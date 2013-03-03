#!/bin/sh
#############################################################################
# File containing configuration parameters used by various scripts
#
# Author: fritz from NAS4Free forum
#
#############################################################################




################################################
# PARAMETERS THAT CAN BE MODIFIED BY THE USER
################################################

# Mail configuration
################################################

CFG_MAIL_FROM="nas@isp.com"	# Enter the mail address of the NAS here (should be the same address than in NAS GUI: System|Advanced|Email)
CFG_MAIL_TO="admin@isp.com"	# Enter the email of the NAS administrator here

# Paths to log folder, temp folder...
#
# ATTENTION: 	THESE FOLDERS MUST EXIST !!!
# 		IF THEY DON'T, PLEASE CREATE THEM
################################################

CFG_TMP_FOLDER="./tmp"		# Folder used to write temporary file
CFG_LOG_FOLDER="./log"		# Folder containing all log files 




################################################
# DO NOT CHANGE THE PARAMETERS BELOW
################################################

# Version of the package
################################################

VERSION="v1.0-rc3+fixes"

# Paths to specific temp files / folders ...
################################################

CFG_RUNNING_SCRIPTS_FOLDER="$CFG_TMP_FOLDER/running_scripts"		# Folder containing all lock files (e.g. files indicating that a script is running)
CFG_FORBID_ANY_SCRIPT_START_FILE="$CFG_TMP_FOLDER/no_script_start.lock"	# File aimed at notifying that no script should be started

# Path to used utilities
################################################

BIN_RM="/bin/rm"
BIN_LS="/bin/ls"
BIN_MKDIR="/bin/mkdir"
BIN_TR="/usr/bin/tr"

BIN_DATE="/bin/date"
BIN_PRINTF="/usr/bin/printf"

BIN_MSMTP="/usr/local/bin/msmtp"
CFG_MSMTP_CONF="/var/etc/msmtp.conf"

BIN_ZPOOL="/sbin/zpool"
BIN_ZFS="/sbin/zfs"

BIN_HOSTNAME="/bin/hostname"

BIN_SHUTDOWN="/sbin/shutdown"
BIN_ACPICONF="/usr/sbin/acpiconf"
BIN_PING="/sbin/ping"

BIN_SMARTCTL="/usr/local/sbin/smartctl"

BIN_SSH="/usr/bin/ssh"
BIN_SOCKSTAT="/usr/bin/sockstat"
