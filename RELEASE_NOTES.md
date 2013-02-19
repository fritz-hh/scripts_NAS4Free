RELEASE NOTES
=============

Please read always this file before installing the package

Download software here: https://github.com/fritz-hh/scripts_NAS4Free/tags

v1.0-rc2 (2013-02-19):
========

New features
------------

- None

Changes
-------

- reportForLogs.sh / manageAcpi.sh: Format of the report / log slighty improved
- backupData.sh: logged data slightly improved

Fixes
-----

- backupData.sh: fixed major bug in test if the destination fs already exists (bug introduced in v1.0-rc1. It did not exist before)
- .gitattributes: config updated to ensure that files checked out follow unix new line convention (LF)


v1.0-rc1 (2013-02-17): (1st version managed on github)
========

New features
------------

- reportFromLogs.sh: Generate a summary for each log file (number warnings/errors)
- improved readability of data logged (display in columns table data)

Changes
-------

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

