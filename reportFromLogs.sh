#!/bin/sh
############################################################################
# Script aimed at generating a extract of all log files
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

# Initialization of the constants
readonly DURATION=604800			# The entries from the last week (duration in sec)
readonly LOG_FILES="$CFG_LOG_FOLDER/*.log"	# The log files to be considered

echo "Script package version: $CFG_VERSION"
time_limit=`$BIN_DATE -j -v-"$DURATION"S`
echo "Showing log entries appended after: $time_limit"

# Appending the extract of the logs
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
printf '%7s %7s %s\n' "WARNING" "ERROR" "log file (\"---\" means: no new log message available)"
for f in $LOG_FILES; do
	if [ -f "$f" ]; then
		# check if the log does not contain any new entry
		get_log_entries "$f" "$DURATION" >/dev/null
		if [ $? -eq "2" ]; then
			printf '%7s %7s %s\n' "---" "---" "$f"
		else
			# if the log contains any new entry
			num_warn=`get_log_entries "$f" "$DURATION" | grep -c "$LOG_WARNING"`
			num_err=`get_log_entries "$f" "$DURATION" | grep -c "$LOG_ERROR"`

			printf '%7d %7d %s\n' "$num_warn" "$num_err" "$f"
		fi
	fi
done
