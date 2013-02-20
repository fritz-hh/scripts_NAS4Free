#!/bin/sh
#############################################################################
# Script aimed at performing a backup of a ZFS filesystem (fs) and of all 
# sub-filesystems recursively to a filesystem located on another ZFS filesystem
# The other filesystem can be either on the local host or on a remote host 
#
# Author: fritz from NAS4Free forum
#
# Usage: backupData.sh [-r user@host] [-b maxRollbck] fsSource fsDest
#
#	-r user@host:	Specify a remote host on which the destination filesystem is located
#			Prerequisite: An ssh server shall be running on the host and
#			public key authentication shall be available
#			(By default the destination filesystem is on the local host)
#			host: ip address or name of the host computer
#			user: name of the user on the host computer
#	-b maxRollbck :	Biggest allowed rollback (in days) on the destination fs.
#			A rollback is necessary if the snapshots available on the 
#			destination fs are not available anymore on the source fs
#			Default value: 10 days
#	fsSource : 	zfs filesystems to be backed-up (source).
#	   		Several file systems can be provided (They shall be separated by a comma ",")
#	   		Note: These fs (as well as the sub-fs) shall have a default mountpoint
# 	fsDest : 	zfs filesystem in which the data should be backed-up (destination)
#			Note: This filesystem must already exist before to launch the backup.
#
# Example: 
#	"backupData.sh tank/nas_scripts tank_backup" will create a backup of the ZFS fs 
#	"tank/nas_scripts" (and of all its sub-filesystems) in the ZFS fs "tank_backup".
#	I.e. After the backup (at least) an fs "tank_backup/tank/nas_scripts" will exist.
#
#############################################################################

# Initialization of the script name and path constants
readonly SCRIPT_NAME=`basename $0` 		# The name of this file
readonly SCRIPT_PATH=`dirname $0`		# The path of the file

# import the file containing the defition of the common functions
. "$SCRIPT_PATH/config.sh"
. "$SCRIPT_PATH/common/commonSnapFcts.sh"
. "$SCRIPT_PATH/common/commonLogFcts.sh"
. "$SCRIPT_PATH/common/commonMailFcts.sh"
. "$SCRIPT_PATH/common/commonLockFcts.sh"

# Initialization of constants 
readonly START_TIMESTAMP=`$BIN_DATE +"%s"` 
readonly COMPRESSION="gzip"		# Type of compression to be used for the destination fs
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"
readonly TMP_FILE="$CFG_TMP_FOLDER/run_fct_ssh.sh"
readonly S_IN_DAY=86400			# Number of seconds in a day
readonly SSH_BATCHMODE="no"		# Only public key authentication is allowed in batch mode 
					# (should only change to "no" for test purposes)

# Initialization of inputs corresponding to optional args of the script
I_REMOTE_ACTIVE="0"			# By default the destination filesystem is local
RUN_FCT_SSH=""				# This should be put in front of FUNCTIONS that may have to be executed remotely
					# By default (i.e. local backup) "RUN_FCT_SSH" does not have any effect
RUN_CMD_SSH=""				# This should be put in front of COMMANDS that may have to be executed remotely
					# By default (i.e. local backup) "RUN_CMD_SSH" does not have any effect
I_MAX_ROLLBACK_S=$((10*$S_IN_DAY))	# Default value of max rollback

# Set variables corresponding to the input parameters
ARGUMENTS="$@"


##########################
# Run a function on a remote server
# functions available the following local files are supported:
# - commonSnapFcts.sh 
# 
# This function does not support to get data through PIPES
#
# Params: The command as well as all arguments of the command
# Run local functions remotely
##########################
run_fct_ssh() {
	local return_code

	# generating the tmp file containing the code to be executed
	cat "$SCRIPT_PATH/config.sh" > $TMP_FILE
	cat "$SCRIPT_PATH/common/commonSnapFcts.sh" >> $TMP_FILE 
	echo "$@" >>  $TMP_FILE
	
	# remote the code on the remote host
	$BIN_SSH -oBatchMode=$SSH_BATCHMODE -t $I_REMOTE_LOGIN "/bin/sh" < $TMP_FILE
	return_code="$?"
	
	# delete the tmp file
	$BIN_RM $TMP_FILE
	
	return $return_code
}


