#!/bin/sh
#############################################################################
# Script aimed at performing a backup of a filesystem (fs) and of all 
# sub-filesystems recursively to a filesystem located on another zpool 
#
# Author: fritz from NAS4Free forum
#
# Param 1: zfs filesystems to be backed-up (source).
#	   Several file systems can be provided (They shall be separated by a comma ",")
#	   Note 1: These fs (as well as the sub-fs) shall have a default mountpoint
#	   Note 2: The filesystem provided as parameter shall not contain any space character
# Param 2: zfs pool in which the data should be backed-up (destination)
#	   Note: This pool must already exist before to launch the script 
#	   backup.
# Param 3: Biggest allowed rollback (in days) on the destination fs.
#	   A rollback is necessary if the snapshots available on the 
#	   destination fs are not available anymore on the source fs
#############################################################################

# Initialization of the script name and path constants
readonly SCRIPT_NAME=`basename $0` 		# The name of this file
readonly SCRIPT_PATH=`dirname $0`		# The path of the file

# import the file containing the defition of the common functions
. "$SCRIPT_PATH/config.sh"
. "$SCRIPT_PATH/commonSnapFcts.sh"
. "$SCRIPT_PATH/commonLogFcts.sh"
. "$SCRIPT_PATH/commonMailFcts.sh"
. "$SCRIPT_PATH/commonLockFcts.sh"

# Set variables corresponding to the input parameters
readonly SRC_FSS="$1"				# The source filesystems (i.e. the filesystems to be backed-up)
readonly DEST_POOL="$2" 			# The destination pool (i.e. the pool in 
						# which the backup data shall be saved)
readonly S_IN_DAY=86400				# Number of seconds in a day
readonly MAX_ROLLBACK_S=$(($3*$S_IN_DAY)) 	# Biggest allowed rollback (in seconds) on the destination fs

# Initialization of constants 
readonly START_TIMESTAMP=`$BIN_DATE +"%s"` 
readonly COMPRESSION="gzip"			# Type of compression to be used for the fs of the backup pool
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"

##################################
# Ensures the availability of the filesystem given as parameter
# Param 1: filesystem name
# Return : 0 if the filesystem is existing or could be created, 
#	   1 otherwise
##################################
ensureFsAvailability() {

	local fs
	fs="$1"

	# Check if the fs already exists
	if $BIN_ZFS list -H -o name | grep "^$fs$" >/dev/null; then
		return 0
	fi

	log_info "$LOGFILE" "Destination filesystem \"$fs\" DOES NOT exist yet. Creating it..."

	# Ensures that the destination pool is NOT readonly
	# So that the filesystems can be created if required
	if ! $BIN_ZFS set readonly=off $DEST_POOL >/dev/null; then
		log_error "$LOGFILE" "Destination pool could not be set to READONLY=off. Filesystem creation not possible "
		return 1
	fi

	# create the filesystem (-p option to create the parent fs if it does not exist)
	if ! $BIN_ZFS create -p -o compression="$COMPRESSION" "$fs"; then
		log_error "$LOGFILE" "The filesystem could NOT be created"

		# Set the destination pool to readonly
		if ! $BIN_ZFS set readonly=on $DEST_POOL >/dev/null; then
			log_error "$LOGFILE" "The destination pool could not be set to \"readonly=on\""
		fi

		return 1
	else
		log_info "$LOGFILE" "Filesystem created successfully"

		# Set the destination pool to readonly
		if ! $BIN_ZFS set readonly=on $DEST_POOL >/dev/null; then
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
		removeDestPoolInName snapSrcFs snapSrcFsTimestamp1970 newestSnapDestFsCreation1970 \
		snapsAgeDiff

	src_fs="$1"
	dest_fs="$2"

	logPrefix="Backup of \"$src_fs\""
	
	# Get the newest snapshot on dest fs
	newestSnapDestFs=`sortSnapshots "$dest_fs" "" | head -n 1`
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
			if ! $BIN_ZFS send $oldestSnapSrcFs | $BIN_ZFS receive -F $dest_fs >/dev/null; then
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
	newestSnapDestFs=`sortSnapshots $dest_fs "" | head -n 1`

	# find the newest snapshot on the dest fs that is still
	# available in the src fs and then perform an incremental 
	# backup starting from the latter snapshot
	for snapDestFs in `sortSnapshots "$dest_fs" ""`; do

		# Compute the src fs snapshot name corresponding to the current dest fs snapshot
		removeDestPoolInName="s!$DEST_POOL/!!g"
		snapSrcFs=`echo "$snapDestFs" | sed -e "$removeDestPoolInName"`

		if [ $snapSrcFs = $newestSnapSrcFs ]; then
			log_info "$LOGFILE" "$logPrefix: No newer snapshot exist in source filesystem. Nothing to backup"
			return 0
		fi

		# If the snapshot exists on the src fs
		if $BIN_ZFS list -o name -t snapshot "$snapSrcFs" 2>/dev/null 1>/dev/null; then

			# Compute the required rollback duration
			snapSrcFsTimestamp1970=`getSnapTimestamp1970 "$snapSrcFs"`
			newestSnapDestFsCreation1970=`getSnapTimestamp1970 "$newestSnapDestFs"`		
			snapsAgeDiff=$(($newestSnapDestFsCreation1970-$snapSrcFsTimestamp1970))
			if [ $snapsAgeDiff -gt $MAX_ROLLBACK_S ]; then
				log_warning "$LOGFILE" "$logPrefix: A rollback of $(($snapsAgeDiff/$S_IN_DAY)) days would be required to perform the incremental backup !"
				log_warning "$LOGFILE" "$logPrefix: Skipping backup of the filesystem"
				log_warning "$LOGFILE" "$logPrefix: Please increase the allowed rollback duration is required"
				return 1
			fi

			log_info "$LOGFILE" "$logPrefix: Rolling back to last snapshot available on both source & destination fs: \"$snapDestFs\"..."
			if ! $BIN_ZFS rollback -r $snapDestFs >/dev/null; then
				log_error "$LOGFILE" "$logPrefix: Rollback failed"
				return 1
			fi

			log_info "$LOGFILE" "$logPrefix: Backing up incrementally from snapshot \"$snapSrcFs\" to \"$newestSnapSrcFs\" ..."
			if ! $BIN_ZFS send -I "$snapSrcFs" "$newestSnapSrcFs" | $BIN_ZFS receive "$dest_fs" >/dev/null; then
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
	local src_fss2 returnCode current_fs currentSubSrcFs 
	
	returnCode=0

	#Itterate through all source filesystems for which a backup should be done
	src_fss2=`echo $SRC_FSS | sed 's/,/ /g'` # replace commas by space as for loops on new line and space
	for current_fs in $src_fss2 ; do	
		
		for currentSubSrcFs in `$BIN_ZFS list -r -H -o name $current_fs`; do
	
			# create the dest filesystems (recursively) 
			# if they do not yet exist and exit if it fails
			if ! ensureFsAvailability "$DEST_POOL/$currentSubSrcFs"; then
                        	returnCode=1
			else
			# Perform the backup
				backup $currentSubSrcFs "$DEST_POOL/$currentSubSrcFs"
                		if [ "$?" -ne "0" ]; then
                        		returnCode=1
                		fi
			fi
		done
	done	

	return $returnCode 
}



