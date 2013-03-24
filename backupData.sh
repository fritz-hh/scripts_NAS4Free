#!/bin/sh
#############################################################################
# Script aimed at performing a backup of a ZFS filesystem (fs) and of all 
# sub-filesystems recursively to another filesystem located on another ZPOOL
# The other filesystem can be either on the local host or on a remote host 
#
# Author: fritz from NAS4Free forum
#
# Usage: backupData.sh [-r user@host[,path2privatekey]] [-b maxRollbck] [-c compression[,...]] fsSource[,...] fsDest
#
#	-r user@host[,path2privatekey]:	Specify a remote host on which the destination filesystem 
#			is located
#			Prerequisite: An ssh server shall be running on the host and
#			public key authentication shall be available
#			(By default the destination filesystem is on the local host)
#			host: ip address or name of the host computer
#			user: name of the user on the host computer
#			path2privatekey: The path to the private key that should be used to
#				login. (This is required either if you are logged under another user
#				in the local host, or if you run the script from cron)
#	-b maxRollbck :	Biggest allowed rollback (in days) on the destination fs.
#			A rollback is necessary if the snapshots available on the 
#			destination fs are not available anymore on the source fs
#			Default value: 10 days
#	-c compression[,...] : compression algorithm to be used for the respective
#			destination filesystem.
#			If only one compression algorithm is provided, this algorithm applies to each 
#			destination filesystem.
#			If more then one compression algorithm is provided (exactly the same number
#			of algorithm shall be provided as the number of source filesystems), 
#			compressionN is the algorithm that will be set for the destination filesystem
#			corresponding to fsSourceN.
#	fsSource[,...] :  zfs filesystems to be backed-up (source).
#	   		Several file systems can be provided (They shall be separated by a comma ",")
#	   		Note: These fs (as well as the sub-fs) shall have a default mountpoint
# 	fsDest : 	zfs filesystem in which the data should be backed-up (destination)
#			Note: This filesystem must already exist before to launch the backup.
#			Note: This ZPOOL in which this filesystem is located should be different
#			      from the ZPOOL(s) of the source filesystems
#
# Example: 
#	"backupData.sh tank/nas_scripts tank_backup" will create a backup of the ZFS fs 
#	"tank/nas_scripts" (and of all its sub-filesystems) in the ZFS fs "tank_backup".
#	I.e. After the backup (at least) an fs "tank_backup/tank/nas_scripts" will exist.
#
#############################################################################

# Initialization of the script name
readonly SCRIPT_NAME=`basename $0` 		# The name of this file

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
readonly SUPPORTED_COMPRESSION='on|off|lzjb|gzip|gzip-[1-9]|zle'
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"
readonly TMP_FILE="$CFG_TMP_FOLDER/run_fct_ssh.sh"
readonly TMPFILE_ARGS="$CFG_TMP_FOLDER/$SCRIPT_NAME.$$.args.tmp"
readonly S_IN_DAY=86400			# Number of seconds in a day
readonly SSH_BATCHMODE="yes"		# Only public key authentication is allowed in batch mode 
					# (should only change to "no" for test purposes)

# Initialization of inputs corresponding to optional args of the script
I_REMOTE_ACTIVE="0"			# By default the destination filesystem is local
RUN_FCT_SSH=""				# This should be put in front of FUNCTIONS that may have to be executed remotely
					# By default (i.e. local backup) "RUN_FCT_SSH" does not have any effect
RUN_CMD_SSH=""				# This should be put in front of COMMANDS that may have to be executed remotely
					# By default (i.e. local backup) "RUN_CMD_SSH" does not have any effect
