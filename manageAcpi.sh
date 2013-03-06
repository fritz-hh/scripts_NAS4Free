#!/bin/sh
#############################################################################
# Script aimed at setting the NAS in sleep state whenever possible
# in order to save energy.
# - The script enables to define a curfew timeslot,
# - A timeslot where the NAS shall sleep if no other device is online,
# - A timeslot where the system shall never sleep. 
# - And allows to force the NAS to stay awake if an incoming SSH connection exists
#
# The script shall be launched at system startup 
#
# Usage: manageAcpi.sh [-p duration] [-w duration] [-a beg,end] [-s delay] [-c beg,end,acpi] [-n ips,delay,acpi] [-vm] 
#
#	- p duration :		Define the duration (in seconds) between each respective poll (by default: 120)
#	- w duration :		Define the duration (in seconds) for which the NAS should never sleep after 
#				it wakes up (by default: 600)
#	- a beg,end :		Define a timeslot in which the NAS shall never go sleeping (e.g. because admin
#				tasks are scheduled during this slot) 
#				(This option superseeds a sleep order originating from -c and -n)
#				+ beg: time of the beginning of the slot (format: hh:mm)
#				+ end: time of the end of the slot (format: hh:mm)
#	- s delay :		Define that the NAS shall not never go sleep if an incoming SSH connection exists.
#				This function may be required in case the NAS is used as a destination of a remote
#				backup.
#				(This option superseeds a sleep order originating from -c and -n)
#				+ delay: delay in seconds between the end of the connection and start of sleep 
#	- c beg,end,acpi :	Define a curfew timeslot in which the NAS shall go sleeping.
#				+ beg: time of the beginning of the slot (format: hh:mm)
#				+ end: time of the end of the slot (format: hh:mm)
#				+ acpi: the ACPI state selected for the sleep (3 or 5) 
#	- n ips,delay,acpi : 	Define that the NAS shall sleep if none of the other devices are online
#				+ ips: IP addresses of the devices to poll (at least one), separated by "+" (Note: IP shall be static)
#				+ delay: delay in seconds between last device going offline and start of sleep 
#				+ acpi: the ACPI state selected for the sleep (3 or 5)
#	- v:			Requests the log to be more verbose
#				Note: This is likely to prevent the disks to spin down 
#	- m:			Send mail on ACPI state change
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
. "common/commonMailFcts.sh"
. "common/commonLockFcts.sh"

# Initialization of the constants 
readonly START_TIMESTAMP=`$BIN_DATE +"%s"`
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"
readonly TMPFILE_ARGS="$CFG_TMP_FOLDER/$SCRIPT_NAME.$$.args.tmp"
readonly ACPI_STATE_LOGFILE="$CFG_LOG_FOLDER/acpi.log"

# Set variables corresponding to the input parameters
ARGUMENTS="$@"

# Log verbosity (1: verbose, 0: less verbose)
I_VERBOSE=0

# 1: mail to be sent on ACPI state change, 0: otherwise 
I_MAIL_ACPI_CHANGE=0

# Initialisation of the default values for the arguments of the script
I_POLL_INTERVAL=120			# number of seconds to wait between to cycles

I_DELAY_PREVENT_SLEEP_AFTER_WAKE="600"	# Amount of time during which the NAS will never go to sleep after waking up

I_CHECK_ALWAYS_ON="0"			# 1 if the check shall be performed, 0 otherwise
I_BEG_ALWAYS_ON="00:00"			# time when the NAS shall never sleep (because of management tasks like backup may start)
I_END_ALWAYS_ON="00:00"			# If end = beg => 24 hours

I_CHECK_SSH_ACTIVE="0"			# 1 if the check shall be performed, 0 otherwise
I_DELAY_SSH="0"				# Delay in seconds between the moment where the SSH connection stops and the moment where the NAS may sleep

I_CHECK_CURFEW_ACTIVE="0"		# 1 if the check shall be performed, 0 otherwise
I_BEG_POLL_CURFEW="00:00"		# time when the script enters the sleep state (except if tasks like backup are running)
I_END_POLL_CURFEW="00:00"		# If end = beg => 24 hours
I_ACPI_STATE_CURFEW="0"			# ACPI state 

