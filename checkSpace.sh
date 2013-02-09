#!/bin/sh
#############################################################################
# Script aimed at checking if the quota of the filesystem is nearly reached
#
# Author: fritz from NAS4Free forum
#
# Param 1: Filesystem to be monitored
# Param 2: Threshold in percent above which a notification mail shall be sent
#############################################################################

# Initialization of the script name and path constants
readonly SCRIPT_NAME=`basename $0` 		# The name of this file
readonly SCRIPT_PATH=`dirname $0`		# The path to the current script

# Import required scripts
. "$SCRIPT_PATH/config.sh"
. "$SCRIPT_PATH/common/commonLogFcts.sh"
. "$SCRIPT_PATH/common/commonMailFcts.sh"
. "$SCRIPT_PATH/common/commonLockFcts.sh"

# Set variables corresponding to the input parameters
readonly FILESYSTEM="$1" 	# name of the filesystem to be monitored
readonly WARN_THRESHOLD="$2"

# Initialization of the constants 
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`
readonly FS_WITHOUT_SLASH=`echo "$FILESYSTEM" | sed 's!/!_!'`    	# The fs without '/' that is not allowed in a file name
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.$FS_WITHOUT_SLASH.log"


##################################
# Get the quota for a given filesystem 
# param 1: filesystem name 
# Return : quota in byte (0 if no quota was set)
##################################
getQuota() {
	local fs
	fs="$1"

	# compute the quota of the filesystem in bytes
	$BIN_ZFS get -o value -Hp quota $fs
}

##################################
# Get the used space for a given filesystem
# param 1: filesystem name 
# Return : used space in byte
##################################
getUsed() {
	local fs
	fs="$1"

	# compute the used size of the filesystem in bytes
	$BIN_ZFS get -o value -Hp used $fs
}

##################################
# Get the available space for a given filesystem
# param 1: filesystem name 
# Return : available space in byte
##################################
getAvailable() {
	local fs
	fs="$1"

	# compute the used size of the filesystem in bytes
	$BIN_ZFS get -o value -Hp avail $fs
}

################################## 
# Main 
##################################
main() {
	local returnCode quota used avail percent mib

	returnCode=0
	mib=$((1024*1024))

	# Check the space for the filesystem (and for all sub-fs recursively)
	for subfilesystem in `$BIN_ZFS list -H -r -o name $FILESYSTEM`; do

		quota=`getQuota $subfilesystem`
		used=`getUsed $subfilesystem`
		avail=`getAvailable $subfilesystem`
		percent=$(($used*100/($used+$avail)))
	
		log_info "$LOGFILE" "$subfilesystem: avail: $((avail/mib)) MiB , used: $((used/mib)) MiB [$percent percent] , quota: $((quota/mib)) MiB"

		# Check if the warning limit is reached		
		if [ $percent -gt $WARN_THRESHOLD ] ; then
			log_warning "$LOGFILE" "Notification threshold reached !"	
			log_warning "$LOGFILE" "Consider increasing quota or adding disk space"	
			returnCode=1
		fi
	done

	return $returnCode
}
        

log_info "$LOGFILE" "-------------------------------------"
log_info "$LOGFILE" "Configured warning threshold: $WARN_THRESHOLD percent"

# run script if possible (lock not existing)
run_main "$LOGFILE" "$SCRIPT_NAME.$FS_WITHOUT_SLASH"
# in case of error, send mail with extract of log in case of error
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Checkspace issue"`

exit 0

