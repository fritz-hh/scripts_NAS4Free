#!/bin/sh
#############################################################################
# Script aimed at performing a backup of a ZFS filesystem (fs) and of all
# sub-filesystems recursively to another filesystem located on another ZPOOL
# The other filesystem can be either on the local host or on a remote host
#
# Author: fritz from NAS4Free forum
#
# Usage: backupData.sh [-s user@host[,path2privatekey]] [-b maxRollbck] [-c compression] fsSource fsDest
#
#    -s user@host[,path2privatekey]: Specify a remote host on which the destination filesystem
#            is located
#            Prerequisite: An ssh server shall be running on the host and
#            public key authentication shall be available
#            (By default the destination filesystem is on the local host)
#            host: ip address or name of the host computer
#            user: name of the user on the host computer
#            path2privatekey: The path to the private key that should be used to
#                login. (This is required either if you are logged under another user
#                in the local host, or if you run the script from cron)
#    -b maxRollbck : Biggest allowed rollback (in days) on the destination fs.
#            A rollback is necessary if the snapshots available on the
#            destination fs are not available anymore on the source fs
#            Default value: 10 days
#    -c compression : compression algorithm to be used for the destination filesystem.
#    fsSource : zfs filesystem to be backed-up (source).
#            Note: This fs shall have a default mountpoint
#    fsDest : zfs filesystem in which the data should be backed-up (destination)
#            Note: The ZPOOL in which this filesystem is located 
#                  must already exist before to launch the backup.
#            Note: The ZPOOL in which this filesystem is located must be different
#                  from the ZPOOL(s) of the source filesystems
#
# Example:
#    "backupData.sh tank/nas_scripts tank_backup" will create a backup of the ZFS fs
#    "tank/nas_scripts" (and of all its sub-filesystems) in the ZFS fs "tank_backup".
#    I.e. After the backup (at least) an fs "tank_backup/nas_scripts" will exist.
#
#############################################################################

# Initialization of the script name
readonly SCRIPT_NAME=`basename $0`  # The name of this file

# set script path as working directory
cd "`dirname $0`"

# Import required scripts
. "config.sh"
. "common/commonSnapFcts.sh"
. "common/commonLogFcts.sh"
. "common/commonMailFcts.sh"
. "common/commonLockFcts.sh"

