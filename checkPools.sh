#!/bin/sh
#############################################################################
# Script aimed at checking if all pools are healthy
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

# Initialization of the constants 
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"


##################################
# Scrub all pools
# Return : 0 no problem detected
#	   1 problem detected
##################################
main() {
	local pool

	$BIN_ZPOOL list -H -o name | while read pool; do
		if $BIN_ZPOOL status -x $pool | grep "is healthy">/dev/null; then
			$BIN_ZPOOL status -x $pool | log_info "$LOGFILE"
		else
			$BIN_ZPOOL status $pool | log_error "$LOGFILE"
		fi 
	done

	# Check if the pools are healthy
	if $BIN_ZPOOL status -x | grep "all pools are healthy">/dev/null; then
		return 0
	else
		return 1
	fi
}


log_info "$LOGFILE" "-------------------------------------"
log_info "$LOGFILE" "Starting checking of pools" 

# run script if possible (lock not existing)
run_main "$LOGFILE" "$SCRIPT_NAME"
# in case of error, send mail with extract of log in case of error
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Problem detected in a pool"`

exit 0


##################################
# Change Notes
#
# 2011-01-16:
#	- First version of the script
# 2011-10-21:
#	- Script modified in order to mail only the lines 
#	  that have been written in the logfile during the current execution
# 2011-10-22:
#       - Minor changes to improve code quality
# 2012-08-21:
#       - Create lock file at when starting the execution
#       - Delete lock file at the end of the execution
#       - Prevent several instances of the script to run at the same time
# 2012-12-17:
#	- Variable TMPFILE renamed in LOGFILE
#	- constants defining path to utilities (like date, rm...) moved to config.sh
#       - log why the script could not be started (differentiate the return codes)
# 2012-12-24:
#       - corrected text in log error
# 2013-01-04:
#       - do not send a error mail in case the NAS is about to shut down
# 2013-01-12:
#       - lock management moved to fct "run_main" 
# 2013-01-13:
#       - few variables declared readonly 
##################################
