# Borg s3/gcloud storage home backup

## What

This is a script to backup your home folder using borg into a local borg repository which is synced
into an AWS S3 or Google Cloud Storage bucket.

## Introduction

Having enough of overcomplicated or crappy commercial backup tools for Linux, I wrote this script to
back up my home folder into s3 on a cron schedule using borg backup:

  * Borg is quick, saves a great deal of space compared to traditional incremental backup solutions
  * s3 and gcloud storage are both cheap compared to commercial backup solutions, and also reliable
  * And cron is always easy to get going on linux

This script will backup your home folder using borg. The backup will be both compressed and encrypted.
Since borg does not natively support these cloud storage solutions, and the fuse/mount solutions are
slow as heck. We'll be using the rsync-like capabilities of the cli tools for each cloud provider,
which actually work pretty well.

This also prunes your backups to keep 7 dailies and 4 end-of-weeks.

The side effect however is you'll have two backups, one wherever borg has its backup repo, and another
on the bucket. This is good though, always a good idea to keep several backups even if one is on the same
computer.

## Compatibility

  * Linux for sure.
  * MacOS likely.
  * Linux on Windows 10, long shot.

## Requirements

### Tools

  * [Borg backup.](https://www.borgbackup.org/) - your distro will probably have this on its repos
  * The cloud provider's cli tool: either `awscli` or `gsutil` (part of `google-cloud-sdk`). Same as above.
  * A bucket

### Environment variables

These are borg-standard, as per [borg's documentation](https://borgbackup.readthedocs.io/en/stable/usage.html#environment-variables):

  * **BORG_REPO** (mandatory): location where all your backups will go into as they're made (NOT s3).
  Whereas borg supports ssh paths here as well as any mounted folder (eg s3 via fuse), I would recommend
  this to be a local folder on a real drive, if you can afford the space, for speed.
  * **BORG_PASSPHRASE** (optional, recommended): borg will encrypt your backups using this passphrase. You should.
  Make sure you keep this somewhere safe, other than your backup as you'll also need it to restore your files.

These are required by the script to function:

  * **BORG_S3_BACKUP_GOOGLE**: set to `true` if you want to use gcloud storage instead of AWS
  * **BORG_S3_BACKUP_BUCKET** (for both cloud providers): put in here the bucket name only. The naming with the `s3`
        word is a backwards compatibility measure from when this script supported AWS s3 only.
  * **BORG_S3_BACKUP_AWS_PROFILE** (s3 only): put in here the aws cli profile that has access to that bucket (eg `default`).

## How to use

  * Git clone this repo somewhere in your computer.
  * Copy [excludes.txt.dist](excludes.txt.dist) into `excludes.txt` and check its contents. The file is
  mandatory, but it can be empty. Have a look at
  [borg's documentation on the subject of excludes](https://borgbackup.readthedocs.io/en/stable/usage/help.html#borg-help-patterns) for more info.
  [excludes.txt.dist](excludes.txt.dist) has a few examples, indeed these are for my specific use case. If not a regular expression, paths must be
  absolute.
  * Install borg backup according to your platform. Possibly already on your distro's software repositories.
  * For S3:
      * Install `awscli`. Possibly on your distro's repos already.
      * Generate programmatic credentials
      * Configure aws cli with these credentials, eg `aws configure`.
  * For Gcloud Storage:
      * [Install gsutil](https://cloud.google.com/storage/docs/gsutil_install). Comes with the `google-cloud-sdk`.
      * [Authenticate with the `gcloud` tool](https://cloud.google.com/storage/docs/authentication)
  * Make yourself a bucket in your cloud provider.
  * Give full access to the bucket the account you're authenticating the cli tool with.
  * Set up the environment variables discussed above (eg on your `~/.profile`). I do recommend you also set `BORG_PASSPHRASE`.
  * Create a borg repo. Eg: `borg init -e repokey-blake2` - see [borg quickstart guide](https://borgbackup.readthedocs.io/en/stable/quickstart.html) and [borg init docs](https://borgbackup.readthedocs.io/en/stable/usage/init.html) for more info
  * Run [borg-backup.sh](borg-backup.sh)!

### Cron

By default, cron won't load any environment as it runs - make sure you source the file holding your environment
variables before running the script!.

Example crontab (assuming you added your environment variables into `~/.profile` that runs the backup every
working weekday at 17:30, on low priority, piping the output into a log file in your home folder overwritting any
previous logs:

```cron
30 17 * * MON-FRI . $HOME/.profile && nice -n19 $HOME/Projects/borg-s3-home-backup/borg-backup.sh > $HOME/backup.log 2>&1
```

#### Failed backups

Sometimes borg will report a failed backup. In my experience, this is typically due to files owned by another user.
I for instance work a lot with docker and sometimes files owned by root are created in my home folder. You can
set up a crontab for your root user to fix this:

```shell script
~ sudo crontab -e
```

then add

```cron
28 17 * * MON-FRI nice -n19 /usr/bin/find /home/YOURUSERNAME \! -user YOURUSERNAME -print | /usr/bin/xargs /usr/bin/chown YOURUSERNAME:YOURUSERNAME -Rf
```

Quadruple-check the folder `find` is searching on. You don't want to be running this in `/` by accident.

Make sure this cronjob is run (and has time to finish) before the cronjob that backs up your files.

### Note: borg backup locking

We lock the borg backup repository during aws s3 sync to ensure it doesn't change during uploads. Borg achieves locks using lock files within the repo,
therefore these files will also be backed up to s3 during sync. If you ever need to download your backup from s3 it will thus be locked and will need
unlocking with `borg break-lock`.

## Restoring backups

We provide with a script to download your backup from the cloud provider. It has the same requirements for env vars as the
backup script:

```shell script
~ ./download-backup.sh /path/to/folder
```

Then move that folder to the expected location of your borg repo.

If your borg repo is not present on your computer, you can of course simply:

```shell script
~ ./download-backup.sh $BORG_REPO
```

After the backup is present at `$BORG_REPO`:
  * CD into the folder and run `borg break-lock` to unlock your backup repo. See [note above](#note-borg-backup-locking)
        for explanation on why your backup is locked.
  * `borg list` will show you available backups
  * CD into some folder then `borg extract ::backup-name`. This will extract your backup to the current folder. See
        [borg's documentation](https://borgbackup.readthedocs.io/en/stable/usage.html#borg-extract) for more info.
  * Move extracted files where they're meant to be.

Example for a typical desktop computer - total restore of your home folder:
  * Make an administrative user whichever way you'd like, make sure they can `sudo` (for instance, on ubuntu
  they must be on the `adm` group). You'll be using this user to restore your data. Do this even if your user
  is already sudo-able to avoid issues when running the commands below.
  * Log out of your desktop back to the log in screen.
  * `CTRL+ALT+F1` to switch to tty1.
  * Log in as said user.

Then:

```bash
# Move your current home folder out of the way
cd /home
mv $HOME $HOME-old

# Make yourself a new one belonging to you
sudo mkdir $HOME
sudo chown $(whoami):$(getent group $(whoami) | awk 'BEGIN { FS = ":" } ; { print $1 }') $HOME

# Work out available backups and extract!
borg list
home-2022-10-05T17.30          Weds, 2022-10-05 17:30:36 [1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef]
home-2022-10-06T17.30          Thu, 2022-10-06 17:30:36  [1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef]

cd /
borg extract ::home-2022-10-05T17.30
reboot
```