# Initialization of constants
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`
readonly SUPPORTED_COMPRESSION='on|off|lzjb|gzip|gzip-[1-9]|zle|lz4'
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"
readonly TMP_FILE="$CFG_TMP_FOLDER/run_fct_ssh.sh"
readonly TMPFILE_ARGS="$CFG_TMP_FOLDER/$SCRIPT_NAME.$$.args.tmp"
readonly S_IN_DAY=86400  # Number of seconds in a day
readonly SSH_BATCHMODE="yes"  # Only public key authentication is allowed in batch mode
                    # (should only change to "no" for test purposes)

# Initialization of inputs corresponding to optional args of the script
I_REMOTE_ACTIVE="0"  # By default the destination filesystem is local
RUN_FCT_SSH=""  # This should be put in front of FUNCTIONS that may have to be executed remotely
                # By default (i.e. local backup) "RUN_FCT_SSH" does not have any effect
RUN_CMD_SSH=""  # This should be put in front of COMMANDS that may have to be executed remotely
                # By default (i.e. local backup) "RUN_CMD_SSH" does not have any effect
I_MAX_ROLLBACK_S=$((10*$S_IN_DAY))  # Default value of max rollback

# Set variables corresponding to the input parameters
ARGUMENTS="$@"


##########################
# Run a function on a remote server
# functions available the following local files are supported:
# - commonSnapFcts.sh
#
# This function does not support to get data through PIPES
#
# Params: The command as well as all arguments of the command
# Run local functions remotely
##########################
run_fct_ssh() {
    local return_code

    # generating the tmp file containing the code to be executed
    cat "config.sh" > $TMP_FILE
    cat "common/commonSnapFcts.sh" >> $TMP_FILE
    echo "$@" >>  $TMP_FILE

    # run the code on the remote host
    if [ -z "$I_PATH_KEY" ]; then
        $BIN_SSH -oBatchMode=$SSH_BATCHMODE -t $I_REMOTE_LOGIN "/bin/sh" < $TMP_FILE
    else
        $BIN_SSH -i "$I_PATH_KEY" -oBatchMode=$SSH_BATCHMODE -t $I_REMOTE_LOGIN "/bin/sh" < $TMP_FILE
    fi
    return_code="$?"

    # delete the tmp file
    $BIN_RM $TMP_FILE

    return $return_code
}


##################################
# Check script input parameters
#
# Params: all parameters of the shell script
# return : 1 if an error occured, 0 otherwise
##################################
parseInputParams() {
    local opt dest_pool regex_rollback host regex_comp

    regex_comp="^($SUPPORTED_COMPRESSION)$"

    # parse the optional parameters
    # (there should be none)
    while getopts ":s:b:c:" opt; do
        case $opt in
            s)
                if ! echo "$OPTARG" | grep -E "^(.+)@(.+)$" >/dev/null; then
                    echo "Remote login data (\"$OPTARG\") does not have the expected format: username@hostname"
                    return 1
                fi

                I_REMOTE_ACTIVE="1"
                I_REMOTE_LOGIN=`echo "$OPTARG" | cut -f1 -d,`
                I_PATH_KEY=`echo "$OPTARG" | cut -s -f2 -d,`  # empty if path not specified (i.e. no "," found)

                # set variables to ensure remote execution of some parts of the script
                RUN_FCT_SSH="run_fct_ssh"
                if [ -z "$I_PATH_KEY" ]; then
                    RUN_CMD_SSH="$BIN_SSH -oBatchMode=$SSH_BATCHMODE $I_REMOTE_LOGIN"
                else
                    RUN_CMD_SSH="$BIN_SSH -i $I_PATH_KEY -oBatchMode=$SSH_BATCHMODE $I_REMOTE_LOGIN"
                fi

                # testing ssh connection
                if $RUN_CMD_SSH exit 0; then
                    echo "SSH connection test successful."
                else
                    echo "SSH connection failed. Please check username / hostname,"
                    echo "ensure that public key authentication is configured, and that you have access to the private key file"
                    return 1
                fi
                ;;
            b)
                if ! echo "$OPTARG" | grep -E "^([0-9]+)$" >/dev/null; then
                    echo "Wrong maximum rollback value, should be a positive integer or zero (unit: days) !"
                    return 1
                fi

                I_MAX_ROLLBACK_S=$(($OPTARG*$S_IN_DAY))
                ;;
            c)
                if ! echo "$OPTARG" | grep -E "$regex_comp" >/dev/null; then
                    echo "Bad compression definition, should be a compression algorithm supported by ZFS"
                    return 1            
                fi

                I_COMPRESSION=$OPTARG
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
    if [ "$#" -ne "2" ]; then
        echo "Exactly 2 mandatory argument shall be provided"
        return 1
    fi

    # Check if the source fs exists
    I_SRC_FS="$1"
    if ! $BIN_ZFS list $I_SRC_FS 2>/dev/null 1>/dev/null; then
        echo "source filesystem \"$I_SRC_FS\" does not exist."
        return 1
    fi

    # Check if the destination pool exists
    I_DEST_FS="$2"
    dest_pool=`echo "$I_DEST_FS" | cut -f1 -d/`
    if ! $RUN_CMD_SSH $BIN_ZFS list $dest_pool 2>/dev/null 1>/dev/null; then
        echo "The ZPOOL \"$dest_pool\" of the destination filesystem \"$I_DEST_FS\" does not exist."
        return 1
    fi

    # ensure that the ZPOOL of the destination filesystem is different from the
    # ZPOOL of the source filesystem
    if [ "$I_REMOTE_ACTIVE" -eq "0" ]; then
        src_pool=`echo "$I_SRC_FS" | cut -f1 -d/`
        if [ "$dest_pool" = "$src_pool" ]; then
            echo "The source filesystem \"$I_SRC_FS\" is in the same pool as the destination filesystem \"$I_DEST_FS\""
            return 1
        fi
    fi

    return 0
}

##################################
# Ensures the availability of the filesystem given as parameter
# Param 1: filesystem name
# Return : 0 if the filesystem is existing or could be created,
#       1 otherwise
##################################
ensureRemoteFSExists() {

    local fs pool readonly_mode
    fs="$1"
    pool=`echo "$fs" | cut -f1 -d/`

    # Check if the fs already exists
    if $RUN_CMD_SSH $BIN_ZFS list $fs 2>/dev/null 1>/dev/null; then
        return 0
    fi

    log_info "$LOGFILE" "Destination filesystem \"$fs\" DOES NOT exist yet. Creating it..."

    # Ensures that the destination pool is NOT readonly
    # So that the filesystems can be created if required
    readonly_mode=`$RUN_CMD_SSH $BIN_ZFS get -H readonly $pool | cut -f3`
    [ "$readonly_mode" = "on" ] && if ! $RUN_CMD_SSH $BIN_ZFS set readonly=off $pool >/dev/null; then
        log_error "$LOGFILE" "Destination pool could not be set to READONLY=off. Filesystem creation not possible "
        return 1
    fi

    # create the filesystem (-p option to create the parent fs if it does not exist)
    if ! $RUN_CMD_SSH $BIN_ZFS create -p "$fs"; then
        log_error "$LOGFILE" "The filesystem could NOT be created"

        # Set the destination pool to readonly
        [ "$readonly_mode" = "on" ] && if ! $RUN_CMD_SSH $BIN_ZFS set readonly=on $pool >/dev/null; then
            log_error "$LOGFILE" "The destination pool could not be set to \"readonly=on\""
        fi

        return 1
    fi

    log_info "$LOGFILE" "Filesystem created successfully"

    # Set the destination filesystem to readonly
    if ! $RUN_CMD_SSH $BIN_ZFS set readonly=on $fs >/dev/null; then
        log_error "$LOGFILE" "The destination filesystem could not be set to \"readonly=on\""
    fi

    # Set the destination pool to readonly
    [ "$readonly_mode" = "on" ] && if ! $RUN_CMD_SSH $BIN_ZFS set readonly=on $pool >/dev/null; then
        log_warning "$LOGFILE" "The destination pool could not be set to \"readonly=on\""
    fi

    return 0
}


##################################
# Backup the source filesystem
# (but NOT recursively the sub-filesystems)
#
# Param 1: source filesystem
# Param 2: destination filesystem
# Return : 0 if the backup could be performed successfully or
#         if there is nothing to backup
#       1 if the backup failed
##################################
backup() {
    local src_fs dest_fs logPrefix newestSnapDestFs oldestSnapSrcFs newestSnapSrcFs snapDestFs \
        replaceDestBySrcInFSName snapSrcFs snapSrcFsTimestamp1970 newestSnapDestFsCreation1970 \
        snapsAgeDiff

    src_fs="$1"
    dest_fs="$2"

    logPrefix="Backup of \"$src_fs\""

    # Get the newest snapshot on dest fs
    newestSnapDestFs=`$RUN_FCT_SSH sortSnapshots "$dest_fs" "" | head -n 1`
    # Get the oldest snapshot on the src fs
    oldestSnapSrcFs=`sortSnapshots "$src_fs" "" | tail -n -1`
    # Get the newest snapshot on the src fs
    newestSnapSrcFs=`sortSnapshots "$src_fs" "" | head -n 1`

    # If there is no snapshot on dest fs, backup the oldest snapshot on the src fs
    if [ -z "$newestSnapDestFs" ]; then
        log_info "$LOGFILE" "$logPrefix: No snapfound found in destination filesystem"

        if [ -z "$oldestSnapSrcFs" ]; then
            log_info "$LOGFILE" "$logPrefix: No snapshot to backup found in source filesystem"
            return 0
        fi
        
        log_info "$LOGFILE" "$logPrefix: Backup up oldest snapshot \"$oldestSnapSrcFs\""
        if ! $BIN_ZFS send $oldestSnapSrcFs | $RUN_CMD_SSH $BIN_ZFS receive -F $dest_fs >/dev/null; then
            log_error "$LOGFILE" "$logPrefix: Backup failed"
            return 1
        fi

        log_info "$LOGFILE" "$logPrefix: Backup performed"

    else
        log_info "$LOGFILE" "$logPrefix: Last snapshot available in destination filesystem was \"$newestSnapDestFs\" before backup"
    fi

    # Get the newest snapshot on the dest fs
    # (It may have changed, if a backup was performed above)
    newestSnapDestFs=`$RUN_FCT_SSH sortSnapshots "$dest_fs" "" | head -n 1`

    # find the newest snapshot on the dest fs that is still
    # available in the src fs and then perform an incremental
    # backup starting from the latter snapshot
    for snapDestFs in `$RUN_FCT_SSH sortSnapshots "$dest_fs" ""`; do

        # Compute the src fs snapshot name corresponding to the current dest fs snapshot
        replaceDestBySrcInFSName="s!^$I_DEST_FS!$I_SRC_FS!g"
        snapSrcFs=`echo "$snapDestFs" | sed -e "$replaceDestBySrcInFSName"`

        if [ $snapSrcFs = $newestSnapSrcFs ]; then
            log_info "$LOGFILE" "$logPrefix: No newer snapshot exists in source filesystem. Nothing to backup"
            return 0
        fi

        # If the current destination snapshot does not exist on the src fs
        if ! $BIN_ZFS list -o name -t snapshot "$snapSrcFs" 2>/dev/null 1>/dev/null; then
            continue
        fi

        # there is something to backup, but we may have to rollback the dest fs first...

        # Compute the required rollback duration
        snapSrcFsTimestamp1970=`getSnapTimestamp1970 "$snapSrcFs"`
        newestSnapDestFsCreation1970=`$RUN_FCT_SSH getSnapTimestamp1970 "$newestSnapDestFs"`
        snapsAgeDiff=$(($newestSnapDestFsCreation1970-$snapSrcFsTimestamp1970))
        if [ $snapsAgeDiff -gt $I_MAX_ROLLBACK_S ]; then
            log_warning "$LOGFILE" "$logPrefix: A rollback of \"$(($snapsAgeDiff/$S_IN_DAY))\" days would be required to perform the incremental backup !"
            log_warning "$LOGFILE" "$logPrefix: Current maximum allowed rollback value equals \"$(($I_MAX_ROLLBACK_S/$S_IN_DAY))\" days."
            log_warning "$LOGFILE" "$logPrefix: Please increase the maximum allowed rollback duration to make the backup possible"
            log_warning "$LOGFILE" "$logPrefix: Skipping backup of this filesystem"
            return 1
        fi

        log_info "$LOGFILE" "$logPrefix: Rolling back to last snapshot available on both source & destination fs: \"$snapDestFs\"..."
        if ! $RUN_CMD_SSH $BIN_ZFS rollback -r $snapDestFs >/dev/null; then
            log_error "$LOGFILE" "$logPrefix: Rollback failed"
            return 1
        fi

        log_info "$LOGFILE" "$logPrefix: Backing up incrementally from snapshot \"$snapSrcFs\" to \"$newestSnapSrcFs\" ..."
        if ! $BIN_ZFS send -I "$snapSrcFs" "$newestSnapSrcFs" | $RUN_CMD_SSH $BIN_ZFS receive "$dest_fs" >/dev/null; then
            log_error "$LOGFILE" "$logPrefix: Backup failed"
            return 1
        fi

        log_info "$LOGFILE" "$logPrefix: Backup performed"
        return 0
    done
}

##################################
# Main
##################################
main() {
    local returnCode currentSubSrcFs currentSubDstFs replaceSrcByDestInFSName

    returnCode=0

    log_info "$LOGFILE" "Starting backup of \"$I_SRC_FS\""

    # for the source fs and all its sub-filesystems
    for currentSubSrcFs in `$BIN_ZFS list -t filesystem,volume -r -H -o name $I_SRC_FS`; do

        replaceSrcByDestInFSName="s!^$I_SRC_FS!$I_DEST_FS!g"
        currentSubDstFs=`echo "$currentSubSrcFs" | sed -e "$replaceSrcByDestInFSName"`

        # create the dest filesystems (recursively) if it does not exist yet
        # and do not perform a backup if it fails
        if ! ensureRemoteFSExists "$currentSubDstFs"; then
            returnCode=1
            continue
        fi

        # if a compression algorithm was specified by the user
        # set compression algorithm for the current destination fs
        if [ -n "$I_COMPRESSION" ]; then
            if $RUN_CMD_SSH $BIN_ZFS set compression="$I_COMPRESSION" "$currentSubDstFs" 2>/dev/null 1>/dev/null; then
                log_info "$LOGFILE" "Compression algorithm set to \"$I_COMPRESSION\" for \"$currentSubDstFs\""
            else
                log_error "$LOGFILE" "Could not set compression algorithm to \"$I_COMPRESSION\" for \"$currentSubDstFs\""
                returnCode=1
            fi
        fi

        # Perform the backup
        if ! backup "$currentSubSrcFs" "$currentSubDstFs"; then
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
    run_main "$LOGFILE" "$SCRIPT_NAME"
    # in case of error, send mail with extract of log file
    [ "$?" -eq "2" ] && get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "$SCRIPT_NAME : issue occured during execution"
fi

$BIN_RM "$TMPFILE_ARGS"
exit 0

