#!/bin/sh
#############################################################################
# Script aimed at setting the NAS in sleep state whenever possible
# in order to save energy. 
#
# The script enables to define:
# - A timeslot where the system shall never sleep (-a),
# - A list of machines that shall prevent the NAS from going to sleep, if they are online (-n),
# - A curfew timeslot (-c),
# - The the NAS shall not go zo sleep if SSH /SMB connections exists (-s and -b)
#
# The script shall be launched at system startup
#
# Usage: manageAcpi.sh [-p duration] [-w duration] [-a beg,end] [-n ips,delay,acpi] [-s delay] [-b delay] [-c beg,end,acpi] [-vm]
#
#    -p duration : Define the duration (in seconds) between each respective poll (by default: 120)
#    -w duration : Define the duration (in seconds) for which the NAS should never sleep after it wakes up (by default: 600)
#    -a beg,end : Define a timeslot in which the NAS shall never go sleeping 
#                (e.g. because admin tasks are scheduled during this slot)
#                (This option superseeds a sleep order originating from -c)
#                + beg: time of the beginning of the slot (format: hh:mm)
#                + end: time of the end of the slot (format: hh:mm)
#    -n ips,delay,acpi : Define that the NAS shall not go to sleep if any of the IP addresses are online
#                + ips: IP addresses of the devices to poll, separated by "+" (Note: IP addresses shall be static)
#                + delay: delay in seconds between last device going offline and start of sleep
#                + acpi: the ACPI state selected for the sleep (3 or 5)
#    -s delay : Define that the NAS shall never go to sleep if an incoming SSH connection exists.
#                This function may be required in case the NAS is used as a destination of a remote backup.
#                (This option superseeds a sleep order originating from -c)
#                + delay: delay in seconds between the end of the connection and start of sleep
#    -b delay : Define that the NAS shall not go to sleep if an SMB connection to the NAS exists.
#                (Note: Some clients (i.e. Windows 10) might not close properly their SMB connection before shutdown.
#                In that case, you can instruct your samba server, to check regularly for stale connections use the following
#                configuration options in cmb.conf: "socket options = TCP_NODELAY SO_KEEPALIVE TCP_KEEPIDLE=30 TCP_KEEPCNT=3 TCP_KEEPINTVL=3")
#                + delay: delay in seconds between the end of the connection and start of sleep
#    -c beg,end,acpi : Define a curfew timeslot in which the NAS shall go sleeping.
#                + beg: time of the beginning of the slot (format: hh:mm)
#                + end: time of the end of the slot (format: hh:mm)
#                + acpi: the ACPI state selected for the sleep (3 or 5)
#    -v: Requests the log to be more verbose (Note: This is likely to prevent the disks to spin down)
#    -m: Send mail on ACPI state change
#
# Author: fritz from NAS4Free forum
#
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
readonly LOGFILE="$CFG_LOG_FOLDER/$SCRIPT_NAME.log"
readonly TMPFILE_ARGS="$CFG_TMP_FOLDER/$SCRIPT_NAME.$$.args.tmp"
readonly ACPI_STATE_LOGFILE="$CFG_LOG_FOLDER/acpi.log"

readonly REGEX_DUR="([0-9]+)"  # a duration as integer
readonly REGEX_HH="(([0-9])|([0-1][0-9])|([2][0-3]))"  # an hour between 0 to 23
readonly REGEX_MM="([0-5][0-9])"  # a minute between 00 and 59
readonly REGEX_TIME="($REGEX_HH[:]$REGEX_MM)"  # a time in hour and minute. E.g. 13:45
readonly REGEX_0_255="(([0-9])|([1-9][0-9])|([1][0-9][0-9])|([2][0-4][0-9])|([2][5][0-5]))"
readonly REGEX_IP="(($REGEX_0_255[.]){3,3}$REGEX_0_255)"  # An IP V4 address

# Set variables corresponding to the input parameters
ARGUMENTS="$@"

# Log verbosity (1: verbose, 0: less verbose)
I_VERBOSE=0

# 1: mail to be sent on ACPI state change, 0: otherwise
I_MAIL_ACPI_CHANGE=0

# Initialisation of the default values for the arguments of the script
I_POLL_INTERVAL=120  # number of seconds to wait between to cycles

I_DELAY_PREVENT_SLEEP_AFTER_WAKE="600"  # Amount of time during which the NAS will never go to sleep after waking up

I_CHECK_ALWAYS_ON=0  # 1 if the check shall be performed, 0 otherwise
I_BEG_ALWAYS_ON="00:00"  # time when the NAS shall never sleep (because of management tasks like backup may start)
I_END_ALWAYS_ON="00:00"  # If end = beg => 24 hours

I_CHECK_SSH_ACTIVE=0  # 1 if the check shall be performed, 0 otherwise
I_DELAY_SSH=0  # Delay in seconds between the moment where the SSH connection stops and the moment where the NAS may sleep

