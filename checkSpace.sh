#!/bin/sh
#############################################################################
# Script aimed at checking if the quota of the ZFS filesystem is nearly reached
#
# Author: fritz from NAS4Free forum
#
# Usage: [-f filesystem] [-t threshold]
#
#	-f filesystem : the ZFS filesystem (incl. sub-fs) to be checked
#			default: all ZFS filesystems
# 	-t threshold : the threshold in percent above which a notification mail shall be sent
#			value must be between 0 and 99
#			default: 80 (percent)
#############################################################################

# Initialization of the script name and path constants
readonly SCRIPT_NAME=`basename $0` 		# The name of this file
readonly SCRIPT_PATH=`dirname $0`		# The path to the current script

# Import required scripts
. "$SCRIPT_PATH/config.sh"
. "$SCRIPT_PATH/common/commonLogFcts.sh"
. "$SCRIPT_PATH/common/commonMailFcts.sh"
. "$SCRIPT_PATH/common/commonLockFcts.sh"

# Record the timestamp corresponding to the start of the script execution
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`

# Set variables corresponding to the input parameters
ARGUMENTS="$@"

# Initialization of the constants 
FILESYSTEM="" 		# default name of the filesystem to be monitored (meaning: all fs)
WARN_THRESHOLD="80"	# space warning threshold default value
LOGFILE=""		# provisionary value of log file name (will be set in fct "parseOptionalInputParams")


################################## 
# Check script input parameters
#
# Params: all parameters of the shell script
##################################
parseOptionalInputParams() {

	local fs_without_slash specific_fs
	specific_fs="0"

	# parse the parameters
	while getopts ":f:t:" opt; do
        	case $opt in
                        f)	fs_without_slash=`echo "$OPTARG" | sed 's!/!_!'`		# value of the fs without '/' that is not allowed in a file name
 				LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.$fs_without_slash.log" 	# value of the log file name
				specific_fs="1"
 				$BIN_ZFS list "$OPTARG" >/dev/null      			# Check if the zfs file system exists
                                if [ "$?" -eq "0" ] ; then
                                        FILESYSTEM="$OPTARG"
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
					WARN_THRESHOLD="$OPTARG" 
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
	if ! parseOptionalInputParams $ARGUMENTS; then
		return 1
	fi

	log_info "$LOGFILE" "-------------------------------------"
	log_info "$LOGFILE" "Configured warning threshold: $WARN_THRESHOLD percent"
	
	# Check the space for the filesystem (and for all sub-fs recursively)
	for subfilesystem in `$BIN_ZFS list -H -r -o name $FILESYSTEM`; do

		quota=`getQuota $subfilesystem`
		used=`getUsed $subfilesystem`
		avail=`getAvailable $subfilesystem`
		percent=$(($used*100/($used+$avail)))
	
		log_info "$LOGFILE" "$subfilesystem: avail: $((avail/mib)) MiB , used: $((used/mib)) MiB [$percent percent] , quota: $((quota/mib)) MiB"

		# Check if the warning limit is reached		
		if [ $percent -gt $WARN_THRESHOLD ] ; then
			log_warning "$LOGFILE" "Notification threshold reached !"	
			log_warning "$LOGFILE" "Consider increasing quota or adding disk space"	
			returnCode=1
		fi
	done

	return $returnCode
}
        
# run script if possible (lock not existing)
fs_without_slash=`echo "$FILESYSTEM" | sed 's!/!_!'`    	# value of the fs without '/' that is not allowed in a file name
run_main "$LOGFILE" "$SCRIPT_NAME.$fs_without_slash"
# in case of error, send mail with extract of log in case of error
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Checkspace issue"`

exit 0

