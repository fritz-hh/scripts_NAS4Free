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
. "$SCRIPT_PATH/commonLogFcts.sh"
. "$SCRIPT_PATH/commonMailFcts.sh"
. "$SCRIPT_PATH/commonLockFcts.sh"

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


##################################
# Change Notes
#
# 2011-01-02:
#	First version of the script
# 2011-01-04:
#	- "#" removed from the lines aimed at sending a notification mail
#	- Bug fix in the formula aimed at computing the usage of the disks (in percent) 
# 2011-08-11:
#	- Script improved to log the exact sizes in bytes instead
#	  of truncating the size to the next kB, MB or GB
# 2011-09-11:
#	- Script improved in order to work with zpools that have been exported before
# 2011-09-12:
#	- Minor changes in logging
# 2011-10-09:
#	- Name of the log file modified to contain the filesystem name
# 2011-10-21:
#       - Script modified in order to mail only the lines
#         that have been written in the logfile during the current execution
# 2011-10-22:
#	- Configured warning threshold for disk usage now appended in log file
#       - Minor changes to improve code quality
# 2012-08-21:
#       - Create lock file at when starting the execution
#       - Delete lock file at the end of the execution
#       - Prevent several instances of the script to run at the same time
# 2012-09-25:
#       - Pool not imported / exported anymore
# 2012-12-14:
#       - "%" character remove from the log file (because of incompatibility
#	  with the mail function
# 2012-12-17:
#       - Variable TMPFILE renamed in LOGFILE
#	- constants defining path to utilities (like date, rm...) moved to config.sh
#       - log why the script could not be started (differentiate the return codes)
#       - allow 2 instances for difference FS to run concurrently
# 2012-12-18:
#       - Bugfix: the wrong lock id was passed to script_end()
# 2012-12-24:
#       - corrected text in log error
# 2013-01-02:
#       - reference to obsolete script commonPoolFct.sh removed
# 2013-01-04:
#       - do not send a error mail in case the NAS is about to shut down
# 2013-01-07:
#       - display size in MiB (instead of byte) for readability
# 2013-01-08:
#       - minor changes in declaration of local variables
# 2013-01-12:
#       - lock management moved to fct "run_main"
# 2013-01-13:
#       - few variables declared readonly
# 2013-01-25:
#       - minor change in data logged
##################################
