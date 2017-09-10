#!/bin/bash

# Name to give this backup within the borg repo
BACKUP_NAME=home-$(date +%Y-%m-%dT%H.%M)

printf "\n\n ** Starting backup ${BACKUP_NAME} of home folder...\n"

# Check environment vars are set
if [[ ! "$BORG_REPO" ]]; then
	printf "\n ** Please provide with BORG_REPO on the environment\n"
	exit 1
fi

if [[ ! "$BORG_S3_BACKUP_BUCKET" ]]; then
	printf "\n ** Please provide with BORG_S3_BACKUP_BUCKET on the environment\n"
	exit 1
fi

if [[ ! "$BORG_S3_BACKUP_AWS_PROFILE" ]]; then
	printf "\n ** Please provide with BORG_S3_BACKUP_AWS_PROFILE on the environment (awscli profile)\n"
	exit 1
fi

EXCLUDES_FILE=$(dirname $0)/excludes.txt
if [ ! -f "${EXCLUDES_FILE}" ]; then
	printf "\n ** Please create an excludes file (even if empty) at '${EXCLUDES_FILE}'.\n"
	exit 1
fi

# Local borg backup, low priority
borg create ::${BACKUP_NAME} \
	${HOME} \
	-v \
	--stats \
	--list \
	--exclude-from ${EXCLUDES_FILE} \
	--compression zlib,6

# Define and store the backup's exit status
OPERATION_STATUS=$?

# Only continue if backup was actually successful
if [ $OPERATION_STATUS == 0 ]; then
	# Clean up old backups: keep 7 end of day and 4 additional end of week archives.
	# Prune operation is not important, s3 sunc is - do not exit were this to fail
	borg prune -v --list --keep-daily=7 --keep-weekly=4

	# Sync borg repo to s3, again low priority
	printf "\n\n ** Sync to s3...\n"
	aws s3 sync ${BORG_REPO} s3://${BORG_S3_BACKUP_BUCKET} --profile=${BORG_S3_BACKUP_PROFILE} --delete

	# We do care about s3 sync succeeding though
	OPERATION_STATUS=$?
fi

if [ $OPERATION_STATUS == 0 ]; then
	STATUS_MESSAGE="Backup successful"
else
	STATUS_MESSAGE="Backup failed because reasons - see output"
fi

# Send desktop notification and exit appropriately if supported by the system - this will probably
# work on a linux desktop
if hash notify-send 2>/dev/null; then
	if [ $OPERATION_STATUS == 0 ]; then
		notify-send -t 0 "Home folder backup" "${STATUS_MESSAGE}" --urgency=normal --icon=dialog-information
	else
		notify-send -t 0 "Home folder backup" "${STATUS_MESSAGE}" --urgency=critical --icon=dialog-error
	fi
fi

# Same as above, but on stdout
printf "\n ** ${STATUS_MESSAGE}\n"
exit ${OPERATION_STATUS}