################################## 
# Check script input parameters
#
# Params: all parameters of the shell script
##################################
parseInputParams() {
	local opt current_fs regex_rollback host

	# parse the optional parameters
	# (there should be none)
	while getopts ":r:b:" opt; do
        	case $opt in
			r)	echo "$OPTARG" | grep -E "^(.+)@(.+)$" >/dev/null 
				if [ "$?" -eq "0" ] ; then
					I_REMOTE_ACTIVE="1"
					I_REMOTE_LOGIN="$OPTARG"
					
					# set variables to ensure remote execution of
					# some parts of the script
					RUN_FCT_SSH="run_fct_ssh"
					RUN_CMD_SSH="$BIN_SSH -oBatchMode=$SSH_BATCHMODE $I_REMOTE_LOGIN"
					
					# ping to test if remote host is accessible
					host=`echo "$I_REMOTE_LOGIN" | cut -f2 -d@`
					if $BIN_PING -c 1 -t 1 $host > /dev/null ; then
						log_info "$LOGFILE" "Ping remote host \"$host\" successful"
					else
						log_error "$LOGFILE" "Ping remote host \"$host\" failed"
						return 1
					fi
					
					# testing ssh connection
					if $RUN_CMD_SSH exit 0; then
						log_info "$LOGFILE" "SSH connection test successful."
					else					
						log_error "$LOGFILE" "SSH connection failed. Please check username / hostname and ensure availability of public key authentication"
						return 1
					fi
				else
					log_error "$LOGFILE" "Remote login data (\"$OPTARG\") does not have the expect format: username@hostname"
					return 1
				fi ;;
			b)	echo "$OPTARG" | grep -E "^([0-9]+)$" >/dev/null 
				if [ "$?" -eq "0" ] ; then
					I_MAX_ROLLBACK_S=$(($OPTARG*$S_IN_DAY))
				else
					log_error "$LOGFILE" "Wrong maximum rollback value, should be a positive integer or zero (unit: days) !"
					return 1
				fi ;;
			\?)
				log_error "$LOGFILE" "Invalid option: -$OPTARG"
				return 1 ;;
                        :)
				log_error "$LOGFILE" "Option -$OPTARG requires an argument"
				return 1 ;;
        	esac
	done

	# Remove the optional arguments parsed above.
	shift $((OPTIND-1))
	
	# Check if the number of mandatory parameters 
	# provided is as expected 
	if [ "$#" -ne "2" ]; then
		log_error "$LOGFILE" "Exactly 2 mandatory argument shall be provided"
		return 1
	fi

	# Itterate through all source filesystems for which a backup should be done
	# and check if the current fs exists	
	I_SRC_FSS=`echo "$1" | sed 's/,/ /g'` # replace commas by space as for loops on new line and space
	for current_fs in $I_SRC_FSS ; do	
		if ! $BIN_ZFS list $current_fs 2>/dev/null 1>/dev/null; then
			log_error "$LOGFILE" "source filesystem \"$current_fs\" does not exist. Skipping it"
			return 1
		fi
	done	
	
	# Check if the destination filesystem exists
	I_DEST_FS="$2"
	if ! $RUN_CMD_SSH $BIN_ZFS list $I_DEST_FS 2>/dev/null 1>/dev/null; then
		log_error "$LOGFILE" "destination filesystem \"$I_DEST_FS\" does not exist."
		return 1
	fi
	
	return 0
}