I_CHECK_NOONLINE_ACTIVE="0"		# 1 if the check shall be performed, 0 otherwise
I_IP_ADDRS="" 				# IP addresses of the devices to be polled, separated by a space character)
I_DELAY_NOONLINE="0"			# Delay in seconds between the moment where no devices are online anymore and the moment where the NAS shall sleep
I_ACPI_STATE_NOONLINE="0"		# ACPI state if no other device is online 

# Initialization the global variables
awake="0"				# 1=NAS is awake, 0=NAS is about to sleep (resp. just woke up)


##################################
# Check script input parameters
#
# Params: all parameters of the shell script
# return : 1 if an error occured, 0 otherwise 
##################################
parseInputParams() {

	local regex_dur regex_hh regex_mm regex_time regex_0_255 regex_ip regex_a regex_c regex_n opt w_min 

	regex_dur="([0-9]+)"
	regex_hh="(([0-9])|([0-1][0-9])|([2][0-3]))"
	regex_mm="([0-5][0-9])"
	regex_time="($regex_hh[:]$regex_mm)"
	regex_0_255="(([0-9])|([1-9][0-9])|([1][0-9][0-9])|([2][0-4][0-9])|([2][5][0-5]))"
	regex_ip="(($regex_0_255[.]){3,3}$regex_0_255)"

	regex_a="^$regex_time[,]$regex_time$"
	regex_c="^($regex_time[,]){2,2}[35]$"
	regex_n="^$regex_ip([+]$regex_ip){0,}[,]$regex_dur[,][35]$"

	w_min="300"

	# parse the parameters
	while getopts ":p:w:a:s:c:n:vm" opt; do
		
		case $opt in
			p)	echo "$OPTARG" | grep -E "^$regex_dur$" >/dev/null 
				if [ "$?" -eq "0" ] ; then
					I_POLL_INTERVAL="$OPTARG"
				else
					echo "Invalid parameter \"$OPTARG\" for option: -p. Should be a positive integer"
					return 1
				fi ;;
			w)	echo "$OPTARG" | grep -E "^$regex_dur$" >/dev/null 
				if [ "$?" -eq "0" ] ; then
					I_DELAY_PREVENT_SLEEP_AFTER_WAKE="$OPTARG"

					if [ "$I_DELAY_PREVENT_SLEEP_AFTER_WAKE" -lt "$w_min" ] ; then
						echo "The value passed to the -w option must be at least $w_min s."
						echo "Replacing the provided value ($I_DELAY_PREVENT_SLEEP_AFTER_WAKE s) with the value $w_min s"
						echo "Rationale: If other options are not set correctly, the server may always"
						echo "shutdown/sleep just after booting making the server unusable"
						I_DELAY_PREVENT_SLEEP_AFTER_WAKE="$w_min"			
					fi
				else
					echo "Invalid parameter \"$OPTARG\" for option: -w. Should be a positive integer"
					return 1
				fi ;;
			a)	echo "$OPTARG" | grep -E "$regex_a" >/dev/null
				if [ "$?" -eq "0" ] ; then
					I_CHECK_ALWAYS_ON="1"	
					I_BEG_ALWAYS_ON=`echo "$OPTARG" | cut -f1 -d,`
					I_END_ALWAYS_ON=`echo "$OPTARG" | cut -f2 -d,`
				else
					echo "Invalid parameter \"$OPTARG\" for option: -a. Should be \"hh:mm,hh:mm\""
					return 1
				fi ;;
			s)	echo "$OPTARG" | grep -E "$regex_dur" >/dev/null
				if [ "$?" -eq "0" ] ; then
					I_CHECK_SSH_ACTIVE="1"			
					I_DELAY_SSH="$OPTARG"
				else
					echo "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -s. Should be a positive integer"
					return 1
				fi ;;
			c)	echo "$OPTARG" | grep -E "$regex_c" >/dev/null
				if [ "$?" -eq "0" ] ; then
					I_CHECK_CURFEW_ACTIVE="1"	
					I_BEG_POLL_CURFEW=`echo "$OPTARG" | cut -f1 -d,`			
					I_END_POLL_CURFEW=`echo "$OPTARG" | cut -f2 -d,`			
					I_ACPI_STATE_CURFEW=`echo "$OPTARG" | cut -f3 -d,`			
				else
					echo "Invalid parameter \"$OPTARG\" for option: -c. Should be \"hh:mm,hh:mm,acpi_state\""
					return 1
				fi ;;
			n)	echo "$OPTARG" | grep -E "$regex_n" >/dev/null
				if [ "$?" -eq "0" ] ; then
					I_CHECK_NOONLINE_ACTIVE="1"
					I_IP_ADDRS=`echo "$OPTARG" | cut -f1 -d, | sed 's/+/ /g'`
					I_DELAY_NOONLINE=`echo "$OPTARG" | cut -f2 -d,`
					I_ACPI_STATE_NOONLINE=`echo "$OPTARG" | cut -f3 -d,`
				else
					echo "Invalid parameter \"$OPTARG\" for option: -n. Should be \"ips,delay,acpi_state\""
					return 1
				fi ;;
			v)	I_VERBOSE=1 ;;
			m)	I_MAIL_ACPI_CHANGE=1 ;;
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
# Returns true if the current time is within the timeslot
# provided as parameter.
#
# Param 1: Start of the timeslot (format: "hh:mm")
# Param 2: End of the timeslot (format: "hh:mm"). If End=Beg, 
#	   the timeslot is considered to last the whole day.
# Return: 0 if the current time is within the timeslot 
################################## 
isInTimeSlot() {
	local startTime endTime nbSecInDay currentTimestamp startTimestamp endTimestamp
        
	startTime="$1"
        endTime="$2"

	nbSecInDay="86400"

	currentTimestamp=`$BIN_DATE +"%s"`
	startTimestamp=`$BIN_DATE -j -f "%H:%M:%S" "$startTime:00" +"%s"`
	endTimestamp=`$BIN_DATE -j -f "%H:%M:%S" "$endTime:00" +"%s"`

	if [ "$endTimestamp" -le "$startTimestamp" ]; then
		if [ "$currentTimestamp" -gt "$startTimestamp" ]; then
			endTimestamp=`expr $endTimestamp + $nbSecInDay`
		else
			startTimestamp=`expr $startTimestamp - $nbSecInDay`
		fi
	fi

	if [ "$currentTimestamp" -gt "$startTimestamp" -a "$currentTimestamp" -le "$endTimestamp" ]; then
		return 0
	else
		return 1
	fi
}


