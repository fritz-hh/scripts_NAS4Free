#!/bin/sh
############################################################################
# Script aimed at generating a extract of all log files
#
# Author: fritz from NAS4Free forum
#
#############################################################################

readonly SCRIPT_NAME=`basename $0`               # The name of this file
readonly SCRIPT_PATH=`dirname $0`                # The path to the current script

# Import required scripts
. "$SCRIPT_PATH/config.sh"
. "$SCRIPT_PATH/common/commonLogFcts.sh"

# Initialization of the constants
readonly DURATION=604800			# The entries from the last week (duration in sec)
readonly LOG_FILES="$CFG_LOG_FOLDER/*.log"	# The log files to be considered

# Appending the extract of the logs
time_limit=`$BIN_DATE -j -v-"$DURATION"S`
echo "Showing log entries appended after: $time_limit" 
for f in $LOG_FILES; do
	# Only consider files, not folders
	if [ -f "$f" ]; then
		echo ""
		echo "$f"
		echo "----------------------------"
		get_log_entries "$f" "$DURATION"
	fi
done

echo ""
echo ""

# Computing a summary of the errors / warnings that are recorded in all log files
echo "Summary:"
echo "----------------------------"
for f in $LOG_FILES; do
	if [ -f "$f" ]; then
		# check if the log does not contain any new entry
		get_log_entries "$f" "$DURATION" >/dev/null
		if [ $? -eq "2" ]; then
			echo "- $f :	No new log entry available"
		else
			# if the log contains any new entry
			num_warn=`get_log_entries "$f" "$DURATION" | grep -c "$LOG_WARNING"`
			num_err=`get_log_entries "$f" "$DURATION" | grep -c "$LOG_ERROR"`
			
			echo "WARNING: $num_warn	ERROR: $num_err	: $f"
		fi
	fi
done