##################################
# Ensures the availability of the filesystem given as parameter
# Param 1: filesystem name
# Return : 0 if the filesystem is existing or could be created, 
#	   1 otherwise
##################################
ensureRemoteFSExists() {

	local fs pool
	fs="$1"
	pool=`echo "$fs" | cut -f1 -d/`
	
	# Check if the fs already exists
	if $RUN_CMD_SSH $BIN_ZFS list $fs 2>/dev/null 1>/dev/null; then
		return 0
	fi
	
	log_info "$LOGFILE" "Destination filesystem \"$fs\" DOES NOT exist yet. Creating it..."

	# Ensures that the destination pool is NOT readonly
	# So that the filesystems can be created if required
	if ! $RUN_CMD_SSH $BIN_ZFS set readonly=off $pool >/dev/null; then
		log_error "$LOGFILE" "Destination pool could not be set to READONLY=off. Filesystem creation not possible "
		return 1
	fi

	# create the filesystem (-p option to create the parent fs if it does not exist)
	if ! $RUN_CMD_SSH $BIN_ZFS create -p -o compression="$COMPRESSION" "$fs"; then
		log_error "$LOGFILE" "The filesystem could NOT be created"

		# Set the destination pool to readonly
		if ! $RUN_CMD_SSH $BIN_ZFS set readonly=on $pool >/dev/null; then
			log_error "$LOGFILE" "The destination pool could not be set to \"readonly=on\""
		fi

		return 1
	else
		log_info "$LOGFILE" "Filesystem created successfully"

		# Set the destination pool to readonly
		if ! $RUN_CMD_SSH $BIN_ZFS set readonly=on $pool >/dev/null; then
			log_warning "$LOGFILE" "The destination pool could not be set to \"readonly=on\""
		fi

		return 0
	fi
}