################################## 
# Request NAS to sleep if no script is running currently
#
# Param 1: ACPI state (one of 3,5)
#    - 3: Sleeping (Suspend to RAM)
#    - 5: Soft off
# Return: 0 if the the NAS could be shutdown 
################################## 
nasSleep() {
	local acpi_state msg

	acpi_state="$1"

        if ! does_any_lock_exist; then

                msg="Shutting down the system to save energy (ACPI state : S$acpi_state)"
                
		if [ $acpi_state -eq "5" ]; then	# Soft OFF
        
			log_info "$LOGFILE" "$msg"
			log_info "$ACPI_STATE_LOGFILE" "S$acpi_state"
        	
			if [ $I_MAIL_ACPI_CHANGE -eq "1" ]; then	
				get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "NAS going to sleep to save energy (ACPI state: S$acpi_state)"
			fi

			awake="0"
			$BIN_SHUTDOWN -p now "$msg"
	
		elif [ $acpi_state -eq "3" ]; then	# Suspend to RAM
	        	
			log_info "$LOGFILE" "$msg"
			log_info "$ACPI_STATE_LOGFILE" "S$acpi_state"
        
			if [ $I_MAIL_ACPI_CHANGE -eq "1" ]; then	
				get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "NAS going to sleep to save energy (ACPI state: S$acpi_state)"
			fi		

			awake="0"
			$BIN_ACPICONF -s 3	
		else
			log_error "$LOGFILE" "Shutdown not possible. ACPI state \"$acpi_state\" not supported"
			return 1
		fi	
		return 0
	else
		log_info "$LOGFILE" "Shutdown not possible. The following scripts are running: `get_list_of_locks`"
		return 1
	fi
}




