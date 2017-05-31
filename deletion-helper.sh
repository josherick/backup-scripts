#!/bin/bash

###############################################################################
###################### DO NOT RUN THIS SCRIPT DIRECTLY! #######################
###############################################################################

# DO NOT RUN THIS SCRIPT DIRECTLY!
# Unexpected behavior may occur.
# Instead, run ./backup.sh which will invoke this script when necessary.

###############################################################################
###################### DO NOT RUN THIS SCRIPT DIRECTLY! #######################
###############################################################################



# Fail the script if a command fails.
# Note there are certain situations which set -e does not work, so be careful
# when adding new commands.
set -e
set -o pipefail

DELETIONS_LIST_DIR=$1
DELETION_ROOT_DIR=$2
CHANGES_DIR=$3
RSYNC=$4
RUN_AS_SUPERUSER=$5

if [ ! -d "$DELETIONS_LIST_DIR" ]; then
	echo "Couldn't open the deletions list directory: $DELETIONS_LIST_DIR"
	exit 1
fi

if [ ! -d "$DELETION_ROOT_DIR" ]; then
	echo "Couldn't open the deletions list directory: $DELETIONS_LIST_DIR"
	exit 1
fi

if [ ! -d "$CHANGES_DIR" ]; then
	echo "Couldn't open the changes directory: $CHANGES_DIR"
	exit 1
fi

if [ "$RSYNC" = "" ]; then
	echo "\$RSYNC not specified"
	exit 1
fi

# Run as sudo if requested.
if [ "$RUN_AS_SUPERUSER" = "true" ]; then
	SUDO="sudo "
else
	SUDO=""
fi

COPIED_FILES=0

function quote {
    local quoted=${1//\'/\'\\\'\'}
    printf "'%s'" "$quoted"
}

function numf {
	printf "%07d" "$1"
}

function rsync_split {
	RSYNC_OPTIONS="--archive \
--hard-links \
--xattrs \
--relative \
--files-from=$(quote "$DELETIONS_LIST_DIR/$1")"
	COMMAND="$SUDO$RSYNC $RSYNC_OPTIONS $(quote "$DELETION_ROOT_DIR") $(quote "$CHANGES_DIR")"
	echo $ $COMMAND
	eval $COMMAND

	FILES="`wc -l $DELETIONS_LIST_DIR/$1`"
	COPIED_FILES=$((COPIED_FILES + FILES))
	echo "$COPIED_FILES" > "$DELETIONS_LIST_DIR/comm/copied-files"
}

CURRENT_SPLIT_NUM=0
NEXT_SPLIT_NUM=$((CURRENT_SPLIT_NUM + 1))
while true; do
	MAX_SPLIT_NUM="`ls $DELETIONS_LIST_DIR | sort -r | head -2 | tail -1`"

	# Check if we've copied everything
	if [ -f "$DELETIONS_LIST_DIR/comm/computation-finished" ] &&
		([[ $CURRENT_SPLIT_NUM -gt $MAX_SPLIT_NUM ]] ||
		 [ ! -f "$DELETIONS_LIST_DIR/$(numf "$CURRENT_SPLIT_NUM")" ]) ; then
		echo "$COPIED_FILES" > "$DELETIONS_LIST_DIR/comm/copied-files"
		touch $DELETIONS_LIST_DIR/comm/copy-finished
		exit 0
	fi
	
	# Sync the next split when it's available.
	if [ -f "$DELETIONS_LIST_DIR/$(numf "$NEXT_SPLIT_NUM")" ] || 
		([ -f "$DELETIONS_LIST_DIR/comm/computation-finished" ] &&
		 [ -f "$DELETIONS_LIST_DIR/$(numf "$CURRENT_SPLIT_NUM")" ]); then

		# rsync all of the files in this split.
		rsync_split "$(numf $CURRENT_SPLIT_NUM)"

		# Move onto the next split number.
		CURRENT_SPLIT_NUM=$((CURRENT_SPLIT_NUM + 1))
		NEXT_SPLIT_NUM=$((CURRENT_SPLIT_NUM + 1))
	else
		# We didn't find this split. Sleep for one second then continue.
		sleep 1
	fi

done
