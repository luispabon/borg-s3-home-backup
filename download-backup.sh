#!/usr/bin/env bash

bold=$(tput bold)
normal=$(tput sgr0)
accent=$(tput setaf 99)
secondary_accent=$(tput setaf 12)

DOWNLOAD_FOLDER=$1
if [[ ! "$DOWNLOAD_FOLDER" ]]; then
  SCRIPT=$(basename "$0")
  printf "\n ** Please provide the folder we're downloading your backup files into. The folder must exist and be empty.\n"
  printf "\n Example: ${SCRIPT} ./backup-restore /path/to/folder\n\n"
  exit 1
fi

if [[ ! -d "$DOWNLOAD_FOLDER" ]]; then
  printf "\n ** The folder ${DOWNLOAD_FOLDER} does not exist. Please create.\n\n"
  exit 1
fi

if [ "$(ls -A $DOWNLOAD_FOLDER)" ]; then
  printf "\n ** The folder ${DOWNLOAD_FOLDER} is not empty.\n\n"
  exit 1
fi

DOWNLOAD_FOLDER_AVAILABLE=$(df -B1 ${DOWNLOAD_FOLDER} | tail -1 | awk '{print $4}')

printf "${bold}Computing bucket size...${normal}\n\n"

# Google and AWS require different sync commands
if [[ "$BORG_S3_BACKUP_GOOGLE" == "true" ]]; then
  CLOUD_SERVICE_NAME="Google Cloud Storage"
  BUCKET_URI="gs://${BORG_S3_BACKUP_BUCKET}"
  BUCKET_SIZE=`gsutil du -s ${BUCKET_URI} | awk '{print \$1}'`
  DOWNLOAD_COMMAND="gsutil -m rsync -r ${BUCKET_URI} ${DOWNLOAD_FOLDER}"
else
  if [[ ! "$BORG_S3_BACKUP_AWS_PROFILE" ]]; then
    printf "\n ** Please provide with BORG_S3_BACKUP_AWS_PROFILE on the environment (awscli profile)\n"
    exit 1
  fi

  CLOUD_SERVICE_NAME="AWS S3"
  NOW=$(date +%s)

  BUCKET_URI="s3://${BORG_S3_BACKUP_BUCKET}"
  BUCKET_SIZE=`aws s3 ls --profile=${BORG_S3_BACKUP_AWS_PROFILE} --summarize --recursive ${BUCKET_URI} | tail -1 | awk '{print \$3}'`
  DOWNLOAD_COMMAND="aws s3 sync ${BUCKET_URI} ${DOWNLOAD_FOLDER} --profile=${BORG_S3_BACKUP_AWS_PROFILE}"
fi

BUCKET_SIZE_GB=`numfmt --to iec --format "%8.4f" ${BUCKET_SIZE}`
DOWNLOAD_FOLDER_AVAILABLE_GB=`numfmt --to iec --format "%8.4f" ${DOWNLOAD_FOLDER_AVAILABLE}`
echo "${bold}Cloud service:${normal} ${accent}${CLOUD_SERVICE_NAME}${normal}"
echo "${bold}Bucket size:${normal} ${accent}${BUCKET_SIZE_GB}${normal}"
echo "${bold}Available space at ${secondary_accent}${DOWNLOAD_FOLDER}:${normal} ${accent}${DOWNLOAD_FOLDER_AVAILABLE_GB}${normal}"

if (( $BUCKET_SIZE > $DOWNLOAD_FOLDER_AVAILABLE )); then
  printf "\n ** There is not enough space to download your backup at ${secondary_accent}${DOWNLOAD_FOLDER}${normal}\n"

  exit 1
fi

printf "\n${bold}Starting download: ${secondary_accent}${BUCKET_URI} ${accent}--> ${secondary_accent}${DOWNLOAD_FOLDER}${normal}\n\n"

$DOWNLOAD_COMMAND

printf "\n\n${bold}Backup download success.\nSummary${normal}:\n\n"
echo "${bold}Cloud service:${normal} ${accent}${CLOUD_SERVICE_NAME}${normal}"
echo "${bold}Bucket size:${normal} ${accent}${BUCKET_SIZE_GB}${normal}"
printf "\n\n${bold}Before you can use it with borg, you need to move ${secondary_accent}${DOWNLOAD_FOLDER} ${normal}${bold}to ${secondary_accent}${BORG_REPO}${normal}\n\n"