I_CHECK_SMB_ACTIVE=0  # 1 if the check shall be performed, 0 otherwise
I_DELAY_SMB=0  # Delay in seconds between the moment where the SMB connection stops and the moment where the NAS may sleep

I_CHECK_CURFEW_ACTIVE=0  # 1 if the check shall be performed, 0 otherwise
I_BEG_POLL_CURFEW="00:00"  # time when the script enters the sleep state (except if tasks like backup are running)
I_END_POLL_CURFEW="00:00"  # If end = beg => 24 hours
I_ACPI_STATE_CURFEW=0  # ACPI state

I_CHECK_NOONLINE_ACTIVE=0  # 1 if the check shall be performed, 0 otherwise
I_IP_ADDRS=""  # IP addresses of the devices to be polled, separated by a space character)
I_DELAY_NOONLINE=0  # Delay in seconds between the moment where no devices are online anymore and the moment where the NAS shall sleep
I_ACPI_STATE_NOONLINE=3  # ACPI state if no other device is online

# Initialization the global variables
awake=0  # 1=NAS is awake, 0=NAS is about to sleep (resp. just woke up)


##################################
# Check script input parameters
#
# Params: all parameters of the shell script
# return : 1 if an error occured, 0 otherwise
##################################
parseInputParams() {

    local regex_a regex_c regex_n opt w_min

    regex_a="^$REGEX_TIME[,]$REGEX_TIME$"
    regex_c="^($REGEX_TIME[,]){2,2}[35]$"
    regex_n="^$REGEX_IP([+]$REGEX_IP){0,}[,]$REGEX_DUR[,][35]$"

    w_min=300

    # parse the parameters
    while getopts ":p:w:a:s:b:c:n:vm" opt; do

        case $opt in
            p)
                if ! echo "$OPTARG" | grep -E "^$REGEX_DUR$" >/dev/null; then
                    echo "Invalid parameter \"$OPTARG\" for option: -p. Should be a positive integer"
                    return 1
                fi
                
                I_POLL_INTERVAL="$OPTARG"
                ;;
            w)
                if ! echo "$OPTARG" | grep -E "^$REGEX_DUR$" >/dev/null; then
                    echo "Invalid parameter \"$OPTARG\" for option: -w. Should be a positive integer"
                    return 1
                fi

                I_DELAY_PREVENT_SLEEP_AFTER_WAKE="$OPTARG"

                if [ "$I_DELAY_PREVENT_SLEEP_AFTER_WAKE" -lt "$w_min" ] ; then
                    echo "The value passed to the -w option must be at least $w_min s."
                    echo "Replacing the provided value ($I_DELAY_PREVENT_SLEEP_AFTER_WAKE s) with the value $w_min s"
                    echo "Rationale: If other options are not set correctly, the server may always"
                    echo "shutdown/sleep just after booting making the server unusable"
                    I_DELAY_PREVENT_SLEEP_AFTER_WAKE="$w_min"
                fi
                ;;
            a)
                if ! echo "$OPTARG" | grep -E "$regex_a" >/dev/null; then
                    echo "Invalid parameter \"$OPTARG\" for option: -a. Should be \"hh:mm,hh:mm\""
                    return 1                
                fi

                I_CHECK_ALWAYS_ON="1"
                I_BEG_ALWAYS_ON=`echo "$OPTARG" | cut -f1 -d,`
                I_END_ALWAYS_ON=`echo "$OPTARG" | cut -f2 -d,`
                ;;
            s)
                if ! echo "$OPTARG" | grep -E "^$REGEX_DUR$" >/dev/null; then
                    echo "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -s. Should be a positive integer"
                    return 1
                fi

                I_CHECK_SSH_ACTIVE="1"
                I_DELAY_SSH="$OPTARG"
                ;;
            b)
                if ! echo "$OPTARG" | grep -E "^$REGEX_DUR$" >/dev/null; then
                    echo "$LOGFILE" "Invalid parameter \"$OPTARG\" for option: -b. Should be a positive integer"
                    return 1
                fi

                I_CHECK_SMB_ACTIVE="1"
                I_DELAY_SMB="$OPTARG"
                ;;
            c)
                if ! echo "$OPTARG" | grep -E "$regex_c" >/dev/null; then
                    echo "Invalid parameter \"$OPTARG\" for option: -c. Should be \"hh:mm,hh:mm,acpi_state\""
                    return 1
                fi

                I_CHECK_CURFEW_ACTIVE="1"
                I_BEG_POLL_CURFEW=`echo "$OPTARG" | cut -f1 -d,`
                I_END_POLL_CURFEW=`echo "$OPTARG" | cut -f2 -d,`
                I_ACPI_STATE_CURFEW=`echo "$OPTARG" | cut -f3 -d,`
                ;;
            n)
                if ! echo "$OPTARG" | grep -E "$regex_n" >/dev/null; then
                    echo "Invalid parameter \"$OPTARG\" for option: -n. Should be \"ips,delay,acpi_state\""
                    return 1
                fi

                I_CHECK_NOONLINE_ACTIVE="1"
                I_IP_ADDRS=`echo "$OPTARG" | cut -f1 -d, | sed 's/+/ /g'`
                I_DELAY_NOONLINE=`echo "$OPTARG" | cut -f2 -d,`
                I_ACPI_STATE_NOONLINE=`echo "$OPTARG" | cut -f3 -d,`
                ;;
            v) I_VERBOSE=1 ;;
            m) I_MAIL_ACPI_CHANGE=1 ;;
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
#       the timeslot is considered to last the whole day.
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

    if [ "$currentTimestamp" -gt "$startTimestamp" ] && [ "$currentTimestamp" -le "$endTimestamp" ]; then
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

    if does_any_lock_exist; then
        log_info "$LOGFILE" "Shutdown not possible. The following scripts are running: `get_list_of_locks`"
        return 1
    fi

    msg="Shutting down the system to save energy (ACPI state : S$acpi_state)"

    if [ $acpi_state -eq "5" ]; then  # Soft OFF

        log_info "$LOGFILE" "$msg"
        log_info "$ACPI_STATE_LOGFILE" "S$acpi_state"

        if [ $I_MAIL_ACPI_CHANGE -eq "1" ]; then
            get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "NAS going to sleep to save energy (ACPI state: S$acpi_state)"
        fi

        awake="0"
        $BIN_SHUTDOWN -p now "$msg"

    elif [ $acpi_state -eq "3" ]; then  # Suspend to RAM

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
}


