#!/bin/sh
#############################################################################
# Script aimed at computing how much time the NAS spent in each respective
# ACPI state
#
# Usage: acpiStats.sh [-p W0,W3,W5]
#
#     -p W0: typical power consumption in mW while in ACPI state S0
#        W3: typical power consumption in mW while in ACPI state S3
#        W5: typical power consumption in mW while in ACPI state S5
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
readonly TMPFILE="$CFG_TMP_FOLDER/$SCRIPT_NAME.$$.stat.tmp"
readonly TMPFILE_ARGS="$CFG_TMP_FOLDER/$SCRIPT_NAME.$$.args.tmp"
readonly ACPI_STATE_LOGFILE="$CFG_LOG_FOLDER/acpi.log"

# Set variables corresponding to the input parameters
ARGUMENTS="$@"

# Initialization of constants
readonly S_IN_WEEK=604800
readonly S_IN_MONTH=2592000
readonly S_IN_YEAR=31536000

# Initialisation of the default values for the arguments of the script
I_COMPUTE_CONSUMPTION="0"
I_W_S0="0"  # Power consumed by the NAS in S0 (in mW)
I_W_S3="0"  # Power consumed by the NAS in S3 (in mW)
I_W_S5="0"  # Power consumed by the NAS in S5 (in mW)


##################################
# Check script input parameters
#
# Params: all parameters of the shell script
# return : 1 if an error occured, 0 otherwise
##################################
parseInputParams() {
    local regex_pow regex_pows opt

    regex_pow="([1-9][0-9]*)"
    regex_pows="$regex_pow[,]$regex_pow[,]$regex_pow"

    # parse the optional arguments
    while getopts ":p:" opt; do

        case $opt in
            p)
                if ! echo "$OPTARG" | grep -E "^$regex_pows$" >/dev/null; then
                    echo "Invalid parameter \"$OPTARG\" for option: -p. Should be \"pS0,pS3,pS5\", were pSx are integer"
                    return 1                
                fi
                
                I_COMPUTE_CONSUMPTION="1"
                I_W_S0=`echo "$OPTARG" | cut -f1 -d,`
                I_W_S3=`echo "$OPTARG" | cut -f2 -d,`
                I_W_S5=`echo "$OPTARG" | cut -f3 -d,`
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
# Compute ACPI state stastistics
#
# Param 1: Log file containing the data to analyze
# Param 2: String to be search for in the 3rd column of the log file
# Return : The percentage of time the NAS spent in the state described by the string
##################################
compute_stat() {

    local log_file pattern date_format duration duration_tot current_line \
        nbLinesInFile current_date current_ts current_pattern old_ts old_pattern \
        log_entry deltat

    log_file="$1"
    pattern="$2"

    date_format=`ts_format`

    duration="0"
    duration_tot="0"

    current_line="1"

    nbLinesInFile=`wc -l "$log_file" | awk ' { print $1 } '`  # find number of lines

    # Itterate the file to compute the time spent by the NAS
    # in the state described by the pattern
    while [ "$current_line" -le "$nbLinesInFile" ]
    do
        old_ts="$current_ts"
        old_pattern="$current_pattern"

        log_entry=`sed "$current_line"!d "$log_file"`

        # get line data from log file
        current_date=`echo "$log_entry" | cut -f1`
        current_pattern=`echo "$log_entry" | cut -f3`
        current_ts=`$BIN_DATE -j -f "$date_format" "$current_date" +%s`

        # compute duration for pattern
        if [ "$current_line" -gt "1" ]; then
            deltat=$(($current_ts-$old_ts))
            duration_tot=$(($duration_tot+$deltat))
            if [ "$old_pattern" = "$pattern" ]; then
                duration=$(($duration+$deltat))
            fi
        fi

        current_line=$(($current_line+1))
    done

    # Take into account the time between the last
    # timestamp and now
    old_ts="$current_ts"
    current_ts=`$BIN_DATE +%s`
    deltat=$(($current_ts-$old_ts))
    duration_tot=$(($duration_tot+$deltat))
    if [ "$current_pattern" = "$pattern" ]; then
        duration=$(($duration+$deltat))
    fi

    echo $(($duration*100/$duration_tot))
}



