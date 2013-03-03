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
# Acquire a lock
#
# Param 1: lock id. If the lock was already acquired, the lock cannot be acquired anymore
# Return : 0 if the lock could be acquired
#          1 if the lock was already acquired
#          2 if no lock at all are allowed to be acquired
#          3 if it is not possible to create the folder that shall contain all locks
##################################
acquire_lock() {
	local lock_id
	lock_id="$1"

	# Ensure that the folder that shall contain all locks exists
	if ! ensure_lock_folder_exits; then
		return 3
	fi 
	
	# If no lock is allowed to be acquired
	if [ -f "$CFG_FORBID_ANY_SCRIPT_START_FILE" ]; then
		return 2
	fi

	# acquire the lock 
	if $BIN_MKDIR "`get_lock_path $lock_id`"; then
		return 0
	else
		return 1
	fi
}

##################################
# Release a lock that was acquired before
#
# Param 1: lock id (must be the same id, as the id 
#	   provided when the lock was acquired)
# Return : 0 if the lock could be released
#          1 otherwise
##################################
release_lock() {
	local lock_id
	lock_id="$1"

	# Ensure that the folder that shall contain all locks exists
	if ! ensure_lock_folder_exits; then
 		return 1
	fi
 
	# Release the lock
	if $BIN_RM -r "`get_lock_path $lock_id`"; then
		return 0
	else
		return 1
	fi
}

##################################
# Check if any lock exists currently
#
# Return : 0 if at least one lock exists
# 	   1 if no lock exists
##################################
does_any_lock_exist() {

	# If the folder that shall contain all locks cannot be created,
	# then no lock can exist
	# (this case should not happen)
	if ! ensure_lock_folder_exits; then
 		return 1
	fi 

	# check if any lock exists
	if [ "`$BIN_LS -A $CFG_RUNNING_SCRIPTS_FOLDER`" != "" ]; then
		return 0
	else
		return 1
	fi
}

##################################
# Get the list of locks that currently exist (i.e. were acquired) separated by a semicolon (";")
#
# Return : The list of locks
##################################
get_list_of_locks() {
	$BIN_LS -A "$CFG_RUNNING_SCRIPTS_FOLDER" | $BIN_TR "\n" ";"
}

##################################
# Prevent any lock to be acquired
# After a call of this function, the
# acquire_lock() function will always return 1
##################################
prevent_acquire_locks() {
	echo "No lock allowed to be acquired since: `$BIN_DATE`" > "$CFG_FORBID_ANY_SCRIPT_START_FILE"
}

##################################
# Allows any lock to be acquired 
# unless it was already acquired 
##################################
allow_acquire_locks() {
	$BIN_RM -f "$CFG_FORBID_ANY_SCRIPT_START_FILE"
}

##################################
# Delete all locks
# This function may be called at NAS startup for robustness reasons
##################################
reset_locks() {
	allow_acquire_locks
	$BIN_RM -f -r "$CFG_RUNNING_SCRIPTS_FOLDER"
}

##################################
# Ensure that the folder that should 
# contain the lock files exists
#
# Return : 0 if the folder existed or could be created
#          1 if the folder could not be created
##################################
ensure_lock_folder_exits() {
	$BIN_MKDIR -p -m go-w "$CFG_RUNNING_SCRIPTS_FOLDER"
	return $?
}

##################################
# Get the path corresponding to a given lock id
#
# Param 1: lock id
# Return : the lock path
##################################
get_lock_path() {
	local lock_id
	lock_id="$1"

	echo "$CFG_RUNNING_SCRIPTS_FOLDER/$lock_id.lock"
}

################################## 
# Run the "main" function unless a lock with the given ID already exists 
# remove the lock at the end of the execution
#
# Param 1: log file name
# Param 2: lock id (should be a folder name without its path) 
# Return : 0 : no error
#          1 : could not start script because the system is (probably) about to shutdown
#	   2 : any other error 
##################################
run_main() {
	local log_file lock_id ret_code err_in_main

	log_file="$1" 
	lock_id="$2"

	err_in_main=0

	acquire_lock "$lock_id"
	ret_code="$?"
	if [ "$ret_code" -eq "0" ]; then
		! main && err_in_main=1
		if ! release_lock "$lock_id"; then
			log_error "$log_file" "Could not delete lock at end of execution"
			return 2
		fi
	elif [ "$ret_code" -eq "1" ]; then
		log_error "$log_file" "Could not start script (Another instance is running)"
		return 2
	elif [ "$ret_code" -eq "2" ]; then
		log_info "$log_file" "Could not start script (The system is probably about to shutdown)"
		return 1
	elif [ "$ret_code" -eq "3" ]; then
		log_error "$log_file" "Lock folder \"$CFG_RUNNING_SCRIPTS_FOLDER\" could not be created"
		return 2	
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

