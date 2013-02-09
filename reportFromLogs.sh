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
. "$SCRIPT_PATH/commonLogFcts.sh"

# Initialization of the constants
readonly DURATION=604800	# The entries from the last week (duration in sec)
readonly LOG_FILES="$CFG_LOG_FOLDER/*.log"

time_limit=`$BIN_DATE -j -v-"$DURATION"S`
echo "Showing log entries appended after: $time_limit" 

# Generating the report
for f in $LOG_FILES
do
	# Only consider files, not folders
	if [ -f "$f" ]; then
		echo ""
		echo "$f"
		echo "----------------------------"
		get_log_entries "$f" "$DURATION"
	fi
done

##################################
# Change Notes
#
# 2010-01-03:
#	First issue of the script
# 2012-12-17:
#	- constants defining path to utilities (like date) moved to config.sh
# 2012-12-22:
#	- minor bugfix
# 2013-01-13:
#	- few variables declared readonly
##################################

