Hi all,

I am a happy Freenas7/Nas4Free user since more than 2 years.
Time to give something back to the community!!!

During the last 2 years I developped various scripts to complement missing functions of Freenas7/Nas4free.
Those scripts will probably be usefull for many users having the same usage profile as myself:
- NAS access from several computers in a home network
- NAS containing 2 ZFS pools (one for data shared with CIFS and one containing the backup of the data)
- NAS should only consume power when it is required (electricity is expensive here) (makes use of acpiconf)
- Prevent data loss (through regular monitoring)
- Be able to go back to a previous version of the data if needed

All scripts that I provide to you rely on a shell script library of common functions:
- To log what the script is doing in a file (resp. extract data from the log)
- To report issues per mail
- To prevent a script from be executed twice concurrently and prevent a script to start if the NAS if about to sleep
The scripts rely on a common configuration file (config.sh) in which the email addresses, path to log files and tmp files... can be set


DESCRIPTION
===========

In my opinion, the scripts are well documented enough to be understood by anybody having shell script knowledge
The script usage (e.g. arguments that can be passed) as well as a detailed description of the functions is provided in the header of each script
I tried to develop the scripts to be as versatile as possible, so that most of the scripts accept various optional arguments (For sure they will nevertheless fit everyones needs...)

scrubPools.sh:
--------------

- Scrub all the zpools and report the results in a log file.
- Send a mail if an error is detected
- Typical scheduling: once a week

checkPools.sh:
--------------

- Checks the status of the pools and report the results in a log file.
- Send a mail if an error is detected
- Typical scheduling: every hour

checkTemps.sh: (Script provided by miGi and updated by fritz)
--------------

- Checks the temperature of each respective CPU / CPU core and of each respective drive and report the results in a log file.
- Send a mail if the CPU (resp. HDD) temperature threshold is reached
- Typical scheduling: every hour or more often

checkSpace.sh:
--------------

- Check there is enough space in the respective file systems (Threshold is configurable)
- Report the results in a log file.
- Send a mail if the space threshold is reached
- Typical scheduling: every day for the data pool
- Typical scheduling: every week for the backup pool

manageSnapshots.sh:
-------------------

- Create hourly/daily/weekly/monthly snapshots of a filesystem (and child filesystems) and keep a configurable number of them (i.e. delete the superfluous snapshots)
- Report the results in a log file.
- Send a mail if an error occurs
- This script was specially designed to work fine even if the NAS is NOT always ON. E.g. if the NAS is OFF when the next monthly snapshot should be created, the script will create it as soon as the NAS is back on.
- This script does only need to be scheduled every hour and it will take care of any type of snapshot (hourly/daily/...)

Note 1: In Services|CIFS/SMB|Share|Edit, set the parameter "Shadow Copy format" to "%Y%m%d_%H%M_autosnap_type%S" in order to make the snapshots visible in the windows shadow copy client

backupData.sh:
--------------

- Backup incrementally (using zfs send/receive) the content of a set of FS into another pool located in the same NAS box
- Report the results in a log file.
- Send a mail if an error occurs
- This script was designed to able to cope with the deletion of superfluous snapshots in the data pool (This may be issued by the manageSnapshots.sh script)
- Typical scheduling: once a week

manageAcpi.sh:
--------------

- Controls shutdown (S5) or sleep (S3) of the NAS based on various parameters
-- If no computer that may access the NAS is online during a certain time (based on the IP address)
-- If the curfew is reached!
- Prevent a shutdown / sleep during a configurable timeslot
- Prevent a shutdown / sleep to be issued when one of the above administrative tasks are running
- Report the results in a log file.
- Script to be started at NAS startup. Scripts runs as an endless loop

Note 1: Depending on your motherboard and on your BIOS settings, the script may or may not work on your NAS.

Note 2: This script requires static IP addresses (of course static DHCP is OK too) on your NAS and other any other computer.

Note 3: I use Wake on LAN to wake the NAS. The WOL paket is sent by my DD-WRT router automatically when one of my computers is online. The script to be executed on the router can be found attached.

acpiStats.sh:
-------------

- Compute the percentage of time the NAS spent in each respective ACPI state (S0/S3/S5)
- Compute the average power usage in watt (based on typical power usage in S0/S3/S5)
- Report the results in a log file.
- Send a mail if an error occurs
- Typical scheduling: once a week

Note 1: This script required manageAcpi.sh to be started when your NAS starts (indeed manageAcpi.sh generates a file (acpi.log) that is required by acpiStats.sh)

reportFromLogs.sh:
------------------

- Scripts aimed at generating a extract of all log files (the part that has been populated during the last week)
- This script is used in the "Status|Email Report" section of nas4free


INSTALL
=======

- Copy the files in a folder of your NAS(all scripts must be copied into the same folder)
- Create a tmp folder
- Create a log folder
- Update the config.sh file according to your needs (paths, email addresses...)
- Configure Cron (https://github.com/fritz-hh/scripts_NAS4Free/wiki/Scheduling)

Note 1: In case you use the embedded version, the folders mentionned above should be located on one of your data disks (you may create a dedicated ZFS filesystem for the scripts in your pool)

Note 2: There no dependencies to utilities that are not already included in NAS4Free (9.1.0.1 - Sandstorm (revision 531))

DISCLAIMER
==========

Of course, the scripts are provided without any warranty!
(I am nor a freeBSD expert nor a SW developper, but a simple user)

Do not hesitate to make me aware of any bug!
(I will try to post regurlarly the updates that I will do in the scripts)

Feel free to use the scripts on your own NAS!

Kind Regards,

fritz