log_info "$LOGFILE" "-------------------------------------"
log_info "$LOGFILE" "Starting backup of \"$SRC_FSS\""

# run script if possible (lock not existing)
run_main "$LOGFILE" "$SCRIPT_NAME"
# in case of error, send mail with extract of log in case of error
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Backup issue"`

exit 0


####################################################################
# Change Notes:
#
# 2010-03-08:
#	- Script creation
# 2010-03-09:
#	- Script now ensures that the dest pool is readonly
#	- Robusteness improved (e.g. detection of problems during backup)
# 2010-03-10:
#	- Script enhanced to support automatic backup of sub-filesystems recursively
#	- Bug corrected: fs could not be created because read-only was set
#	  at the wrong place
#	- Various improvements in the log file generation
#	- Bug corrected: if the last snapshot on dest fs cannot be found,
#	  performs rollback instead of destroying the respective snapshot
# 2010-03-12:
#	- 'export of the dest pool' put in a dedicated function, 
#	  and called if an error occurs
# 2010-03-13:
#	- 'set the pool to read only' put directly into the function aimed
#	  at ensuring the availability of the filesystems
#	- Comments improved in the code
#	- Check added in order to avoid that big rollbacks are performed
#	  (on the dest fs), in case no newer common snapshot 
#	  is found
# 2010-03-15:
#	- Check added in order to verify if each fs to be backed-up
#	  has a default "mountpoint". (Only the default mountpoint is supported
#	  by the script)
#	- Common functions put into another shell script, used in this script
# 2010-08-15:
#	location of the log file changed to "/export/home/xxxxx/scripts/logs"
#	instead of "/export/home/xxxxx/scripts/logs"
# 2010-08-22:
#	- Minor changes in the comments
# 2011-01-01:
#	- Script modified to run with freeNAS 0.7.2
#	- Logging modified to harmonize the format of the log file
#	- Send a mail in case an issue is detected
# 2011-10-21:
#       - Script modified in order to mail only the lines
#         that have been written in the logfile during the current execution
# 2011-10-22:
#       - Minor changes to improve code quality
# 2012-01-02:
#       - Minor changes to improve code quality
# 2012-08-21:
#       - Create lock file at when starting the execution
#       - Delete lock file at the end of the execution
#       - Prevent several instances of the script to run at the same time
# 2012-09-17:
#       - Added possibility to define several filesystems to be backuped
# 2012-09-18:
#       - Bug fix: In case a backup is requested for an fs but not for its parent, the parent
#	  fs is created automatically in the backup pool (but no backup is done for
#	  the latter fs)
# 2012-09-25:
#       - Backup pool not imported / exported anymore 
# 2012-12-17:
#       - Variable TMPFILE renamed in LOGFILE 
#	- constants defining path to utilities (like date, rm...) moved to config.sh
#       - log why the script could not be started (differentiate the return codes)
# 2012-12-24:
#       - corrected text in log error
# 2013-01-02:
#       - reference to obsolete script commonPoolFct.sh removed
# 2013-01-04:
#       - do not send a error mail in case the NAS is about to shut down
# 2013-01-06:
#       - minor changes induced by changes in "commonSnapFcts.sh"
# 2013-01-08:
#       - minor changes in declaration of local variables 
# 2013-01-12:
#       - lock management moved to fct "run_main" 
# 2013-01-14:
#       - few variables declared readonly 
####################################################################
