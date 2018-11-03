RELEASE NOTES
=============

Please always read this file before installing the package

Download software here: https://github.com/fritz-hh/scripts_NAS4Free/tags

v2.2 (2018-11-03):
====

New features
------------

- None 

Changes
-------

- None

Fixes
-----

- backupData.sh: (closes #21) Fix a bug that leads the backupData.sh script to set the whole destination pool to 
  read only a the end of the backup.
  This is not a good idea if at least 1 filesystem of the destination pool is used for other purposes than backup.
  Now the script puts the zpool to readonly at the end of the script, only if it was readonly, when the script started.

Tested with
-----------

- Xigmanas (formerly NAS4Free) 11.2.0.4 - Omnius (revision 6005)

v2.1 (2018-11-03):
====

New features
------------

- checkPools.sh and scrubPools.sh: In case of pool error, provide
  a more verbose status message in the log, so that it is possible to located the
  impacted files. 

Changes
-------

- None

Fixes
-----

- None

Tested with
-----------

- Xigmanas (formerly NAS4Free) 11.2.0.4 - Omnius (revision 6005)


v2.0 (2015-01-27):
====

New features
------------

- backupData.sh: support for lz4 compression algorithm

Changes
-------

- None

Fixes
-----

- manageSnapshots.sh: (fixes #23) Correct wrong behaviour in case zfs property listsnaps=ON
- Log messages improved

Tested with
-----------

- NAS4Free  	9.2.0.1 - Shigawire (revision 972) - Embedded

v2.0-beta1 (2013-03-25):
====

New features
------------

- backupData.sh: support of remote backup through ssh
- backupData.sh: check that the pool of the destination filesystem is different from the pool of each source filesystem
- backupData.sh: (closes #19) new option -c to set compression for the destination filesystems
- manageAcpi.sh: (closes #7) new switch -s to prevent shutdown in case of active ssh connection to the server
- manageSnapshots.sh: new switch -r to process recursively the filesystems at a given depth

Changes
-------

- backupData.sh: (closes #8) allow any zfs fs as detination of the backup (not only a pool) (e.g. not only "backup_pool" but also "backup_pool/abc" are now supported)
- manageAcpi.sh: signature of -n switch changed (before [-n beg,end,acpi,delay,ips], after [-n ips,delay,acpi])
- reportFromLogs.sh: mention package version in report

Fixes
-----

- None

Tested with
-----------

- NAS4Free 9.1.0.1 - Sandstorm (revision 531) - Embedded

v1.0 (2013-03-12):
====

New features
------------

- None

Changes
-------

- None

Fixes
-----

- checkSpace.sh: (fixes #18): Minor fix regarding quota of volumes that may equal to the character: "-"

Tested with
-----------

- NAS4Free 9.1.0.1 - Sandstorm (revision 531) - Embedded

v1.0-rc4 (2013-03-04):
========

New features
------------

- None

Changes
-------

- backupData.sh: compression algorithm of destination pool changed from "gzip" to "lzjb"

Fixes
-----

- backupData.sh: (fixes #13) supports any snapshots names (even if they do not follow naming convention used by manageSnapshot.sh)
- commonLockFcts.sh: (affects all scripts) (fixes #14) lock acquisition now atomic to prevent that the same lock is acquired more once in case 2 scripts try to acquire the same lock at the same time
- checkSpace.sh and manageSnapshots.sh: (fixes #17) The script now supports providing as argument an fs name that contains more than one "/" (e.g.: "tank/data/user1")
- manageSnapshots.sh: Fixes a bug that occurs when the script is called with many arguments
- manageAcpi.sh: Ensure that "prevent sleep after wake" is never smaller than 300s (otherwise the server may always shutdown just after booting if other parameters are set incorrectly)

Tested with
-----------

- NAS4Free 9.1.0.1 - Sandstorm (revision 531) - Embedded

v1.0-rc3 (2013-02-22):
========

New features
------------

- None

Changes
-------

- config.sh: layout changed to segregate the variables that can be used by the users from the other variables

Fixes
-----

- All scripts: Fix #9 (script can now be called from any directory)
- manageSnapshots.sh: Fix #10 and #11 (corrects an erroneous argument check for switches -h -d -w and -m)
- backupData.sh: Correct syntax error preventing the script to run (bug introduced in v1.0-rc2)
- commonLockFcts.sh: robustness improved
- commonLogFcts.sh: robustness against bad log file name/path improved, and increased verbosity if error is detected

Tested with
-----------

- NAS4Free 9.1.0.1 - Sandstorm (revision 531) - Embedded

v1.0-rc2 (2013-02-19):
========

New features
------------

- None

Changes
-------

- reportFromLogs.sh / manageAcpi.sh: Format of the report / log slighty improved
- backupData.sh: logged data slightly improved

Fixes
-----

- backupData.sh: fixed major bug in test if the destination fs already exists (bug introduced in v1.0-rc1. It did not exist before)
- .gitattributes: config updated to ensure that files checked out follow unix new line convention (LF)

Tested with
-----------

- NAS4Free 9.1.0.1 - Sandstorm (revision 531) - Embedded

v1.0-rc1 (2013-02-17): (1st version managed on github)
========

New features
------------

- reportFromLogs.sh: Generate a summary for each log file (number of arnings/errors)

Changes
-------

- improved readability of data logged (display as tables whenever possible: e.g.: for checkSpace.sh)
- checkSpace.sh: arguments "filesystem" and "threshold" are now optional (-f and -t)
- backupData.sh: argument "max_rollback" is now optional (-b) 
- commonLockFcts.sh (impact on all scripts): Do not warn if a script cannot be started because the NAS is about to shut down (normal information message instead)
- library of funtions moved to subfolder "common"
- config.sh: default path to "log" and "tmp" folder changed

Fixes
-----

- all scripts: improved validation of mandatory and optional arguments
- commonLogFcts.sh: leading spaces of message now also logged if data are provided through a pipe
- commonLogFcts.sh: When logging, if no log file path is provided, echo text on std out instead
- commonLogFcts.sh: When returning a log file extract: Handle case of empty file 

Tested with
-----------

- NAS4Free 9.1.0.1 - Sandstorm (revision 531) - Embedded
