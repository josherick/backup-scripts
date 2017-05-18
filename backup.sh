#!/bin/bash

# Fail the script if a command fails.
# Note there are certain situations which set -e does not work, so be careful
# when adding new commands.
set -e
set -o pipefail

###############################################################################
############# CHECK THIS SECTION BEFORE RUNNING ON A NEW MACHINE ##############
###############################################################################

# There must be a matching exclusions file in the same directory as this file
# named rsync-exclusions.${PLATFORM}.txt
PLATFORM="mac"

# The location of the drive to backup to.
DRIVE="/Volumes/Nemo 4TB RAID 1"

# The root location of what you want to back up.
ORIGINAL_DIR="/"

# Hostname of this computer, used to identify its backups from other machines.
HOSTNAME=`hostname`

# Set to false if the script shouldn't prompt for confirmation before running.
ASK_FOR_CONFIRMATION="true"

# Set to true to run rsync as the superuser using sudo.
RUN_AS_SUPERUSER="false"

# Set to true if you'd like rsync to do a dry-run instead of a real backup.
DRY_RUN="false"

###############################################################################
########### ^ CHECK THIS SECTION BEFORE RUNNING ON A NEW MACHINE ^ ############
###############################################################################

# Must have rsync>=3.1.0
if [ -f /usr/local/bin/rsync ]; then
	RSYNC="/usr/local/bin/rsync" # homebrew
elif [ -f /user/bin/rsync ]; then
	RSYNC="/usr/bin/rsync"
else
	echo "\$RSYNC should be set to rsync>=3.1.0"
	exit 1
fi

# Parse rsync version.
RSYNC_VER="`$RSYNC --version | \
head -1 | \
gsed \"s/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\).*$/\1/\"`"
RSYNC_MAJOR_VER="`echo $RSYNC_VER | cut -c 1`"
RSYNC_MINOR_VER="`echo $RSYNC_VER | cut -c 3`"
if [ "$RSYNC_MAJOR_VER" -lt "3" ] || [ "$RSYNC_MINOR_VER" -lt "1" ]; then
	echo "$RSYNC is version $RSYNC_VER, must be rsync>=3.1.0"
	exit 1
fi



# Must have GNU sed
if [ -f /usr/local/bin/gsed ]; then
	SED="/usr/local/bin/gsed" # homebrew
elif [ -f /usr/bin/sed ]; then
	SED="/usr/bin/sed"
else
	echo "\$SED should be set to GNU sed"
	exit 1
fi

# Caffeinate if it's available.
if [ -f /usr/bin/caffeinate ]; then
	CAFFEINATE="/usr/bin/caffeinate -s"
else
	CAFFEINATE=""
fi

# sed --version fails on BSD sed.
if ! $SED --version > /dev/null 2> /dev/null ; then
	echo "Make sure you have GNU sed installed!"
	exit 1
fi


# Make sure exclude file exists.
EXCLUDE_FILE=`realpath rsync-exclusions.${PLATFORM}.txt`
if [ ! -f "$EXCLUDE_FILE" ]; then
	echo "You need an exclude file called \"$EXCLUDE_FILE\" in the same directory as this file."
	exit 1
fi

# Make sure exclude file exists.
if [ "$RUN_AS_SUPERUSER" = "true" ]; then
	SUDO="sudo "
else
	SUDO=""
fi

# Define some formatting.
BOLD=`tput bold`
GREEN=`tput setaf 2`
NORMAL=`tput sgr0`

# The location of this hostname's backup directory.
BACKUP_DIR="$DRIVE/rsync-backups/$HOSTNAME"

LOG="$BACKUP_DIR/backup.log"


if [ -f "$BACKUP_DIR/current" ]; then
	PREVIOUS=`cat "$BACKUP_DIR/current"`
	INCREMENTS_DIR="$BACKUP_DIR/increments/$PREVIOUS"
fi


if [ "$ASK_FOR_CONFIRMATION" = "true" ]; then
	# Make sure that the user knows where we're backing up from and to.
	echo "Backup from directory:          $BOLD$ORIGINAL_DIR$NORMAL"
	echo "Backup to drive:                $BOLD$DRIVE$NORMAL"
	echo "Backup with hostname:           $BOLD$HOSTNAME$NORMAL"
	echo "Backup platform (for excludes): $BOLD$PLATFORM$NORMAL"
	echo ""
	if [ "$DRY_RUN" = "true" ]; then
		echo "${BOLD}Note:${NORMAL} This is a ${BOLD}dry-run${NORMAL}. \
In order to get rsync to run properly and not throw
errors, certain filenames passed to rsync will be the timestamp of the most
recent backup rather than timestamp that this backup would have. This is to
avoid touching your files at all."
		echo ""
	fi
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

# Define a unique date string to identify this backup.
DATE=`date +%F_%H.%M.%S.%Z`

# Create directory our log should be in if it doesn't exist.
if [ ! -e "`dirname \"$LOG\"`" ] && [ ! "$DRY_RUN" = "true" ]; then
	mkdir -p "`dirname \"$LOG\"`"
	eval $COMMAND
fi

# Suffix the old log file with "old" if it exists and this isn't a dry-run.
DIRNAME="`dirname \"$LOG\"`"
BASENAME="`basename \"$LOG\"`"
OLD_LOG="${DIRNAME}/${BASENAME}.old"
if [ -f "$LOG" ] && [ ! "$DRY_RUN" = "true" ]; then
	mv "$LOG" "$OLD_LOG"
fi

# Log start time.
if [ ! "$DRY_RUN" = "true" ]; then
	echo "BEGIN $DATE" >> "$LOG"
fi


echo ""

