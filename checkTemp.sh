#!/bin/sh
#############################################################################
# Check the CPU and HDD temperatures, and send e-mail 
# if desired limits are exceeded  
#
# Author: miGi from NAS4Free Forum
#
# Usage: checkTemp.sh thresholdCPU thresholdHDD
#
#	thresholdCPU : Warning temperature threshold to the CPU (in deg celsius)
# 	thresholdHDD : Warning temperature threshold to the HDD (in deg celsius)
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

# Initialization of the constants 
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"

# Set variables corresponding to the input parameters
ARGUMENTS="$@"



################################## 
# Check script input parameters
#
# Params: all parameters of the shell script
##################################
parseInputParams() {
	local opt regex_temp 

	# parse the optional parameters
	# (there should be none)
	while getopts ":" opt; do
        	case $opt in
			\?)
				log_error "$LOGFILE" "Invalid option: -$OPTARG"
				return 1 ;;
        	esac
	done

	# Remove the optional arguments parsed above.
	shift $((OPTIND-1))
	
	# Check if the number of mandatory parameters 
	# provided is as expected 
	if [ "$#" -ne "2" ]; then
		log_error "$LOGFILE" "Exactly two mandatory argument shall be provided"
		return 1
	fi

	# Set variables corresponding to the input parameters
	I_WARN_THRESHOLD_CPU="$1"
	I_WARN_THRESHOLD_HDD="$2"

        regex_temp="([0-9]+)"

        echo "$I_WARN_THRESHOLD_CPU" | grep -E "^$regex_temp$" >/dev/null
        if [ "$?" -ne "0" ]; then
                log_warning "$LOGFILE" "Wrong CPU temperature notification threshold definition !"
                return 1
        fi

        echo "$I_WARN_THRESHOLD_HDD" | grep -E "^$regex_temp$" >/dev/null
        if [ "$?" -ne "0" ]; then
                log_warning "$LOGFILE" "Wrong HDD temperature notification threshold definition !"
                return 1
        fi

	return 0
}


##################################
# Main
##################################
main() {

	returnCode=0

	log_info "$LOGFILE" "-------------------------------------"
	log_info "$LOGFILE" "Starting checking temperatures..."
	
	# Parse the input parameters
	if ! parseInputParams $ARGUMENTS; then
		return 1
	fi
	
	log_info "$LOGFILE" "CPUs (warning threshold: $((I_WARN_THRESHOLD_CPU))C):"
	printf '%8s %s\n' "Temp(C)" "CPU" | log_info "$LOGFILE"
	for cpu in `sysctl -a | grep -E "cpu\.[0-9]+\.temp" | cut -f1 -d:`; do 
		cpuTemp=`sysctl -a | grep $cpu | awk '{gsub(/[[.][0-9]C]*/,"");print $2}'` 
		
		printf '%+8d %s\n' "$((cpuTemp))" "$cpu" | log_info "$LOGFILE"
		
		if [ "$((cpuTemp))" -ge "$I_WARN_THRESHOLD_CPU" ] ; then
			log_warning "$LOGFILE" "CPU notification threshold reached !"
			returnCode=1
		fi
	done

	log_info "$LOGFILE" "HDDs (warning threshold: $((I_WARN_THRESHOLD_HDD))C):"
	printf '%8s %-6s %-25s %s\n' "Temp(C)" "dev" "P/N" "S/N" | log_info "$LOGFILE"
	for hdd in $(sysctl -n kern.disks); do
		devTemp=`$BIN_SMARTCTL -a /dev/$hdd | grep "Temperature_Celsius" | awk '{print $10}'`
		devSerNum=`$BIN_SMARTCTL -a /dev/$hdd | grep "^Serial Number:" | sed 's/^Serial Number:[ \t]*\(.*\)[ \t]*$/\1/g'`
		devName=`$BIN_SMARTCTL -a /dev/$hdd | grep "^Device Model:" | sed 's/^Device Model:[ \t]*\(.*\)[ \t]*$/\1/g'`
		
		printf '%+8d %-6s %-25s %s\n' "$((devTemp))" "$hdd" "$devName" "$devSerNum" \
			| log_info "$LOGFILE"
			
		if [ "$((devTemp))" -ge "$I_WARN_THRESHOLD_HDD" ] ; then
			log_warning "$LOGFILE" "HDD notification threshold reached !"
			returnCode=1
		fi
	done
	
	return $returnCode
}



# run script if possible (lock not existing)
run_main "$LOGFILE" "$SCRIPT_NAME"
# in case of error, send mail with extract of log file
[ "$?" -eq "2" ] && `get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Problem with temperatures"`

exit 0

