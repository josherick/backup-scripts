# backup-scripts
Bash script to backup with rsync

My problem with most backup solutions is that when you backup your files in an incremental fashion, the "incremental" versions are not actually backed up.
For example, suppose you create files A and B, back them up, then delete file A and perform another ("incremental") backup. 
File A now exists only on your backup drive, meaning it is not backed up, since that is your only copy of that file.

This script (which is a work in progress and comes with NO warranty) uses rsync to backup your filesystem to an external drive, so you always have a full copy of your filesystem in a single folder.
When it performs subsequent backups, it calculates which files have been changed or deleted and moves only those files to a separate "increments" directory (in a timestamped sub-directory), containing files and versto a different drive at your convenience so they once again exist on two separate drives.
Then, you can then easily copy the files in the "increments" directory to a different drive at your convenience so they once again exist on two separate drives.

The script is configured by editing `backup.sh` directly.
