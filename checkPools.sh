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
. "$SCRIPT_PATH/common/commonLogFcts.sh"
. "$SCRIPT_PATH/common/commonMailFcts.sh"
. "$SCRIPT_PATH/common/commonLockFcts.sh"

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

