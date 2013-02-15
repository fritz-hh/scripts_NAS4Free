#!/bin/sh
#############################################################################
# Toolbox containing several functions aimed at:
# - recording that a script is running
# - detecting that a script is running
# - preventing several instances of the same script from running 
# - preventing any script from running 
#
# Author: fritz from NAS4Free forum
#############################################################################


##################################
# Record that a given script is starting now
#
# Param 1: script id. The script id can be either, the script
#	   name, or any other string. If a script with the same id is
#	   already running, the script will not get start allowance.
#	   The script name shall be used, if only one instance of the
#	   script should be executed at a given point in time, otherwise
#	   the lock id should not equal the script name.
# Return : 0 if the script is allowed to start
#          1 if this script id is already locked
#          2 if no script is allowed to start
#          3 if the user has insufficient right to write into the lock folder
##################################
script_start() {
	local script_id
	script_id="$1"

	# If the lock folder cannot be created
	if ! create_lock_folder; then
 		return 3
	fi 

	# If an instance is already running
	if is_script_running "$script_id"; then
		return 1
	fi	
	
	# If no script is allowed to start
        if [ -f "$CFG_FORBID_ANY_SCRIPT_START_FILE" ]; then
                return 2
        fi

	# record that script is now running
	# (i.e. create the lock file)
	echo "script started at the following time: `$BIN_DATE`" > "`get_lock_file_name_and_path $script_id`"

	return 0
}

##################################
# Record that a given script is ending now
#
# Param 1: script id (must be the same id, as the id 
#	   provided when the script started)
# Return : 0 if the script was running before
#          1 otherwise
##################################
script_end() {
	local script_id
	script_id="$1"

	# If the lock folder cannot be created
	if ! create_lock_folder; then
 		return 1
	fi
 
	# If the script was not running
	if ! is_script_running "$script_id"; then
		return 1
	fi

	# record that script is stopping
	# (i.e. delete the lock file)
	$BIN_RM -f "`get_lock_file_name_and_path $script_id`"

	return 0
}

##################################
# Ckecks if a given script is running
#
# Param 1: script id
# Return : 0 if the script is already running
#          1 otherwise
##################################
is_script_running() {
	local script_id
	script_id="$1"

	# If the lock folder cannot be created
	if ! create_lock_folder; then
 		return 1
	fi

	# if lock file does exists
	if [ -f "`get_lock_file_name_and_path $script_id`" ]; then
		return 0
	else
		return 1 
	fi 
}

##################################
# Check if any script is running
#
# Return : 0 if at least one script is running
# 	   1 if no script is running
##################################
is_any_script_running() {

	# If the lock folder cannot be created,
	# then no lock can exist
	# (this case should not happen)
	if ! create_lock_folder; then
 		return 1
	fi 

	# check if any script is running
	if [ "`$BIN_LS -A $CFG_RUNNING_SCRIPTS_FOLDER`" != "" ]; then
		return 0
	else
		return 1
	fi
}

##################################
# Get the list of scripts that are currently running
# the script names are separated by a semicolon (";")
#
# Return : The list of scripts
##################################
get_list_of_running_scripts() {
	$BIN_LS -A $CFG_RUNNING_SCRIPTS_FOLDER | $BIN_TR "\n" ";"_
}

##################################
# Prevent any script to start
# After a call of this function, the
# script_start() function will always return 1
##################################
prevent_scripts_to_start() {
	echo "No script allowed to start since: `$BIN_DATE`" > "$CFG_FORBID_ANY_SCRIPT_START_FILE"
}

##################################
# Allows any script to start 
# unless it is already running 
##################################
allow_scripts_to_start() {
	$BIN_RM -f $CFG_FORBID_ANY_SCRIPT_START_FILE
}

##################################
# Delete all locks
# This function should be called at NAS startup for robustness reasons
##################################
reset_locks() {
	allow_scripts_to_start
	$BIN_RM -f -r $CFG_RUNNING_SCRIPTS_FOLDER
}

##################################
# Ensure that the folder that should 
# contain the lock files exists
#
# Return : 0 if the folder existed or could be created
#          1 if the folder could not be created
##################################
create_lock_folder() {
	# Create the folder if it did not yet exist
	`$BIN_MKDIR -p -m go-w $CFG_RUNNING_SCRIPTS_FOLDER`
 	return $?
}

##################################
# Get the name (incl path) of the
# lock file corresponding to a given script id
#
# Param 1: script id
# Return : the lock file name (incl path)
##################################
get_lock_file_name_and_path() {
	local script_id
	script_id="$1"

	echo "$CFG_RUNNING_SCRIPTS_FOLDER/$script_id.lock"
}

################################## 
# Run the "main" function unless a lock with the given ID already exists 
# remove the lock at the end of the execution
#
# Param 1: log file name
# Param 2: lock id (should be a valid file name without path) 
# Return : 0 : no error
#          1 : could not start script because system is about to shutdown
#	   2 : any other error 
##################################
run_main() {
	local log_file lock_id ret_code err_in_main

	log_file="$1" 
	lock_id="$2"

	err_in_main=0

	script_start $lock_id
	ret_code="$?"
	if [ "$ret_code" -eq "0" ]; then
		! main && err_in_main=1
		if ! script_end $lock_id; then
			log_error "$log_file" "Could not delete lock file at end of execution"
			return 2
		fi
	elif [ "$ret_code" -eq "1" ]; then
		log_error "$log_file" "Could not start script (Another instance is running)"
		return 2
	elif [ "$ret_code" -eq "2" ]; then
		log_warning "$log_file" "Could not start script (The system is about to shutdown)"
		return 1
	else
		log_error "$log_file" "Could not start script (Unexpected issue)"
		return 2
	fi

	if [ "$err_in_main" -ne "0" ]; then
		return 2
	else
		return 0
	fi
}