##################################
# Main
##################################
main() {
    local ts_last_online_ip ts_last_ssh ts_last_smb ts_wakeup in_always_on_timeslot \
        ssh_sleep_prevent smb_sleep_prevent curfew_sleep_request \
        ip_online_sleep_prevent delta_t awakefor

    # initialization of local variables
    ts_last_online_ip=`$BIN_DATE +%s`  # Timestamp when the last device was detected to be online
    ts_last_ssh=`$BIN_DATE +%s`  # Timestamp when the last SSH connection ended
    ts_last_smb=`$BIN_DATE +%s`  # Timestamp when the last SMB connection ended
    ts_wakeup=`$BIN_DATE +%s`  # Timestamp when the NAS woke up last time
    in_always_on_timeslot="0"  # 1=We are currently in the always on timeslot, 0 otherwise
    ip_online_sleep_prevent="0"  # 1=Sleep prevented because an IP address is reachable, 0 otherwise
    ssh_sleep_prevent="0"  # 1=Sleep prevented by SSH, 0 otherwise
    smb_sleep_prevent="0"  # 1=Sleep prevented by SMB, 0 otherwise
    curfew_sleep_request="0"  # 1=Sleep requested by curfew check, 0 otherwise

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
    printf '%-35s %s\n' "- CHECK_SMB_ACTIVE:" "$I_CHECK_SMB_ACTIVE" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- DELAY_SMB:" "$I_DELAY_SMB" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- CHECK_CURFEW_ACTIVE:" "$I_CHECK_CURFEW_ACTIVE" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- BEG_POLL_CURFEW:" "$I_BEG_POLL_CURFEW" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- END_POLL_CURFEW:" "$I_END_POLL_CURFEW" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- ACPI_STATE_CURFEW:" "$I_ACPI_STATE_CURFEW" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- CHECK_NOONLINE_ACTIVE:" "$I_CHECK_NOONLINE_ACTIVE" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- ACPI_STATE_NOONLINE:" "$I_ACPI_STATE_NOONLINE" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- DELAY_NOONLINE:" "$I_DELAY_NOONLINE" | log_info "$LOGFILE"
    printf '%-35s %s\n' "- IP_ADDRS:" "$I_IP_ADDRS" | log_info "$LOGFILE"


    # record in the ACPI state log, that the script is not running anymore
    trap 'log_info "$ACPI_STATE_LOGFILE" "UNTRACKED"; exit 0' INT TERM
    

    # Loop until the NAS is switched off
    while true; do
    
    
        [ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "-----------------"

        # If the NAS just woke up
        if [ $awake -eq "0" ]; then
            awake="1"
            ts_wakeup=`$BIN_DATE +%s`
            ts_last_online_ip=`$BIN_DATE +%s`

            log_info "$ACPI_STATE_LOGFILE" "S0"
            log_info "$LOGFILE" "NAS just woke up (S0). Preventing sleep during the next $I_DELAY_PREVENT_SLEEP_AFTER_WAKE s"

            if [ $I_MAIL_ACPI_CHANGE -eq "1" ]; then
                get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "NAS just woke up (S0)"
            fi
        fi

        # wait until next poll
        sleep $I_POLL_INTERVAL

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
            # Check if an incoming ssh connection exists
            if $BIN_SOCKSTAT -c | grep "sshd" > /dev/null ; then
                ts_last_ssh=`$BIN_DATE +%s`
                [ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "Incoming SSH connection detected"
            fi
            delta_t=$((`$BIN_DATE +%s`-$ts_last_ssh))
            [ "$delta_t" -le "$I_DELAY_SSH" ] && ssh_sleep_prevent="1"
        fi

        # Check if an incoming SMB connection existed recently
        smb_sleep_prevent="0"
        if [ $I_CHECK_SMB_ACTIVE -eq "1" ]; then
            # Check if an incoming smb connection exists
            if $BIN_SMBSTATUS --processes | grep -E "$REGEX_IP" > /dev/null; then
                ts_last_smb=`$BIN_DATE +%s`
                smb_host=`$BIN_SMBSTATUS --processes | grep -o -E "$REGEX_IP" | head -n 1` 
                [ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "SMB client detected: $smb_host (other devices may be connected too)"
            fi
            delta_t=$((`$BIN_DATE +%s`-$ts_last_smb))
            [ "$delta_t" -le "$I_DELAY_SMB" ] && smb_sleep_prevent="1"
        fi

        # Check if curfew is reached
        curfew_sleep_request="0"
        if [ $I_CHECK_CURFEW_ACTIVE -eq "1" ]; then
            if isInTimeSlot "$I_BEG_POLL_CURFEW" "$I_END_POLL_CURFEW"; then
                [ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "In curfew timeslot: [ $I_BEG_POLL_CURFEW ; $I_END_POLL_CURFEW ]"
                curfew_sleep_request="1"
            fi
        fi

        # Check if any listed IP address was online recently
        ip_online_sleep_prevent="0"
        if [ $I_CHECK_NOONLINE_ACTIVE -eq "1" ]; then
            for ip_addr in $I_IP_ADDRS; do
                if $BIN_PING -c 1 -t 1 $ip_addr > /dev/null ; then
                    ts_last_online_ip=`$BIN_DATE +%s`
                    [ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "Online IP address detected: $ip_addr (other devices may be online too)"
                    break
                fi
            done
            delta_t=$((`$BIN_DATE +%s`-$ts_last_online_ip))
            [ "$delta_t" -lt "$I_DELAY_NOONLINE" ] && ip_online_sleep_prevent="1"
        fi

        # Logic to control sleep (from highest precedance to lowest precedance)
        # - Do not sleep if:
        #    - The NAS woke-up recently
        #    - We are in the always on timeslot (see '-a')
        #    - An SSH connection exists (or existed recently) (see '-s')
        # - Sleep if within the curfew timeslot (see '-c')
        # - Do not sleep if:
        #    - A device is online (or was recently) (see '-n')
        #    - An SMB connection exists (or existed recently) (see '-b')
        # - Sleep in any other case
        awakefor=$((`$BIN_DATE +"%s"`-$ts_wakeup))
        if [ $in_always_on_timeslot -eq "1" ] || [ $ssh_sleep_prevent -eq "1" ] || [ $awakefor -lt $I_DELAY_PREVENT_SLEEP_AFTER_WAKE ]; then
            [ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "Preventing to go to sleep due to always-on timeslot, SSH or because the NAS woke-up recently"
            allow_acquire_locks
            continue
        fi

        if [ $curfew_sleep_request -eq "1" ]; then
            log_info "$LOGFILE" "Curfew: Sleep requested"
            prevent_acquire_locks
            nasSleep $I_ACPI_STATE_CURFEW
            continue
        fi

        if [ $smb_sleep_prevent -eq "1" ] || [ $ip_online_sleep_prevent -eq "1" ]; then
            [ $I_VERBOSE -eq "1" ] && log_info "$LOGFILE" "Preventing to go to sleep due to SMB connection or because a configured machine is online"
            allow_acquire_locks
            continue
        fi

        prevent_acquire_locks
        nasSleep $I_ACPI_STATE_NOONLINE

    done
}


# Parse and validate the input parameters
if ! parseInputParams $ARGUMENTS > "$TMPFILE_ARGS"; then
    log_info "$LOGFILE" "-------------------------------------"
    cat "$TMPFILE_ARGS" | log_error "$LOGFILE"
    $BIN_RM "$TMPFILE_ARGS"
    get_log_entries_ts "$LOGFILE" "$START_TIMESTAMP" | sendMail "$SCRIPT_NAME : Invalid arguments"
    exit 1
fi

$BIN_RM "$TMPFILE_ARGS"
log_info "$LOGFILE" "-------------------------------------"
main  # Endless loop that should never return
