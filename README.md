Hi all,

I am a happy Freenas7/Nas4Free/Xigmanas user since 2010.
Time to give something back to the community!!!

Since 2011 I developped various scripts to complement missing functions of Freenas7/Nas4free (The scripts can probably be used on other FreeBSD distributions like FreeNAS8, but it was not tested)

These scripts will probably be usefull for many users having a similar usage profile as myself:
- NAS access from several computers in a home network
- NAS should only consume power when it is required (electricity is expensive here) (makes use of acpiconf)
- Prevent data loss (through regular monitoring)
- Be able to go back to a previous version of the data if needed
- NAS containing 2 ZFS pools (one for data shared with CIFS and one containing the backup of the data)

All scripts that I provide to you rely on a shell script library of common functions:
- To log what the script is doing in a file (resp. extract data from the log)
- To report issues per mail
- To prevent a script from be executed twice concurrently and prevent a script to start if the NAS if about to sleep

The scripts rely on a common configuration file (config.sh) in which the email addresses, path to log files and tmp files... can be set


DESCRIPTION
===========

In my opinion, the scripts are well documented enough to be understood by anybody having shell script knowledge.
The script usage (e.g. arguments that can be passed) as well as a detailed description of the functions is provided in the header of each script. PLEASE READ THE HEADER OF THE SCRIPT BEFORE USING IT!
I tried to develop the scripts to be as versatile as possible (the scripts accept various optional arguments), so that they should help many NAS4Free users

scrubPools.sh:
--------------

- Scrub all the ZPOOLS and report the results in a log file.
- Send a mail if an error is detected
- Typical scheduling: once a week

checkPools.sh:
--------------

- Checks the status of the ZPOOLS and report the results in a log file.
- Send a mail if an error is detected
- Typical scheduling: every hour

checkTemps.sh: (Thanks to miGi from NAS4Free forum)
--------------

- Checks the temperature of each respective CPU / CPU core and of each respective drive and report the results in a log file.
- Send a mail if the CPU (resp. HDD) temperature threshold is reached
- Typical scheduling: every hour or more often

checkSpace.sh:
--------------

- Check if there is enough space in the respective ZFS file systems (The filesystems to monitor as well as the threshold is configurable)
- Report the results in a log file.
- Send a mail if the space threshold is reached
- Typical scheduling: every day for the data pool
- Typical scheduling: every week for the backup pool

manageSnapshots.sh:
-------------------

- Create hourly/daily/weekly/monthly snapshots of a ZFS filesystem (and child filesystems) and keep a configurable number of them (i.e. delete the superfluous snapshots)
- Report the results in a log file.
- Send a mail if an error occurs
- This script was specially designed to work fine even if the NAS is NOT always ON. E.g. if the NAS is OFF when the next monthly snapshot should be created, the script will create it as soon as the NAS is back on.
- This script does only need to be scheduled every hour and it will take care of any type of snapshot (hourly/daily/...)

Note 1: In Services|CIFS/SMB|Share|Edit, set the parameter "Shadow Copy format" to "%Y%m%d_%H%M_autosnap_type%S" in order to make the snapshots visible in the windows shadow copy client

backupData.sh:
--------------

- Backup incrementally (using zfs send/receive) the content of a set of ZFS filesystems into another pool located either in the same NAS box, or in a remote machine
- Report the results in a log file.
- Send a mail if an error occurs
- This script was designed to able to cope with the deletion of superfluous snapshots in the data pool (This may be issued by the manageSnapshots.sh script)
- Typical scheduling: once a week

manageAcpi.sh:
--------------

- Controls shutdown (S5) or sleep (S3) of the NAS based on various parameters. E.g.:
    - If no computer that may access the NAS is online during a certain time (based on the IP address)
    - If the curfew is reached!
- (if requested) prevents a shutdown / sleep during a configurable timeslot
- (if requested) prevents a shutdown / sleep if another machine is accessing the NAS using SSH
- (if requested) prevents a shutdown / sleep if another machine is accessing the NAS using SMB
- Prevents a shutdown / sleep to be issued when one of the above administrative scripts is running
- Reports the results in a log file.
- Script to be started at NAS startup. The script runs as an endless loop

Note 1: Depending on your motherboard and on your BIOS settings, the script may or may not work on your NAS.
Note 2: This script requires static IP addresses (of course static DHCP is OK too) on your NAS and other any other computer.
Note 3: I use Wake on LAN to wake the NAS. The WOL paket can be sent by a DD-WRT router or a Raspberry Pi automatically when one of my computers is online (see script here: https://github.com/fritz-hh/autowake_NAS)

acpiStats.sh:
-------------

- Compute the percentage of time the NAS spent in each respective ACPI state (S0/S3/S5)
- Compute the average power usage in watt (based on typical power usage in S0/S3/S5)
- Report the results in a log file.
- Send a mail if an error occurs
- Typical scheduling: once a week

Note 1: This script requires manageAcpi.sh to be started when your NAS starts (indeed manageAcpi.sh generates a file (acpi.log) that is required by acpiStats.sh)

reportFromLogs.sh:
------------------

- Scripts aimed at generating a extract of all log files (the part that has been populated during the last week)
- Additionally it generates statistics on the number of errors and warnings that occured in each scripts
- This script can be sheduled in the "Status|Email Report" section of nas4free


DOWNLOAD:
=========

https://github.com/fritz-hh/scripts_NAS4Free/releases

INSTALLATION AND CONFIGURATION:
===============================

https://github.com/fritz-hh/scripts_NAS4Free/wiki

SUPPORT / QUESTIONS:
====================

http://forums.nas4free.org/viewtopic.php?f=70&t=2197

DISCLAIMER:
===========

Even though the scripts were developped with particular focus on robustness, I do not provide any warranty with the script !
(I am nor a freeBSD expert nor a SW developper, but a simple user)

Any contribution (problem reports, fixes, improvement of the wiki, comments, new functions) is welcome!

Feel free to use the scripts on your own NAS!

Kind Regards,

fritz