if [ -f "$BACKUP_DIR/current" ]; then
	MESSAGE="Creating a space for this backup and for increments from the previous backup..."
	print_and_log "$MESSAGE"

	# Rename the previous backup folder to be the current backup.
	COMMAND="mv \"$BACKUP_DIR/$PREVIOUS\" \"$BACKUP_DIR/$DATE\""
	print_and_execute "$COMMAND"

	# Create a space for the backup we are overwriting.
	COMMAND="mkdir \"$INCREMENTS_DIR\""
	print_and_execute "$COMMAND"

	# Move the old log to this incremental folder.
	COMMAND="mv \"$OLD_LOG\" \"$INCREMENTS_DIR/backup.log\""
	print_and_execute "$COMMAND"

	# Create a space the actual files that are overwritten by this backup.
	INCREMENTS_DIR=$INCREMENTS_DIR/changes
	COMMAND="mkdir \"$INCREMENTS_DIR\""
	print_and_execute "$COMMAND"
else
	MESSAGE="Creating backup directory and setting it to the current backup..."
	print_and_log "$MESSAGE"

	# Create backup directory if it doesn't exist.
	COMMAND="mkdir -p \"$BACKUP_DIR/$DATE\""
	print_and_execute "$COMMAND"

	# Create increments directory if it doesn't exist.
	COMMAND="mkdir -p \"$BACKUP_DIR/increments\""
	print_and_execute "$COMMAND"

	# This shouldn't be used since this is our first backup, but we'll create
	# it just in case.
	INCREMENTS_DIR=$BACKUP_DIR/increments

	JUST_CREATED="true"
fi

# Set the new current backup.
COMMAND="echo $DATE > \"$BACKUP_DIR/current\""
print_and_execute "$COMMAND"

# The directory to actually put the files we're backing up.
CURRENT_BACKUP_DIR="$DRIVE/rsync-backups/$HOSTNAME/$DATE"


# rsync is going to delete any files that are present in the destination that
# are no longer present in the source.

# Make a copy of them first so they aren't deleted, unless this is the first
# sync.

if [ ! "$JUST_CREATED" = "true" ]; then
	print_and_log ""
	MESSAGE="Copying files that will be pruned by rsync to increments directory..."
	print_and_log "$MESSAGE"

	RSYNC_OPTIONS="--archive \
		--xattrs \
		--hard-links \
		--update \
		--dry-run \
		--verbose \
		--delete \
		--exclude-from=\"$EXCLUDE_FILE\""

	# Pipe rsync dry-run to sed, filtering lines down to only the relative paths
	# of the files that will be deleted, then copy each file individually with it's
	# relative path into the increments directory.
	if [ ! "$DRY_RUN" = "true" ]; then
		COPY_TO=$CURRENT_BACKUP_DIR
	else
		COPY_TO=$BACKUP_DIR/$PREVIOUS
	fi

	# We want to evaluate cd whether this is a dry-run or not.
	# Running cd in a bash script won't change anything outside, and it is
	# necessary for the following rsync commands to work properly.
	COMMAND="cd \"$COPY_TO\""
	if [ ! "$DRY_RUN" = "true" ]; then
		# Evaluate and log.
		echo $ $GREEN$COMMAND$NORMAL
		echo $ $COMMAND >> "$LOG"
		eval $COMMAND 2> >(tee -a "$LOG" >&2)
	else
		# Evaluate without any logging.
		echo $ ${GREEN}cd $CURRENT_BACKUP_DIR$NORMAL
		eval $COMMAND
	fi

	COMMAND="$SUDO$RSYNC $RSYNC_OPTIONS \"$ORIGINAL_DIR\" \"$COPY_TO\" | \
			$SED -n \"/^deleting /p\" | \
			$SED \"s/^deleting //g\""

	COPIED_FILES=0

	print_and_log_command "$COMMAND"
	while read -r RELATIVE_PATH; do
		RSYNC_OPTIONS="--archive --hard-links --xattrs --relative"
		COMMAND="$CAFFEINATE $SUDO$RSYNC $RSYNC_OPTIONS \"$RELATIVE_PATH\" \"$INCREMENTS_DIR\""
		if [ ! "$DRY_RUN" = "true" ]; then
			# Print (don't log, there could be lots of these!)
			echo $ $COMMAND >> "$LOG"
			eval $COMMAND 2> >(tee -a "$LOG" >&2)
		fi
		COPIED_FILES=$((COPIED_FILES + 1))
	done < <(eval $COMMAND 2> >(tee -a "$LOG" >&2))

	MESSAGE="Copied $COPIED_FILES files whose originals will be pruned in the next step."
	print_and_log "$MESSAGE"
fi


# Perform the actual rsync operation!
print_and_log ""
print_and_log "Starting rsync..."

RSYNC_OPTIONS="--archive \
	--xattrs \
	--hard-links \
	--update \
	--exclude-from=\"$EXCLUDE_FILE\" \
	--fuzzy \
	--delete-after \
	--backup \
	--info=progress2 \
	--backup-dir=\"$INCREMENTS_DIR\""

if [ "$DRY_RUN" = "true" ]; then
	RSYNC_OPTIONS="$RSYNC_OPTIONS --dry-run --verbose"
	COPY_TO=$BACKUP_DIR/$PREVIOUS
else
	RSYNC_OPTIONS="$RSYNC_OPTIONS --log-file=\"$LOG\""
	COPY_TO=$CURRENT_BACKUP_DIR
fi

COMMAND="$CAFFEINATE $SUDO$RSYNC $RSYNC_OPTIONS \"$ORIGINAL_DIR\" \"$COPY_TO\""
print_and_execute "$COMMAND"

# Log end time.
if [ "$DRY_RUN" = "true" ]; then
	echo END `date +%F-%H%M%S%Z` >> "$LOG"
fi
