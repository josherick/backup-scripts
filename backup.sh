#!/bin/bash

###############################################################################
############# CHECK THIS SECTION BEFORE RUNNING ON A NEW MACHINE ##############
###############################################################################

# There must be a matching exclusions file in the same directory as this file
# named rsync-exclusions.${PLATFORM}.txt
PLATFORM="mac"

# The location of the drive to backup to, without a trailing slash.
#DRIVE="/Volumes/Nemo 4TB RAID 1"
DRIVE="/Users/joshsherick/backup_test/drive"

# The root location of what you want to back up.
# A trailing slash indicates that the contents of the directory should be
# backed up, which is probably what you want.
#ORIGINAL_DIR="/"
ORIGINAL_DIR="/Users/joshsherick/backup_test/fs/"

# Hostname of this computer, used to identify its backups from other machines.
HOSTNAME=`hostname`

# Set to true to run rsync as the superuser using sudo.
RUN_AS_SUPERUSER="false"

# Set to false if the script shouldn't prompt for confirmation before running.
ASK_FOR_CONFIRMATION="true"

# Set to true if you'd like rsync to do a dry-run instead of a real backup.
DRY_RUN="false"

###############################################################################
########### ^ CHECK THIS SECTION BEFORE RUNNING ON A NEW MACHINE ^ ############
###############################################################################

# Fail the script if a command fails.
# Note there are certain situations which set -e does not work, so be careful
# when adding new commands.
set -e
set -o pipefail

# Must have GNU sed
if [ -f /usr/local/bin/gsed ]; then
	SED="/usr/local/bin/gsed" # homebrew
elif [ -f /usr/bin/sed ]; then
	SED="/usr/bin/sed"
else
	echo "\$SED should be set to GNU sed"
	exit 1
fi

# sed --version fails on BSD sed.
if ! $SED --version > /dev/null 2> /dev/null ; then
	echo "Make sure you have GNU sed installed!"
	exit 1
fi

# Must have GNU split
if [ -f /usr/local/bin/gsplit ]; then
	SPLIT="/usr/local/bin/gsplit" # homebrew
elif [ -f /usr/bin/split ]; then
	SPLIT="/usr/bin/split"
else
	echo "\$SPLIT should be set to GNU split"
	exit 1
fi

# split --version fails on BSD split.
if ! $SPLIT --version > /dev/null 2> /dev/null ; then
	echo "Make sure you have GNU split installed!"
	exit 1
fi

# Must have rsync>=3.1.0
if [ -f /usr/local/bin/rsync ]; then
	RSYNC="/usr/local/bin/rsync" # homebrew
elif [ -f /usr/bin/rsync ]; then
	RSYNC="/usr/bin/rsync"
else
	echo "\$RSYNC should be set to rsync>=3.1.0"
	exit 1
fi

# Parse rsync version.
RSYNC_VER="`$RSYNC --version | \
head -1 | \
$SED \"s/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\).*$/\1/\"`"
RSYNC_MAJOR_VER="`echo $RSYNC_VER | cut -c 1`"
RSYNC_MINOR_VER="`echo $RSYNC_VER | cut -c 3`"
if [ "$RSYNC_MAJOR_VER" -lt "3" ] || [ "$RSYNC_MINOR_VER" -lt "1" ]; then
	echo "$RSYNC is version $RSYNC_VER, must be rsync>=3.1.0"
	exit 1
fi

# Make sure exclude file exists.
EXCLUDE_FILE=`realpath rsync-exclusions.${PLATFORM}.txt`
if [ ! -f "$EXCLUDE_FILE" ]; then
	echo "You need an exclude file called \"$EXCLUDE_FILE\" in the same directory as this file."
	exit 1
fi

# Run as sudo if requested.
if [ "$RUN_AS_SUPERUSER" = "true" ]; then
	SUDO="sudo "
else
	SUDO=""
fi

# Define some formatting.
BOLD=`tput bold`
GREEN=`tput setaf 2`
RED=`tput setaf 1`
NORMAL=`tput sgr0`

# The location of this hostname's backup directory.
BACKUP_DIR="$DRIVE/rsync-backups/$HOSTNAME"

