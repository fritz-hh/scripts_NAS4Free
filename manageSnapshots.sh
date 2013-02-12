#!/bin/sh
#############################################################################
# Script aimed performing a snapshot of a ZFS filesystem (and of the
# sub-filesystems recursively) and aimed at removing old and superfluous 
# snapshots of that filesystem
#
# This script shall be called hourly.
# It ensures itself that a configured number of hourly, daily, weekly 
# and monthly snapshots are kept.
#
# Author: fritz from NAS4Free forum
#
# Usage: manageSnapshots.sh [-n] [-h num] [-d num] [-w num] [-m num] [-k] filesystem
#
# 	-n : Do not create a new snapshot of the file system
#	-h num : Keep 'num' hourly snapshots (by default: 24) (<0 for all) 
#	-d num : Keep 'num' daily snapshots (by default: 15) (<0 for all)
#	-w num : Keep 'num' weekly snapshots (by default: 8) (<0 for all)
#	-m num : Keep 'num' monthly snapshots (by default: 12) (<0 for all)
#	-k : Keep all snapshots (This option superseeds -h, -d, -w, -m)
#	filesystem : zfs filesystem for which a snapshot shall be created
#############################################################################

# Initialization of the script name and path constants
readonly SCRIPT_NAME=`basename $0` 		# The name of this file
readonly SCRIPT_PATH=`dirname $0`		# The path of the file

# import the other required scripts
. "$SCRIPT_PATH/config.sh"
. "$SCRIPT_PATH/common/commonSnapFcts.sh"
. "$SCRIPT_PATH/common/commonLogFcts.sh"
. "$SCRIPT_PATH/common/commonMailFcts.sh"
. "$SCRIPT_PATH/common/commonLockFcts.sh"

