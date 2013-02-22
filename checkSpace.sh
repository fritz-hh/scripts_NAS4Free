#!/bin/sh
#############################################################################
# Script aimed at checking if the quota of the ZFS filesystem is nearly reached
#
# Author: fritz from NAS4Free forum
#
# Usage: checkSpace.sh [-f filesystem] [-t threshold]
#
#	-f filesystem : the ZFS filesystem (incl. sub-fs) to be checked
#			default: all ZFS filesystems
# 	-t threshold : the threshold in percent above which a notification mail shall be sent
#			value must be between 0 and 99
#			default: 80 (percent)
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

# Set variables corresponding to the input parameters
ARGUMENTS="$@"

# Initialization of the optional input variables 
I_FILESYSTEM="" 		# default name of the filesystem to be monitored (meaning: all fs)
I_WARN_THRESHOLD="80"	# space warning threshold default value

LOGFILE=""		# provisionary value of log file name (will be set in fct "parseInputParams")


################################## 
# Check script input parameters
#
# Params: all parameters of the shell script
##################################
parseInputParams() {

	local fs_without_slash specific_fs
	specific_fs="0"

	# parse the parameters
	while getopts ":f:t:" opt; do
        	case $opt in
			f)	fs_without_slash=`echo "$OPTARG" | sed 's!/!_!'`		# value of the fs without '/' that is not allowed in a file name
 				LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.$fs_without_slash.log" 	# value of the log file name
				specific_fs="1"
 				$BIN_ZFS list "$OPTARG" 2>/dev/null 1>/dev/null			# Check if the zfs file system exists
				if [ "$?" -eq "0" ] ; then
					I_FILESYSTEM="$OPTARG"
				else
					log_error "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -f. The ZFS filesystem does not exist."
					return 1
				fi ;;
			t) 	# first check if a specific fs was set before, otherwise
				# set the log file name to its default value
				if [ "$specific_fs" -eq "0" ]; then
					LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"
				fi
				# check if the threshold value is valid
				echo "$OPTARG" | grep -E '^[0-9]{1,2}$' >/dev/null
				if [ "$?" -eq "0" ] ; then 
					I_WARN_THRESHOLD="$OPTARG" 
				else
					log_error "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -t. Should be an integer between 0 and 99."
					return 1
				fi ;;
			\?)
				log_error "$LOGFILE" "Invalid option: -$OPTARG"
				return 1 ;;
			:)
				log_error "$LOGFILE" "Option -$OPTARG requires an argument"
				return 1 ;;
        	esac
	done

	# check if a specific fs was set before, otherwise
	# set the log file name to its default value
	# (required in case none of -f and -t are used)
	if [ "$specific_fs" -eq "0" ]; then
		LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"
	fi

	# Remove the optional arguments parsed above.
	shift $((OPTIND-1))
	
	# Check if the number of mandatory parameters 
	# provided is as expected 
	if [ "$#" -ne "0" ]; then
		log_error "$LOGFILE" "No mandatory arguments should be provided"
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
	local fs
	fs="$1"

	# compute the quota of the filesystem in bytes
	$BIN_ZFS get -o value -Hp quota $fs
}

##################################
# Get the used space for a given filesystem
# param 1: filesystem name 
# Return : used space in byte
##################################
getUsed() {
	local fs
	fs="$1"

	# compute the used size of the filesystem in bytes
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

	# compute the used size of the filesystem in bytes
	$BIN_ZFS get -o value -Hp avail $fs
}

################################## 
# Main 
##################################
main() {
	local returnCode quota used avail percent mib

	returnCode=0
	mib=$((1024*1024))

	# Parse the input parameters
	if ! parseInputParams $ARGUMENTS; then
		return 1
	fi

	log_info "$LOGFILE" "-------------------------------------"
	log_info "$LOGFILE" "Configured warning threshold: $I_WARN_THRESHOLD percent"

	printf '%14s %13s %13s %13s %s\n' "Used (percent)" "Used (MiB)" "Available" "Quota" "Filesystem" \
		| log_info "$LOGFILE"

	
	# Check the space for the filesystem (and for all sub-fs recursively)
	for subfilesystem in `$BIN_ZFS list -H -r -o name $I_FILESYSTEM`; do

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
        
# run script if possible (lock not existing)
fs_without_slash=`echo "$I_FILESYSTEM" | sed 's!/!_!'`    	# value of the fs without '/' that is not allowed in a file name
run_main "$LOGFILE" "$SCRIPT_NAME.$fs_without_slash"
# in case of error, send mail with extract of log file
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Checkspace issue"`

exit 0