# Location of the log file (potentially an old log file, which we will move)
LOG="$BACKUP_DIR/backup.log"


# If there is a most recent backup, set variables accordingly.
if [ -f "$BACKUP_DIR/current" ]; then
	PREVIOUS=`cat "$BACKUP_DIR/current"`
	INCREMENTS_DIR="$BACKUP_DIR/increments/$PREVIOUS"
fi

# This is who rsync runs as.
if [ ! "$RUN_AS_SUPERUSER" = "true" ]; then
	RUN_AS="$BOLD`whoami`$NORMAL"
else
	RUN_AS="${RED}root${NORMAL}"
fi


# Make sure that the user knows where we're backing up from and to.
if [ "$ASK_FOR_CONFIRMATION" = "true" ]; then
	echo "Run as:                         $BOLD$RUN_AS$NORMAL"
	echo "Dry run:                        $BOLD$DRY_RUN$NORMAL"
	echo "Backup from directory:          $BOLD$ORIGINAL_DIR$NORMAL"
	echo "Backup to drive:                $BOLD$DRIVE$NORMAL"
	echo "Backup with hostname:           $BOLD$HOSTNAME$NORMAL"
	echo "Backup platform (for excludes): $BOLD$PLATFORM$NORMAL"
	echo ""

	if [ ! "$RUN_AS_SUPERUSER" = "true" ]; then
		echo "${BOLD}Note:${NORMAL} rsync will be run by ${BOLD}$RUN_AS${NORMAL} \
instead of the superuser. 
Some permissions may not be able to be preserved."
		echo ""
	fi

	if [ "$RUN_AS_SUPERUSER" = "true" ] && [ ! "$DRY_RUN" = "true" ]; then
		echo "${RED}WARNING:${NORMAL} rsync will be run by $BOLD$RUN_AS$NORMAL. \
Be careful when using this option, 
and consider doing a dry-run first to see what will be changed. Depending
on your sudo settings, you may not be prompted for a password."
		echo ""
	fi

	if [ "$DRY_RUN" = "true" ]; then
		echo "${BOLD}Note:${NORMAL} This is a ${BOLD}dry-run${NORMAL}. \
In order to get rsync to run properly and not throw
errors, certain filenames passed to rsync will be the timestamp of the most
recent backup rather than timestamp that this backup would have. This is to
avoid touching your files at all."
		echo ""
	fi

	# Pause to confirm.
	read -p "Confirm backup? [Y/n] " -n 1
	if [[ ! $REPLY =~ ^[Yy]$ ]] && [ ! -z $REPLY ]; then
		echo ""
		echo "Did not back up."
		exit 1
	fi
fi

# Define several functions to standardize printing, logging, and evaluating.
function print_and_log {
	echo $1
	if [ ! "$DRY_RUN" = "true" ]; then
		echo $1 >> "$LOG"
	fi
}

function print_and_log_command {
	echo $ $GREEN$1$NORMAL
	if [ ! "$DRY_RUN" = "true" ]; then
		echo $ $1 >> "$LOG"
	fi
}

function print_and_execute {
	print_and_log_command "$1"
	if [ ! "$DRY_RUN" = "true" ]; then
		eval $1 2> >(tee -a "$LOG" >&2)
	fi
}