I_MAX_ROLLBACK_S=$((10*$S_IN_DAY))	# Default value of max rollback

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
	local opt current_fs current_src_pool dest_pool regex_rollback host regex_comp comp_num fs_num
	
	regex_comp="^($SUPPORTED_COMPRESSION)([,]($SUPPORTED_COMPRESSION)){0,}$"
	
	# parse the optional parameters
	# (there should be none)
	while getopts ":r:b:c:" opt; do
        	case $opt in
			r)	echo "$OPTARG" | grep -E "^(.+)@(.+)$" >/dev/null 
				if [ "$?" -eq "0" ] ; then
					I_REMOTE_ACTIVE="1"
					I_REMOTE_LOGIN=`echo "$OPTARG" | cut -f1 -d,`
					I_PATH_KEY=`echo "$OPTARG" | cut -s -f2 -d,`	# empty if path not specified (i.e. no "," found)
					
					# set variables to ensure remote execution of
					# some parts of the script
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
				else
					echo "Remote login data (\"$OPTARG\") does not have the expect format: username@hostname"
					return 1
				fi ;;
			b)	echo "$OPTARG" | grep -E "^([0-9]+)$" >/dev/null 
				if [ "$?" -eq "0" ] ; then
					I_MAX_ROLLBACK_S=$(($OPTARG*$S_IN_DAY))
				else
					echo "Wrong maximum rollback value, should be a positive integer or zero (unit: days) !"
					return 1
				fi ;;
			c)	echo "$OPTARG" | grep -E "$regex_comp" >/dev/null 
				if [ "$?" -eq "0" ] ; then
					I_COMPRESSION=$OPTARG
				else
					echo "Bad compression definition, should be a set of compression algorithms (supported by ZFS) separated by comma \",\" characters"
					return 1
				fi ;;
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

	# Itterate through all source filesystems for which a backup should be done
	# and check if the current fs exists	
	I_SRC_FSS=`echo "$1" | sed 's/,/ /g'` # replace commas by space as for loops on new line and space
	for current_fs in $I_SRC_FSS ; do	
		if ! $BIN_ZFS list $current_fs 2>/dev/null 1>/dev/null; then
			echo "source filesystem \"$current_fs\" does not exist."
			return 1
		fi
	done	
	
	# Check if the destination filesystem exists
	I_DEST_FS="$2"
	if ! $RUN_CMD_SSH $BIN_ZFS list $I_DEST_FS 2>/dev/null 1>/dev/null; then
		echo "destination filesystem \"$I_DEST_FS\" does not exist."
		return 1
	fi
	
	# ensure that the ZPOOL of the destination filesystem is different from the
	# ZPOOL(s) of the source filesystems
	dest_pool=`echo "$I_DEST_FS" | cut -f1 -d/`
	for current_fs in $I_SRC_FSS ; do
		current_src_pool=`echo "$current_fs" | cut -f1 -d/`
		if [ "$dest_pool" = "$current_src_pool" ]; then
			echo "The source filesystem \"$current_fs\" is in the same pool than the destination filesystem \"$I_DEST_FS\""
			return 1
		fi
	done
	
	# Ensure that the number of compression algorithm provided is compatible with
	# the number of source filesystems
	if [ -n "$I_COMPRESSION" ]; then
		
		# number of compression algorithm defined
		comp_num=`echo "$I_COMPRESSION" | tr "," "\n" | wc -l`
		# number of source fs defined
		fs_num=`echo "$I_SRC_FSS" | tr " " "\n" | wc -l`
		
		# if the number of compression algorithm defined is neither 1
		# nor equal to the number number of source fs that were defined
		if [ $comp_num -ne 1 -a $comp_num -ne $fs_num ]; then
			echo "Bad compression definition, the number of compression algorithm should either equal 1 or should be equal to the number of source filesystems"
			return 1
		fi
	fi
	
	return 0
}

##################################
# Ensures the availability of the filesystem given as parameter
# Param 1: filesystem name
# Return : 0 if the filesystem is existing or could be created, 
#	   1 otherwise
##################################
ensureRemoteFSExists() {

	local fs pool
	fs="$1"
	pool=`echo "$fs" | cut -f1 -d/`
	
	# Check if the fs already exists
	if $RUN_CMD_SSH $BIN_ZFS list $fs 2>/dev/null 1>/dev/null; then
		return 0
	fi
	
	log_info "$LOGFILE" "Destination filesystem \"$fs\" DOES NOT exist yet. Creating it..."

	# Ensures that the destination pool is NOT readonly
	# So that the filesystems can be created if required
	if ! $RUN_CMD_SSH $BIN_ZFS set readonly=off $pool >/dev/null; then
		log_error "$LOGFILE" "Destination pool could not be set to READONLY=off. Filesystem creation not possible "
		return 1
	fi

	# create the filesystem (-p option to create the parent fs if it does not exist)
	if ! $RUN_CMD_SSH $BIN_ZFS create -p "$fs"; then
		log_error "$LOGFILE" "The filesystem could NOT be created"

		# Set the destination pool to readonly
		if ! $RUN_CMD_SSH $BIN_ZFS set readonly=on $pool >/dev/null; then
			log_error "$LOGFILE" "The destination pool could not be set to \"readonly=on\""
		fi

		return 1
	else
		log_info "$LOGFILE" "Filesystem created successfully"

		# Set the destination pool to readonly
		if ! $RUN_CMD_SSH $BIN_ZFS set readonly=on $pool >/dev/null; then
			log_warning "$LOGFILE" "The destination pool could not be set to \"readonly=on\""
		fi

		return 0
	fi
}


