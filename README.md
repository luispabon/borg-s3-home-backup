# Borg s3 home backup

## Introduction

Having enough of overcomplicated or crappy commercial backup tools for Linux, I wrote this script to
back up my home folder into s3 on a cron schedule using borg backup:

  * Borg is quick, saves a great deal of space compared to traditional incremental backup solutions
  * s3 is cheap compared to commercial backup solutions, and also reliable
  * And cron is always easy to get going on linux

This script will backup your home folder using borg. The backup will be both compressed and encrypted.
Since borg does not natively support s3, and the fuse/mount solution is slow as heck, we're using aws
sync instead at the end. This actually works pretty well.

This also prunes your backups to keep 7 dailys and 4 end-of-weeks.

The side effect however is you'll have two backups, one wherever borg has its backup repo, and another
on s3. This is good though, always a good idea to keep several backups even if one is on the same
computer.

## Compatibility

  * Linux for sure.
  * MacOS likely.
  * Linux on Windows 10, long shot.

## Requirements

### Tools

  * [Borg backup.](https://www.borgbackup.org/)
  * awscli - you must configure a profile with aws access key and secret for use on the command line.
  * An s3 bucket the above profile has access to.

### Environment variables

These are borg-standard, as per [borg's documentation](https://borgbackup.readthedocs.io/en/stable/usage.html#environment-variables):

  * **BORG_REPO** (mandatory): location where all your backups will go into as they're made (NOT s3).
  Whereas borg supports ssh paths here as well as any mounted folder (eg s3 via fuse), I would recommend
  this to be a local folder on a real drive, if you can afford the space, for speed.
  * **BORG_PASSPHRASE** (optional, recommended): borg will encrypt your backups using this passphrase. You should.
  Make sure you keep this somewhere safe, other than your backup as you'll also need it to restore your files.

These are required by the script to function:

  * **BORG_S3_BACKUP_BUCKET**: put in here the bucket name only.
  * **BORG_S3_BACKUP_AWS_PROFILE**: put in here the aws cli profile that has access to that bucket (eg `default`).

## How to use

  * Git clone this repo somewhere in your computer.
  * Copy [excludes.txt.dist](excludes.txt.dist) into `excludes.txt` and check its contents. The file is
  mandatory, but it can be empty. Have a look at
  [borg's documentation on the subject of excludes](https://borgbackup.readthedocs.io/en/stable/usage.html#borg-help-patterns) for more info.
  [excludes.txt.dist](excludes.txt.dist) has a few examples, indeed these are for my specific use case. If not a regular expression, paths must be
  absolute.
  * Install borg backup according to your platform. Possibly already on your distro's software repositories.
  * Install awscli - same as above.
  * AWS setup:
    * You obviously need an account in there.
    * You must have access keys and secrets for it.
    * Configure aws cli with these credentials, eg `aws configure`.
    * Make yourself a bucket in your aws account.
  * Set up the environment variables discussed above (eg on your `~/.profile`). I do recommend you also set `BORG_PASSPHRASE`.
  * Create a borg repo: `borg init`
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

## Restoring backups

There's no script here to restore your backups, you'll have to use borg for that. See [borg's documentation](https://borgbackup.readthedocs.io/en/stable/usage.html#borg-extract). Generally:

  * Make sure the environment variables above are all set.
  * Download from s3 all your backup files into the location at $BORG_REPO (if you don't have your local borg repo).
  * `borg list` will show you available backups
  * CD into some folder then `borg extract ::backup-name`, should extract on that same folder.
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
mv myusername myusername-old

# Make yourself a new one belonging to you
sudo mkdir myusername
sudo chown myusername:myusername myusername

# Work out available backups and extract!
borg list
cd /
borg extract ::whichever-backup-you-need-maybe-latest
reboot
```