function quote {
    local quoted=${1//\'/\'\\\'\'}
    printf "'%s'" "$quoted"
}

# Define a unique date string to identify this backup.
DATE=`date +%F_%H.%M.%S.%Z`


DIRNAME="`dirname \"$LOG\"`"
# Create directory our log should be in if it doesn't exist.
if [ ! -e "$DIRNAME" ]; then
	mkdir -p "$DIRNAME"
fi

# Suffix the old log file with "old" if it exists and this isn't a dry-run.
BASENAME="`basename \"$LOG\"`"
OLD_LOG="${DIRNAME}/${BASENAME}.old"
if [ -f "$LOG" ]; then
	mv "$LOG" "$OLD_LOG"
fi

# Log start time.
if [ ! "$DRY_RUN" = "true" ]; then
	echo "BEGIN $DATE" >> "$LOG"
fi


# Caffeinate if it's available.
echo ""
if [ -f /usr/bin/caffeinate ]; then
	MESSAGE="Ensuring the machine doesn't sleep until the script ends..."
	print_and_log "$MESSAGE"

	COMMAND="/usr/bin/caffeinate -dim -w $$ &"
	print_and_execute "$COMMAND"
else
	MESSAGE="You may want to take steps to ensure your machine doesn't sleep during this process!"
	print_and_log "$MESSAGE"
fi


# Move files and create directories to ensure we have a space for this backup.
echo ""
if [ -f "$BACKUP_DIR/current" ]; then
	MESSAGE="Creating a space for this backup and for increments from the previous backup..."
	print_and_log "$MESSAGE"

	# Rename the previous backup folder to be the current backup.
	COMMAND="mv $(quote "$BACKUP_DIR/$PREVIOUS") $(quote "$BACKUP_DIR/$DATE")"
	print_and_execute "$COMMAND"

	# Create a space for the backup we are overwriting.
	COMMAND="mkdir $(quote "$INCREMENTS_DIR")"
	print_and_execute "$COMMAND"

	# Move the old log to this incremental folder.
	COMMAND="mv $(quote "$OLD_LOG") $(quote "$INCREMENTS_DIR/backup.log")"
	print_and_execute "$COMMAND"

	# Create a space the actual files that are overwritten by this backup.
	CHANGES_DIR=$INCREMENTS_DIR/changes
	COMMAND="mkdir $(quote "$CHANGES_DIR")"
	print_and_execute "$COMMAND"
else
	MESSAGE="Creating backup directory and setting it to the current backup..."
	print_and_log "$MESSAGE"

	# Create backup directory if it doesn't exist.
	COMMAND="mkdir -p $(quote "$BACKUP_DIR/$DATE")"
	print_and_execute "$COMMAND"

	# Create increments directory if it doesn't exist.
	COMMAND="mkdir -p $(quote "$BACKUP_DIR/increments")"
	print_and_execute "$COMMAND"

	JUST_CREATED="true"
fi

# Set the new current backup.
COMMAND="echo $DATE > $(quote "$BACKUP_DIR/current")"
print_and_execute "$COMMAND"

# The directory to actually put the files we're backing up.
CURRENT_BACKUP_DIR="$DRIVE/rsync-backups/$HOSTNAME/$DATE"


# rsync is going to delete any files that are present in the destination that
# are no longer present in the source.

# Make a copy of them first so they aren't deleted, unless this is the first
# sync.
if [ ! "$JUST_CREATED" = "true" ]; then
	print_and_log ""
	MESSAGE="Calculating and making copies of files that will be pruned by rsync..."
	print_and_log "$MESSAGE"

	DELETION_SCRIPT=`realpath deletion-helper.sh`

	if [ ! "$DRY_RUN" = "true" ]; then
		COPY_TO=$CURRENT_BACKUP_DIR
	else
		COPY_TO=$BACKUP_DIR/$PREVIOUS
	fi

	# We want to evaluate cd whether this is a dry-run or not.
	# Running cd in a bash script won't change anything outside, and it is
	# necessary for the following rsync commands to work properly.
	COMMAND="cd $(quote "$COPY_TO")"
	if [ ! "$DRY_RUN" = "true" ]; then
		# Evaluate and log.
		echo $ $GREEN$COMMAND$NORMAL
		echo $ $COMMAND >> "$LOG"
		eval $COMMAND 2> >(tee -a "$LOG" >&2)
	else
		# Evaluate without any logging.
		echo "$ ${GREEN}cd $(quote "$CURRENT_BACKUP_DIR")$NORMAL"
		eval $COMMAND
	fi

	# We are going to store lists of the files that will be deleted in this
	# directory, 1000 files at a time.
	# This lets us speed up deletion significantly, since we can copy 1000 
	# files at a time rather than having to start and stop rsync for every 
	# file copy.
	# And, since we split the list into multiple files, we don't have to wait
	# for rsync to complete it's deleted file computation before starting to
	# copy files.
	DELETIONS_LIST_DIR=$INCREMENTS_DIR/deletions-list
	COMMAND="mkdir -p $(quote "$DELETIONS_LIST_DIR/comm")"
	print_and_execute "$COMMAND"

	# Invoke the deletion helper, which will exit when it's finished.
	COMMAND="$DELETION_SCRIPT \
$(quote "$DELETIONS_LIST_DIR") \
$(quote "$CURRENT_BACKUP_DIR") \
$(quote "$CHANGES_DIR") \
\"$RSYNC\" \
\"$RUN_AS_SUPERUSER\" \
\"$DRY_RUN\""

	echo $ $GREEN$COMMAND$NORMAL
	eval $COMMAND & >> "$LOG" 2>&1 | tee -a $LOG

	# Pipe rsync dry-run to sed, filtering lines down to only the relative
	# paths of the files that will be deleted, then copy each file individually
	# with it's relative path into the increments directory.
	RSYNC_OPTIONS="--archive \
		--xattrs \
		--hard-links \
		--update \
		--dry-run \
		--verbose \
		--delete \
		--exclude-from=$(quote "$EXCLUDE_FILE")"

	COMMAND="$SUDO$RSYNC $RSYNC_OPTIONS $(quote "$ORIGINAL_DIR") $(quote "$COPY_TO") | \
			$SED -n \"/^deleting /p\" | \
			$SED \"s/^deleting //g\" | \
			$SPLIT -d --suffix-length=7 - $(quote "$INCREMENTS_DIR/deletions-list/")"
	print_and_execute "$COMMAND"

	TOTAL_FILES="`find $DELETIONS_LIST_DIR -type f -maxdepth 1 | xargs cat | wc -l`"
	MESSAGE="Computation of files to be pruned resulted in $TOTAL_FILES files."
	print_and_log "$MESSAGE"
	
	# Wait until the deletion helper is done.
	while [ ! -f "$DELETIONS_LIST_DIR/comm/copy-finished" ] && [ ! "$DRY_RUN" = "true" ] ; do
		touch $DELETIONS_LIST_DIR/comm/computation-finished
		if [ -f "$DELETIONS_LIST_DIR/comm/copied-files" ]; then
			CURRENT_FILE_NUM="`cat \"$DELETIONS_LIST_DIR/comm/copied-files\"`"
			echo -en "\rCurrently copying $CURRENT_FILE_NUM of $TOTAL_FILES";
		fi
		sleep 1
	done

	COPIED_FILES="`cat \"$DELETIONS_LIST_DIR/comm/copied-files\"`"
	MESSAGE="Copied $COPIED_FILES files whose originals will be pruned in the next step."
	print_and_log "$MESSAGE"

	echo "Computation of $TOTAL_FILES files to be pruned finished."

	# The deletion helper is done.
	# Delete the deletions list directory.
	COMMAND="rm -r $(quote "$DELETIONS_LIST_DIR")"
	print_and_execute "$COMMAND"

fi


# Perform the actual rsync operation.
print_and_log ""
print_and_log "Starting rsync..."

RSYNC_OPTIONS="--archive \
	--xattrs \
	--hard-links \
	--update \
	--exclude-from=$(quote "$EXCLUDE_FILE") \
	--fuzzy \
	--delete-after \
	--backup \
	--info=progress2 \
	--backup-dir=$(quote "$CHANGES_DIR")"

# Dry-runs log to console, real runs log to log file.
if [ "$DRY_RUN" = "true" ]; then
	RSYNC_OPTIONS="$RSYNC_OPTIONS --dry-run --verbose"
	COPY_TO=$BACKUP_DIR/$PREVIOUS
else
	RSYNC_OPTIONS="$RSYNC_OPTIONS --log-file=$(quote "$LOG")"
	COPY_TO=$CURRENT_BACKUP_DIR
fi

COMMAND="$SUDO$RSYNC $RSYNC_OPTIONS $(quote "$ORIGINAL_DIR") $(quote "$COPY_TO")"
print_and_log_command "$COMMAND"
if [ ! "$DRY_RUN" = "true" ]; then
	# Evaluate and log.
	eval $COMMAND 2> >(tee -a "$LOG" >&2)
else
	# Evaluate without any logging.
	eval $COMMAND
fi

# Log end time.
if [ ! "$DRY_RUN" = "true" ]; then
	echo END `date +%F-%H%M%S%Z` >> "$LOG"
fi