##################################
# Log the statistics for the file
# provided as parameter
#
# param 1: file name (inkl. path)
# return : 1 if an error occured, 0 otherwise
##################################
log_stats() {
    local S0p S3p S5p file percentage_tot

    file=$1

    # compute statistics
    S0p=`compute_stat "$file" "S0"`
    S3p=`compute_stat "$file" "S3"`
    S5p=`compute_stat "$file" "S5"`

    if [ "$I_COMPUTE_CONSUMPTION" -eq "1" ]; then
        log_info "$LOGFILE" "S0 ($(($I_W_S0/1000)) W) (Working)       : $S0p percent"
        log_info "$LOGFILE" "S3 ($(($I_W_S3/1000)) W) (Suspend to RAM): $S3p percent"
        log_info "$LOGFILE" "S5 ($(($I_W_S5/1000)) W) (Soft off)      : $S5p percent"
        W_average=$((($I_W_S0*$S0p+$I_W_S3*$S3p+$I_W_S5*$S5p)/100/1000))
        log_info "$LOGFILE" "Average power comsumption: $W_average W"
    else
        log_info "$LOGFILE" "S0 (Working)       : $S0p percent"
        log_info "$LOGFILE" "S3 (Suspend to RAM): $S3p percent"
        log_info "$LOGFILE" "S5 (Soft off)      : $S5p percent"
    fi

    # consistency check
    percentage_tot=$(($S0p+$S3p+$S5p))
    if [ $percentage_tot -lt "98" ] || [ $percentage_tot -gt "102" ]; then
        log_warning "$LOGFILE" "The sum of the percentages is not equal to 100, but equals $percentage_tot"
        return 1
    fi
    
    return 0
}


##################################
# Main
##################################
main() {
    local oldest_acpi_ts

    log_info "$LOGFILE" "Starting computation of ACPI statistics"

    oldest_acpi_ts=`get_log_oldest_ts "$ACPI_STATE_LOGFILE"`
    if [ "$?" -ne "0" ]; then
        log_error "$LOGFILE" "Could not read \"$ACPI_STATE_LOGFILE\" that should contain the acpi states history"
        return 1
    fi

    if [ $oldest_acpi_ts -le `$BIN_DATE -j -v -"$S_IN_WEEK"S +%s` ]; then
        get_log_entries "$ACPI_STATE_LOGFILE" "$S_IN_WEEK" > $TMPFILE
        log_info "$LOGFILE" "ACPI Statistics for the last week:"
        if ! log_stats $TMPFILE; then return 1; fi
    fi

    if [ $oldest_acpi_ts -le `$BIN_DATE -j -v -"$S_IN_MONTH"S +%s` ]; then
        get_log_entries "$ACPI_STATE_LOGFILE" "$S_IN_MONTH" > $TMPFILE
        log_info "$LOGFILE" "ACPI Statistics for the last month:"
        if ! log_stats $TMPFILE; then return 1; fi
    fi

    if [ $oldest_acpi_ts -le `$BIN_DATE -j -v -"$S_IN_YEAR"S +%s` ]; then
        get_log_entries "$ACPI_STATE_LOGFILE" "$S_IN_YEAR" > $TMPFILE
        log_info "$LOGFILE" "ACPI Statistics for the last year:"
        if ! log_stats $TMPFILE; then return 1; fi
    fi

    cat "$ACPI_STATE_LOGFILE" > $TMPFILE
    log_info "$LOGFILE" "ACPI Statistics since the beginning of the log (`$BIN_DATE -j -f %s $oldest_acpi_ts`):"
    if ! log_stats $TMPFILE; then return 1; fi

    # Delete the temporary file
    $BIN_RM -f "$TMPFILE"

    return 0
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