################################## 
# Main 
##################################
main() {
	local ts_last_online_device ts_last_ssh ts_wakeup in_always_on_timeslot curfew_sleep_request \
		noonline_sleep_request any_device_online delta_t awakefor
	
	# initialization of local variables
	ts_last_online_device=`$BIN_DATE +%s`	# Timestamp when the last other device was detected to be online
	ts_last_ssh=`$BIN_DATE +%s`		# Timestamp when the last SSH connection ended
	ts_wakeup=`$BIN_DATE +%s`		# Timestamp when the NAS woke up last time
	in_always_on_timeslot="0"		# 1=We are currently in the always on timeslot, 0 otherwise 
	ssh_sleep_prevent="0"			# 1=Sleep prevented by SSH, 0 otherwise
	curfew_sleep_request="0"		# 1=Sleep requested by curfew check, 0 otherwise
	noonline_sleep_request="0"		# 1=Sleep requested by no-online check, 0 otherwise 

	# Remove any existing lock
	reset_locks

	# log the selected configuration
	log_info "$LOGFILE" "Selected settings for \"$SCRIPT_NAME\":"
	printf '%-35s %s\n' "- VERBOSE:" "$I_VERBOSE" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- MAIL ACPI STATE CHANGES:" "$I_MAIL_ACPI_CHANGE" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- POLL_INTERVAL:" "$I_POLL_INTERVAL" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- DELAY_PREVENT_SLEEP_AFTER_WAKE:" "$I_DELAY_PREVENT_SLEEP_AFTER_WAKE" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- CHECK_ALWAYS_ON:" "$I_CHECK_ALWAYS_ON" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- BEG_ALWAYS_ON:" "$I_BEG_ALWAYS_ON" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- END_ALWAYS_ON:" "$I_END_ALWAYS_ON" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- CHECK_SSH_ACTIVE:" "$I_CHECK_SSH_ACTIVE" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- DELAY_SSH:" "$I_DELAY_SSH" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- CHECK_CURFEW_ACTIVE:" "$I_CHECK_CURFEW_ACTIVE" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- BEG_POLL_CURFEW:" "$I_BEG_POLL_CURFEW" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- END_POLL_CURFEW:" "$I_END_POLL_CURFEW" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- ACPI_STATE_CURFEW:" "$I_ACPI_STATE_CURFEW" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- CHECK_NOONLINE_ACTIVE:" "$I_CHECK_NOONLINE_ACTIVE" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- ACPI_STATE_NOONLINE:" "$I_ACPI_STATE_NOONLINE" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- DELAY_NOONLINE:" "$I_DELAY_NOONLINE" | log_info "$LOGFILE"
	printf '%-35s %s\n' "- IP_ADDRS:" "$I_IP_ADDRS" | log_info "$LOGFILE"


	# Loop until the NAS is switched off
	while true; do
		[ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "-----------------"

		# If the NAS just woke up
		if [ $awake -eq "0" ]; then
			awake="1"
 			ts_wakeup=`$BIN_DATE +%s`       	
			ts_last_online_device=`$BIN_DATE +%s`

			log_info "$ACPI_STATE_LOGFILE" "S0"
			log_info "$LOGFILE" "NAS just woke up (S0). Preventing sleep during the next $I_DELAY_PREVENT_SLEEP_AFTER_WAKE s"
        
			if [ $I_MAIL_ACPI_CHANGE -eq "1" ]; then	
				get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "NAS just woke up (S0)"
			fi	
		fi

		# Check if in always_on timeslot 
		in_always_on_timeslot="0"
		if [ $I_CHECK_ALWAYS_ON -eq "1" ]; then
			if isInTimeSlot "$I_BEG_ALWAYS_ON" "$I_END_ALWAYS_ON"; then
				[ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "In always_on timeslot: [ $I_BEG_ALWAYS_ON ; $I_END_ALWAYS_ON ]"
				in_always_on_timeslot="1"
			fi
		fi

		# Check if an incoming SSH connection existed recently  
		ssh_sleep_prevent="0"
		if [ $I_CHECK_SSH_ACTIVE -eq "1" ]; then
			# Check if an ingoing ssh connection exist
			if $BIN_SOCKSTAT -c | grep "sshd" > /dev/null ; then
				ts_last_ssh=`$BIN_DATE +%s`
				ssh_sleep_prevent="1"				
				[ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "Incoming SSH connection detected"
			else
				delta_t=$((`$BIN_DATE +%s`-$ts_last_ssh))
				[ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "No incoming SSH connection for $delta_t s"
				if [ "$delta_t" -le "$I_DELAY_SSH" ]; then
					ssh_sleep_prevent="1"
				fi
			fi
		fi
		
		# Check if curfew is reached
		curfew_sleep_request="0"
		if [ $I_CHECK_CURFEW_ACTIVE -eq "1" ]; then
			if isInTimeSlot "$I_BEG_POLL_CURFEW" "$I_END_POLL_CURFEW"; then
				[ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "In curfew timeslot: [ $I_BEG_POLL_CURFEW ; $I_END_POLL_CURFEW ]"
				curfew_sleep_request="1"
			fi
		fi

		# Check if no other devices are online for a certain duration
		noonline_sleep_request="0"	
		if [ $I_CHECK_NOONLINE_ACTIVE -eq "1" ]; then
			any_device_online="0"
			for ip_addr in $I_IP_ADDRS; do 	
				if $BIN_PING -c 1 -t 1 $ip_addr > /dev/null ; then
					any_device_online="1"
					[ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "Online device detected: $ip_addr (skipping any other device)"
					break
				fi
			done

			if [ "$any_device_online" -eq "1" ]; then	
				ts_last_online_device=`$BIN_DATE +%s`
			else
				delta_t=$((`$BIN_DATE +%s`-$ts_last_online_device))
				[ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "No devices online for $delta_t s"
				if [ "$delta_t" -gt "$I_DELAY_NOONLINE" ]; then
					noonline_sleep_request="1"	
				fi
			fi
		fi

		# Sleep if requested, but never if:
		# - The NAS woke-up shortly
		# - We are in the always on timeslot
		# - An SSH connection existed recently 
		awakefor=$((`$BIN_DATE +"%s"`-$ts_wakeup))
		if [ $in_always_on_timeslot -eq "0" -a $ssh_sleep_prevent -eq "0" -a $awakefor -gt $I_DELAY_PREVENT_SLEEP_AFTER_WAKE ]; then
			if [ $curfew_sleep_request -eq "1" ]; then
				log_info "$LOGFILE" "Curfew: Sleep requested"
				prevent_acquire_locks
				nasSleep $I_ACPI_STATE_CURFEW
 			elif [ $noonline_sleep_request -eq "1" ]; then
				log_info "$LOGFILE" "No other device online: sleep requested"
				prevent_acquire_locks
				nasSleep $I_ACPI_STATE_NOONLINE
			else
				allow_acquire_locks
			fi
		else
			allow_acquire_locks
		fi

		# wait until next poll	
		sleep $I_POLL_INTERVAL
	done
}



# Parse and validate the input parameters
if ! parseInputParams $ARGUMENTS > "$TMPFILE_ARGS"; then
	log_info "$LOGFILE" "-------------------------------------"
	cat "$TMPFILE_ARGS" | log_error "$LOGFILE"
	get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "$SCRIPT_NAME : Invalid arguments"
else
	log_info "$LOGFILE" "-------------------------------------"
	cat "$TMPFILE_ARGS" | log_info "$LOGFILE"
	
        # Return the log entries that have been logged during the current
        # execution of the script
	! main && get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "Sleep management issue"
fi

$BIN_RM "$TMPFILE_ARGS"
exit 0

