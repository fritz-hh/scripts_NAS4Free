#!/bin/sh
####################################################################
# Function aimed at sending a mail to the administrator of the nas
#
# Author: fritz from NAS4Free forum
#
# Param 1: Subject of the mail
# Param 2: Content of the mail (Not required if data are provided from a pipe)
####################################################################
sendMail() {
    local host subject body line
    
    # Initialize variables
    host=`$BIN_HOSTNAME -s`
    subject="$1"
    body=""

    # If the mail body is provided though the pipe
    if [ ! -t 0 ]; then
        local line=""
        while read line
        do
            body="$body\n$line"
        done
    # if the mail body is NOT provided though the pipe
    else
        body="$2"
    fi    

    # Send the mail
    $BIN_PRINTF "From: $CFG_MAIL_FROM\nTo: $CFG_MAIL_TO\nSubject: $subject\n\n$body" | $BIN_MSMTP --file=$CFG_MSMTP_CONF -t

    return 0
}

