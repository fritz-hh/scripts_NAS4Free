#!/bin/sh
#############################################################################
# Script aimed at scrubing all zpools in order to find checksum errors
#
# Author: fritz from NAS4Free forum
#
#############################################################################

# Initialization of the script name and path constants
readonly SCRIPT_NAME=`basename $0` 		# The name of this file
readonly SCRIPT_PATH=`dirname $0`		# The path to the current script

# Import required scripts
. "$SCRIPT_PATH/config.sh"
. "$SCRIPT_PATH/commonLogFcts.sh"
. "$SCRIPT_PATH/commonMailFcts.sh"
. "$SCRIPT_PATH/commonLockFcts.sh"

# Record the timestamp corresponding to the start of the script execution
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`

# Initialization of the constants 
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"


##################################
# Check if scrubing is still in progress for a given pool
# Return : 0 if scrub is in progress,
#	   1 otherwise
##################################
scrubInProgress() {
	if $BIN_ZPOOL status | grep "scrub in progress">/dev/null; then
		return 0
	else
		return 1
	fi
}

##################################
# Scrub all pools
# Return : 0 no problem detected
#	   1 problem detected
##################################
main() {

	# Starting scrubbing
	$BIN_ZPOOL list -H -o name | while read pool; do
		$BIN_ZPOOL scrub $pool
		log_info "$LOGFILE" "Starting srubbing of pool: $pool" 
	done

	# Waiting for the end of the scrubbing
	while scrubInProgress; do sleep 10; done;
	log_info "$LOGFILE" "Scrub finished for all pools" 

	# Check if the pools are healthy
	if $BIN_ZPOOL status -x | grep "all pools are healthy">/dev/null; then
		$BIN_ZPOOL status -x | log_info "$LOGFILE"
		return 0
	else
		$BIN_ZPOOL status | log_error "$LOGFILE"
		return 1
	fi
}


log_info "$LOGFILE" "-------------------------------------"
log_info "$LOGFILE" "Starting srubbing" 

# run script if possible (lock not existing)
run_main "$LOGFILE" "$SCRIPT_NAME"
# in case of error, send mail with extract of log in case of error
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Issue detected during scrubbing"`

exit 0



##################################
# Change Notes
#
# 2010-08-15:
#	- Initial version written for opensolaris 2009.06
# 2010-12-29:
#	- Script modified for FreeNAS 0.7.2
#	- Successive calls of the script saved in the same log file (instead of creating
#	  a log file for each call
# 2010-12-30:
#	- Mail sent in case an issue was detected
# 2011-10-21:
#       - Script modified in order to mail only the lines
#         that have been written in the logfile during the current execution
# 2011-10-22:
#       - Minor changes to improve code quality
# 2012-08-21:
#       - Create lock file at when starting the execution
#       - Delete lock file at the end of the execution
#       - Prevent several instances of the script to run at the same time
# 2012-12-17:
#       - Variable TMPFILE renamed in LOGFILE
#	- constants defining path to utilities (like zpool, date...) moved to config.sh
#       - log why the script could not be started (differentiate the return codes)
# 2012-12-24:
#       - corrected text in log error
# 2012-12-29:
#       - scrubbing all pools at concurrently instead of one after the other
#	  in order to save time
# 2013-01-04:
#       - do not send a error mail in case the NAS is about to shut down
# 2013-01-12:
#       - lock management moved to fct "run_main"
# 2013-01-13:
#       - few variables declared readonly
##################################
