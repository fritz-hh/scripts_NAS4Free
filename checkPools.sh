#!/bin/sh
#############################################################################
# Script aimed at checking if all pools are healthy
#
# Author: fritz from NAS4Free forum
#
#############################################################################

# Initialization of the script name
readonly SCRIPT_NAME=`basename $0`         # The name of this file

# set script path as working directory
cd "`dirname $0`"

# Import required scripts
. "config.sh"
. "common/commonLogFcts.sh"
. "common/commonMailFcts.sh"
. "common/commonLockFcts.sh"

# Initialization of the constants
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`
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
# Scrub all pools
# Return : 0 no problem detected
#       1 problem detected
##################################
main() {
    local pool

    log_info "$LOGFILE" "Starting checking of pools"

    $BIN_ZPOOL list -H -o name | while read pool; do
        if ZPOOL_STATUS_NON_NATIVE_ASHIFT_IGNORE=1 $BIN_ZPOOL status -x $pool | grep "is healthy">/dev/null; then
            ZPOOL_STATUS_NON_NATIVE_ASHIFT_IGNORE=1 $BIN_ZPOOL status -x $pool | log_info "$LOGFILE"
        else
            $BIN_ZPOOL status -v $pool | log_error "$LOGFILE"
        fi
    done

    # Check if the pools are healthy
    if ZPOOL_STATUS_NON_NATIVE_ASHIFT_IGNORE=1 $BIN_ZPOOL status -x | grep "all pools are healthy">/dev/null; then
        return 0
    else
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

