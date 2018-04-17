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
readonly TMPFILE_ARGS="$CFG_TMP_FOLDER/$SCRIPT_NAME.$$.args.tmp"

# Set variables corresponding to the input parameters
ARGUMENTS="$@"


################################## 
# Check script input parameters
#
# Params: all parameters of the shell script
# return : 1 if an error occured, 0 otherwise 
##################################
parseInputParams() {
	local opt
	
	# parse the optional parameters
	# (there should be none)
	while getopts ":" opt; do
        	case $opt in
			\?)
				echo "Invalid option: -$OPTARG"
				return 1 ;;
        	esac
	done

	# Remove the optional arguments parsed above.
	shift $((OPTIND-1))
	
	# Check if the number of mandatory parameters 
	# provided is as expected 
	if [ "$#" -ne "0" ]; then
		echo "No mandatory arguments should be provided"
		return 1
	fi
	
	return 0
}

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
	log_info "$LOGFILE" "Starting scrubbing" 
	$BIN_ZPOOL list -H -o name | while read pool; do
		$BIN_ZPOOL scrub $pool
		log_info "$LOGFILE" "Starting scrubbing of pool: $pool" 
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



# Parse and validate the input parameters
if ! parseInputParams $ARGUMENTS > "$TMPFILE_ARGS"; then
	log_info "$LOGFILE" "-------------------------------------"
	cat "$TMPFILE_ARGS" | log_error "$LOGFILE"
	get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "$SCRIPT_NAME : Invalid arguments"
else
	log_info "$LOGFILE" "-------------------------------------"
	cat "$TMPFILE_ARGS" | log_info "$LOGFILE"

	# run script if possible (lock not existing)
	run_main "$LOGFILE" "$SCRIPT_NAME"
	# in case of error, send mail with extract of log file
	[ "$?" -eq "2" ] && get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "$SCRIPT_NAME : issue occured during execution"
fi

$BIN_RM "$TMPFILE_ARGS"
exit 0

