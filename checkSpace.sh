#!/bin/sh
#############################################################################
# Script aimed at checking if the quota of the ZFS filesystem is nearly reached
#
# Author: fritz from NAS4Free forum
#
# Usage: checkSpace.sh [-f filesystem] [-t threshold]
#
#    -f filesystem : the ZFS filesystem (incl. sub-fs) to be checked
#            default: all ZFS filesystems
#    -t threshold : the threshold in percent above which a notification mail shall be sent
#            value must be between 0 and 99
#            default: 80 (percent)
#############################################################################

# Initialization of the script name
readonly SCRIPT_NAME=`basename $0`  # The name of this file

# set script path as working directory
cd "`dirname $0`"

# Import required scripts
. "config.sh"
. "common/commonLogFcts.sh"
. "common/commonMailFcts.sh"
. "common/commonLockFcts.sh"

# Initialization of the constants
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`
readonly TMPFILE_ARGS="$CFG_TMP_FOLDER/$SCRIPT_NAME.$$.args.tmp"

# default value of the log file
LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"

# Set variables corresponding to the input parameters
ARGUMENTS="$@"

# Initialization of the optional input variables
I_FILESYSTEM=""  # default name of the filesystem to be monitored (meaning: all fs)
I_WARN_THRESHOLD="80"  # space warning threshold default value

##################################
# Check script input parameters
#
# Params: all parameters of the shell script
# return : 1 if an error occured, 0 otherwise
##################################
parseInputParams() {
    local opt fs_without_slash

    # parse the parameters
    while getopts ":f:t:" opt; do
        case $opt in
            f)
                fs_without_slash=`echo "$OPTARG" | sed 's!/!_!g'`  # value of the fs without '/' that is not allowed in a file name
                LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.$fs_without_slash.log"  # value of the log file name
                I_FILESYSTEM="$OPTARG"
             
                if ! $BIN_ZFS list "$OPTARG" 2>/dev/null 1>/dev/null; then  # Check if the zfs file system exists
                    echo "Invalid parameter \"$OPTARG\" for option: -f. The ZFS filesystem does not exist."
                    return 1
                fi
                ;;
            t)
                if ! echo "$OPTARG" | grep -E '^[0-9]{1,2}$' >/dev/null; then
                    echo "Invalid parameter \"$OPTARG\" for option: -t. Should be an integer between 0 and 99."
                    return 1
                fi

                I_WARN_THRESHOLD="$OPTARG"
                ;;
            \?)
                echo "Invalid option: -$OPTARG"
                return 1 ;;
            :)
                echo "Option -$OPTARG requires an argument"
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
# Get the quota for a given filesystem
# param 1: filesystem name
# Return : quota in byte (0 if no quota was set)
##################################
getQuota() {
    local fs q
    fs="$1"

    # compute the quota of the filesystem in byte
    q=`$BIN_ZFS get -o value -Hp quota $fs`
    # check if quota is not a number, for volumes it migh be "-"
    ! [ "$q" -eq "$q" ] 2>/dev/null && q="0"
    echo $q
}

##################################
# Get the used space for a given filesystem
# param 1: filesystem name
# Return : used space in byte
##################################
getUsed() {
    local fs
    fs="$1"

    # compute the used size of the filesystem in byte
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

    # compute the used size of the filesystem in byte
    $BIN_ZFS get -o value -Hp avail $fs
}

##################################
# Main
##################################
main() {
    local returnCode quota used avail percent mib

    returnCode=0
    mib=$((1024*1024))

    log_info "$LOGFILE" "Configured warning threshold: $I_WARN_THRESHOLD percent"

    printf '%14s %13s %13s %13s %s\n' "Used (percent)" "Used (MiB)" "Available" "Quota" "Filesystem" \
        | log_info "$LOGFILE"


    # Check the space for the filesystem (and for all sub-fs recursively)
    for subfilesystem in `$BIN_ZFS list -t filesystem,volume -H -r -o name $I_FILESYSTEM`; do

        quota=`getQuota $subfilesystem`
        used=`getUsed $subfilesystem`
        avail=`getAvailable $subfilesystem`
        percent=$(($used*100/($used+$avail)))

        printf '%14s %13s %13s %13s %s\n' "$percent percent" "$((used/mib)) MiB" "$((avail/mib)) MiB" "$((quota/mib)) MiB" "$subfilesystem" \
            | log_info "$LOGFILE"

        # Check if the warning limit is reached
        if [ $percent -gt $I_WARN_THRESHOLD ] ; then
            log_warning "$LOGFILE" "Notification threshold reached !"
            log_warning "$LOGFILE" "Consider increasing quota or adding disk space"
            returnCode=1
        fi
    done

    return $returnCode
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
    fs_without_slash=`echo "$I_FILESYSTEM" | sed 's!/!_!g'`  # value of the fs without '/' that is not allowed in a file name
    run_main "$LOGFILE" "$SCRIPT_NAME.$fs_without_slash"
    # in case of error, send mail with extract of log file
    [ "$?" -eq "2" ] && get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "$SCRIPT_NAME : issue occured during execution"
fi

$BIN_RM "$TMPFILE_ARGS"
exit 0