##################################
# Backup the source filesystem 
# (but NOT recursively the sub-filesystems)
#
# Param 1: source filesystem
# Param 2: destination filesystem
# Return : 0 if the backup could be performed successfully or 
#	     if there is nothing to backup
#	   1 if the backup failed
##################################
backup() {
	local src_fs dest_fs logPrefix newestSnapDestFs oldestSnapSrcFs newestSnapSrcFs snapDestFs \
		removeDestFSInName snapSrcFs snapSrcFsTimestamp1970 newestSnapDestFsCreation1970 \
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
			log_info "$LOGFILE" "$logPrefix: No snapshot to be backed up found in source filesystem"
			return 0
		else
			log_info "$LOGFILE" "$logPrefix: Backup up oldest snapshot \"$oldestSnapSrcFs\""
			if ! $BIN_ZFS send $oldestSnapSrcFs | $RUN_CMD_SSH $BIN_ZFS receive -F $dest_fs >/dev/null; then
				log_error "$LOGFILE" "$logPrefix: Backup failed"
				return 1
			else
				log_info "$LOGFILE" "$logPrefix: Backup performed"
			fi
		fi
	else
		log_info "$LOGFILE" "$logPrefix: Last snapshot available in destination filesystem was \"$newestSnapDestFs\" before backup"
	fi

	# Get the newest snapshot on the dest fs
	# (It may have changed, if a backup was performed above)
	newestSnapDestFs=`$RUN_FCT_SSH sortSnapshots $dest_fs "" | head -n 1`

	# find the newest snapshot on the dest fs that is still
	# available in the src fs and then perform an incremental 
	# backup starting from the latter snapshot
	for snapDestFs in `$RUN_FCT_SSH sortSnapshots "$dest_fs" ""`; do

		# Compute the src fs snapshot name corresponding to the current dest fs snapshot
		removeDestFSInName="s!$I_DEST_FS/!!g"
		snapSrcFs=`echo "$snapDestFs" | sed -e "$removeDestFSInName"`

		if [ $snapSrcFs = $newestSnapSrcFs ]; then
			log_info "$LOGFILE" "$logPrefix: No newer snapshot exist in source filesystem. Nothing to backup"
			return 0
		fi

		# If the snapshot exists on the src fs
		if $BIN_ZFS list -o name -t snapshot "$snapSrcFs" 2>/dev/null 1>/dev/null; then

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
			else
				log_info "$LOGFILE" "$logPrefix: Backup performed"
				return 0
			fi
		fi
	done
}

################################## 
# Main 
##################################
main() {
	local returnCode current_fs currentSubSrcFs currentSubDstFs algo cpt

	returnCode=0
	
	log_info "$LOGFILE" "Starting backup of \"$I_SRC_FSS\""

	# Itterate through all source filesystems for which a backup should be done
	cpt=0
	for current_fs in $I_SRC_FSS ; do

		cpt=$(($cpt+1))
	
		# for the current fs and all its sub-filesystems
		for currentSubSrcFs in `$BIN_ZFS list -r -H -o name $current_fs`; do

			currentSubDstFs="$I_DEST_FS/$currentSubSrcFs"
		
			# create the dest filesystems (recursively) 
			# if they do not yet exist and exit if it fails
			if ! ensureRemoteFSExists "$currentSubDstFs"; then
				returnCode=1
			else
				# if a compression algorithm was specified by the user
				# set compression algorithm for the current destination fs
				if [ -n "$I_COMPRESSION" ]; then
					# compute compress algorithm for the current fs, or unique algorithm if only one was defined
					algo=`echo "$I_COMPRESSION" | cut -f$cpt -d,` 
					if $RUN_CMD_SSH $BIN_ZFS set compression="$algo" "$currentSubDstFs" 2>/dev/null 1>/dev/null; then
						log_info "$LOGFILE" "Compression algorithm set to \"$algo\" for \"$currentSubDstFs\""
					else
						log_error "$LOGFILE" "Could not set compression algorithm to \"$algo\" for \"$currentSubDstFs\""
						returnCode=1
					fi
				fi

				# Perform the backup
				if ! backup "$currentSubSrcFs" "$currentSubDstFs"; then
					returnCode=1
				fi
			fi
		done
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

