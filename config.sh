#!/bin/sh
#############################################################################
# File containing configuration parameters used by various scripts
#
# Author: fritz from NAS4Free forum
#
#############################################################################




################################################
# PARAMETER THAT CAN BE USED BY THE USER
################################################

# Mail configuration
################################################

CFG_MAIL_FROM="nas@isp.com"
CFG_MAIL_TO="admin@isp.com"

# Paths to log folder, temp folder...
################################################

CFG_TMP_FOLDER="tmp"				# Folder containing any temporary file (folder should exist)
CFG_LOG_FOLDER="log"				# Folder containing all log files (folder should exist)




################################################
# DO NOT CHANGE THE PARAMETERS BELOW
################################################

# Version of the package
################################################

VERSION="v1.0-rc3"

# Paths to specific temp files / folders ...
################################################

CFG_RUNNING_SCRIPTS_FOLDER="$CFG_TMP_FOLDER/running_scripts"		# Folder containing all lock files (e.g. files indicating that a script is running)
CFG_FORBID_ANY_SCRIPT_START_FILE="$CFG_TMP_FOLDER/no_script_start.lock"	# File aimed at notifying that no script should be started

# Path to used utilities
# (should not be changed by the user)
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