##################################
# Backup the source filesystem 
# (but NOT recursively the sub-filesystems)
#
# Param 1: source filesystem
# Param 2: destination filesystem
# Return : 0 if the backup could be performed successfully or 
#	     if there is nothing to backup
#	   1 if the backup failed
##################################
backup() {
	local src_fs dest_fs logPrefix newestSnapDestFs oldestSnapSrcFs newestSnapSrcFs snapDestFs \
		removeDestFSInName snapSrcFs snapSrcFsTimestamp1970 newestSnapDestFsCreation1970 \
		snapsAgeDiff

	src_fs="$1"
	dest_fs="$2"

	logPrefix="Backup of \"$src_fs\""
	
	# Get the newest snapshot on dest fs
	newestSnapDestFs=`$RUN_FCT_SSH sortSnapshots "$dest_fs" "" | head -n 1`
	# Get the oldest snapshot on the src fs
	oldestSnapSrcFs=`sortSnapshots "$src_fs" "" | tail -n -1`
	# Get the newest snapshot on the src fs
	newestSnapSrcFs=`sortSnapshots "$src_fs" "" | head -n 1`

	# If there is no snapshot on dest fs, backup the oldest snapshot on the src fs
	if [ -z "$newestSnapDestFs" ]; then
		log_info "$LOGFILE" "$logPrefix: No snapfound found in destination filesystem"

		if [ -z "$oldestSnapSrcFs" ]; then
			log_info "$LOGFILE" "$logPrefix: No snapshot to be backed up found in source filesystem"
			return 0
		else
			log_info "$LOGFILE" "$logPrefix: Backup up oldest snapshot \"$oldestSnapSrcFs\""
			if ! $BIN_ZFS send $oldestSnapSrcFs | $RUN_CMD_SSH $BIN_ZFS receive -F $dest_fs >/dev/null; then
				log_error "$LOGFILE" "$logPrefix: Backup failed"
				return 1
			else
				log_info "$LOGFILE" "$logPrefix: Backup performed"
			fi
		fi
	else
		log_info "$LOGFILE" "$logPrefix: Last snapshot available in destination filesystem was \"$newestSnapDestFs\" before backup"
	fi

	# Get the newest snapshot on the dest fs
	# (It may have changed, if a backup was performed above)
	newestSnapDestFs=`$RUN_FCT_SSH sortSnapshots $dest_fs "" | head -n 1`

	# find the newest snapshot on the dest fs that is still
	# available in the src fs and then perform an incremental 
	# backup starting from the latter snapshot
	for snapDestFs in `$RUN_FCT_SSH sortSnapshots "$dest_fs" ""`; do

		# Compute the src fs snapshot name corresponding to the current dest fs snapshot
		removeDestFSInName="s!$I_DEST_FS/!!g"
		snapSrcFs=`echo "$snapDestFs" | sed -e "$removeDestFSInName"`

		if [ $snapSrcFs = $newestSnapSrcFs ]; then
			log_info "$LOGFILE" "$logPrefix: No newer snapshot exist in source filesystem. Nothing to backup"
			return 0
		fi

		# If the snapshot exists on the src fs
		if $BIN_ZFS list -o name -t snapshot "$snapSrcFs" 2>/dev/null 1>/dev/null; then

			# Compute the required rollback duration
			snapSrcFsTimestamp1970=`getSnapTimestamp1970 "$snapSrcFs"`
			newestSnapDestFsCreation1970=`$RUN_FCT_SSH getSnapTimestamp1970 "$newestSnapDestFs"`		
			snapsAgeDiff=$(($newestSnapDestFsCreation1970-$snapSrcFsTimestamp1970))
			if [ $snapsAgeDiff -gt $I_MAX_ROLLBACK_S ]; then
				log_warning "$LOGFILE" "$logPrefix: A rollback of \"$(($snapsAgeDiff/$S_IN_DAY))\" days would be required to perform the incremental backup !"
				log_warning "$LOGFILE" "$logPrefix: Current maximum allowed rollback value equals \"$(($I_MAX_ROLLBACK_S/$S_IN_DAY))\" days."
				log_warning "$LOGFILE" "$logPrefix: Please increase the maximum allowed rollback duration to make the backup possible"
				log_warning "$LOGFILE" "$logPrefix: Skipping backup of this filesystem"
				return 1
			fi

			log_info "$LOGFILE" "$logPrefix: Rolling back to last snapshot available on both source & destination fs: \"$snapDestFs\"..."
			if ! $RUN_CMD_SSH $BIN_ZFS rollback -r $snapDestFs >/dev/null; then
				log_error "$LOGFILE" "$logPrefix: Rollback failed"
				return 1
			fi

			log_info "$LOGFILE" "$logPrefix: Backing up incrementally from snapshot \"$snapSrcFs\" to \"$newestSnapSrcFs\" ..."
			if ! $BIN_ZFS send -I "$snapSrcFs" "$newestSnapSrcFs" | $RUN_CMD_SSH $BIN_ZFS receive "$dest_fs" >/dev/null; then
				log_error "$LOGFILE" "$logPrefix: Backup failed"
				return 1
			else
				log_info "$LOGFILE" "$logPrefix: Backup performed"
				return 0
			fi
		fi
	done
}

################################## 
# Main 
##################################
main() {
	local returnCode current_fs currentSubSrcFs 

	returnCode=0	

	log_info "$LOGFILE" "-------------------------------------"	

	# Parse the input parameters
	if ! parseInputParams $ARGUMENTS; then
		return 1
	fi
	
	log_info "$LOGFILE" "Starting backup of \"$I_SRC_FSS\""

	# Itterate through all source filesystems for which a backup should be done
	for current_fs in $I_SRC_FSS ; do
	
		# for the current fs and all its sub-filesystems
		for currentSubSrcFs in `$BIN_ZFS list -r -H -o name $current_fs`; do

			# create the dest filesystems (recursively) 
			# if they do not yet exist and exit if it fails
			if ! ensureRemoteFSExists "$I_DEST_FS/$currentSubSrcFs"; then
				returnCode=1
			else
				# Perform the backup
				backup $currentSubSrcFs "$I_DEST_FS/$currentSubSrcFs"
				if [ "$?" -ne "0" ]; then
					returnCode=1
				fi
			fi
		done
	done	

	return $returnCode 
}



# run script if possible (lock not existing)
run_main "$LOGFILE" "$SCRIPT_NAME"
# in case of error, send mail with extract of log file
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Backup issue"`

exit 0

