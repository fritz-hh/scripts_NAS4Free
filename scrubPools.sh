#!/bin/sh
#############################################################################
# Script aimed at scrubing all zpools in order to find checksum errors
#
# Author: fritz from NAS4Free forum
#
#############################################################################

# Initialization of the script name
readonly SCRIPT_NAME=`basename $0` 		# The name of this file

# set script path as working directory
cd "`dirname $0`"

# Import required scripts
. "config.sh"
. "common/commonLogFcts.sh"
. "common/commonMailFcts.sh"
. "common/commonLockFcts.sh"

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
# in case of error, send mail with extract of log file
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Issue detected during scrubbing"`

exit 0