# Record the timestamp corresponding to the start of the script execution
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`

# Set variables corresponding to the input parameters
ARGUMENTS="$@"

# Initialization of the constants
GENERATE_SNAPSHOT=1	# By default, the script shall generate snapshots (1=true)

MAX_NB_HOURLY=24	# Default number of hourly snapshots to be kept
MAX_NB_DAILY=15		# Default number of daily snapshots to be kept
MAX_NB_WEEKLY=8		# Default number of weekly snapshots to be kept
MAX_NB_MONTHLY=12	# Default number of monthly snapshots to be kept

readonly S_IN_HOUR=36000	# Number of seconds in an hour
readonly S_IN_DAY=86400		# Number of seconds in a day
readonly S_IN_WEEK=604800	# Number of seconds in a week
readonly S_IN_MONTH=2629744	# Number of seconds in a month

readonly HOURLY_TAG="type01"	# It is important that the changing part of the tag are exactly 2 digits	
readonly DAILY_TAG="type02"	# in order to be able to show all tags in the windows shadow copy client
readonly WEEKLY_TAG="type03"	# Shadow copy should be enable in the NAS4Free GUI under
readonly MONTHLY_TAG="type04"	# Services|CIFS/SMB|Shares

# get the mandatory script parameter (Filesystem for which a snapshot shall be created) 	
if [ $# -gt 0 ]; then
	eval FILESYSTEM=\$$#				# Filesystem to snapshot
else
	echo "Name of the filesystem to snapshot not provided when calling \"$SCRIPT_NAME\"" | sendMail "Snapshot management issue"
	exit 1
fi

# Initialization of the log file path
readonly FS_WITHOUT_SLASH=`echo "$FILESYSTEM" | sed 's!/!_!'`	# The fs without '/' that is not allowed in a file name
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.$FS_WITHOUT_SLASH.log"

################################## 
# Check script input parameters
#
# Params: all parameters of the shell script
##################################
parseOptionalInputParams() {
	local keep_all_snap opt
	
	keep_all_snap="0"

	# parse the optional parameters
	while getopts ":nh:d:w:m:k" opt; do
		case $opt in
			n) 	GENERATE_SNAPSHOT=0 ;;
			h) 	echo "$OPTARG" | grep '^[1-9-][0-9]*$' >/dev/null	# Check if positive or negative integer
				if [ "$?" -eq "0" ] ; then 
					MAX_NB_HOURLY="$OPTARG" 
				else
					log_error "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -h. Should be an integer."
					return 1
				fi ;;
			d) 	echo "$OPTARG" | grep '^[1-9-][0-9]*$' >/dev/null	# Check if positive or negative integer
				if [ "$?" -eq "0" ] ; then 
					MAX_NB_DAILY="$OPTARG" 
				else
					log_error "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -h. Should be an integer."
					return 1
				fi ;;
			w) 	echo "$OPTARG" | grep '^[1-9-][0-9]*$' >/dev/null	# Check if positive or negative integer
				if [ "$?" -eq "0" ] ; then 
					MAX_NB_WEEKLY="$OPTARG" 
				else
					log_error "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -h. Should be an integer."
					return 1
				fi ;;
			m) 	echo "$OPTARG" | grep '^[1-9-][0-9]*$' >/dev/null	# Check if positive or negative integer
				if [ "$?" -eq "0" ] ; then 
					MAX_NB_MONTHLY="$OPTARG" 
				else
					log_error "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -h. Should be an integer."
					return 1
				fi ;;
			k) 	keep_all_snap="1" ;;
			\?)
				log_error "$LOGFILE" "Invalid option: -$OPTARG"
				return 1 ;;
			:)
				log_error "$LOGFILE" "Option -$OPTARG requires an argument"
				return 1 ;;
		esac
	done

	# If the keep all snapshots was selected
	if [ $keep_all_snap -eq "1" ]; then
		MAX_NB_HOURLY="-1"
		MAX_NB_DAILY="-1"
		MAX_NB_WEEKLY="-1"
		MAX_NB_MONTHLY="-1"
	fi

	return 0
}

################################## 
# Compute the age in s of the newest snapshot of a filesystem
# having a given tag
# If no snapshot is available, return the seconds since 1970 
#
# Param 1: filesystem
# Param 2: tag
# Return : age in s
##################################
newestSnapshotAge() {
	local newestSnap snapCreationDate ageSnap

	filesystem="$1"
	tag="$2"
	newestSnap=`sortSnapshots "$filesystem" "$tag" | head -n 1`

	if [ -z "$newestSnap" ]; then
		snapCreationDate="0"
	else
		snapCreationDate=`getSnapTimestamp1970 $newestSnap`
	fi
	
	ageSnap=$((`$BIN_DATE +%s`-$snapCreationDate))
	echo $ageSnap
}

################################## 
# Create a new snapshot of the filesystem (not recursively) 
# This will either create a monthly, weekly, daily or hourly snapshot
# depending how old the last respective snapshot is 
#
# Param 1: filesystem
##################################
createSnapshot() {
	local filesystem ageMonthlySnap ageWeeklySnap ageDailySnap \
		now newSnapshotName fullNewSnapshotname
	
	filesystem="$1"

	ageMonthlySnap=`newestSnapshotAge "$filesystem" "$MONTHLY_TAG"`
	ageWeeklySnap=`newestSnapshotAge "$filesystem" "$WEEKLY_TAG"`
	ageDailySnap=`newestSnapshotAge "$filesystem" "$DAILY_TAG"`

	# Find out which snapshot tag shall be used
	if [ $MAX_NB_MONTHLY -ne 0 -a $ageMonthlySnap -ge $S_IN_MONTH ]; then
		tag="$MONTHLY_TAG"
	elif [ $MAX_NB_WEEKLY -ne 0 -a $ageWeeklySnap -ge $S_IN_WEEK ]; then
		tag="$WEEKLY_TAG"
	elif [ $MAX_NB_DAILY -ne 0 -a $ageDailySnap -ge $S_IN_DAY ]; then
		tag="$DAILY_TAG"
	elif [ $MAX_NB_HOURLY -ne 0 ]; then  
		tag="$HOURLY_TAG"
	else
		log_info "$LOGFILE" "Currently, no need to create any snapshot for filesystem $filesystem"
		return 0
	fi

	# Create the snapshot
	now=`$BIN_DATE +%s`
	newSnapshotName=`generateSnapshotName "$tag" "$now"`

	fullNewSnapshotname="$filesystem@$newSnapshotName"
	log_info "$LOGFILE" "Creating new snapshot \"$fullNewSnapshotname\""
	if `$BIN_ZFS snapshot $fullNewSnapshotname>/dev/null`; then 
		return 0
	else
		log_error "$LOGFILE" "Problem while creating snapshot $fullNewSnapshotname (A snapshot having the same name may already exist)"
		return 1
	fi
}


##################################
# Delete old snapshots for the filesystem given as parameter
# Note: Snapshots for subfile systems are ALSO deleted
#
# Param 1: zfs filesystem for which a snapshot shall be deleted
# Param 2: the snapshot tag to be considered
# Param 3: max number of snapshots to be kept (all are kept if value is negative)
##################################
deleteOldSnapshots() {
	local filesystem tag maxNb returnCode subfs
        
	filesystem="$1"
	tag="$2"
	maxNb="$3"

	returnCode=0
        
	log_info "$LOGFILE" "Analyzing snapshots with tag \"$tag\""

	# Check if all snapshots are required to be kept
	if [ "$maxNb" -lt "0" ]; then
		log_info "$LOGFILE" "$filesystem (and sub-filesystems): All snapshots with tag \"$tag\" kept"
		return 0
	fi 

	# Get the list of sub-filesystems from the requested filesystem
	for subfs in `$BIN_ZFS list -H -r -o name $filesystem`; do

		# Delete the snapshots that are too old in the current sub filesystem
		for snapshot in `sortSnapshots $subfs $tag | tail -n +$((maxNb+1))`; do

			# Destroy the snapshots that are too old
			if ! $BIN_ZFS destroy $snapshot; then
			        log_error "$LOGFILE" "Problem while trying to delete snapshot \"$snapshot\""
			        returnCode=1
			else
				log_info "$LOGFILE" "Snapshot \"$snapshot\" DELETED"
			fi
		done
	done

	return $returnCode
}

################################## 
# Main 
##################################
main() {
	local returnCode
	returnCode=0
	
	# Parse the input parameters
	if ! parseOptionalInputParams $ARGUMENTS; then
		return 1
	fi

	log_info "$LOGFILE" "Keeping up to $MAX_NB_HOURLY hourly / $MAX_NB_DAILY daily / $MAX_NB_WEEKLY weekly / $MAX_NB_MONTHLY monthly snapshots (<0 = all)" 

	# Check if the filesystem for which the snapshots shall be managed is available
	if ! $BIN_ZFS list "$FILESYSTEM">/dev/null; then
		log_error "$LOGFILE" "Unknown file system: \"$FILESYSTEM\""
		return 1
	fi

	# Make a snapshot of all file systems within the filesystem $FILESYSTEM
	if [ "$GENERATE_SNAPSHOT" -eq "1" ]; then
		for subfilesystem in `$BIN_ZFS list -H -r -o name $FILESYSTEM`; do 
			if ! createSnapshot $subfilesystem; then
				returnCode=1	
			fi 
		done
	else
		log_info "$LOGFILE" "Snapshot creation deactivated (no snapshot created)"
	fi

	# Delete the superfluous snapshots
	log_info "$LOGFILE" "Removing superfluous snapshots"
	if ! deleteOldSnapshots "$FILESYSTEM" "$HOURLY_TAG" "$MAX_NB_HOURLY"; then
		returnCode=1	
	fi 
	if ! deleteOldSnapshots "$FILESYSTEM" "$DAILY_TAG" "$MAX_NB_DAILY"; then
		returnCode=1	
	fi 
	if ! deleteOldSnapshots "$FILESYSTEM" "$WEEKLY_TAG" "$MAX_NB_WEEKLY"; then
		returnCode=1	
	fi 
	if ! deleteOldSnapshots "$FILESYSTEM" "$MONTHLY_TAG" "$MAX_NB_MONTHLY"; then
		returnCode=1	
	fi 

	return $returnCode
}




log_info "$LOGFILE" "-------------------------------------"
log_info "$LOGFILE" "Starting snapshot script for dataset \"$FILESYSTEM\""

# run script if possible (lock not existing)
run_main "$LOGFILE" "$SCRIPT_NAME.$FS_WITHOUT_SLASH"
# in case of error, send mail with extract of log file
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Snapshot management issue"`

exit 0


