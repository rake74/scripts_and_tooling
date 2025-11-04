#!/bin/bash

myname=$(basename $0)
myname=${myname%.sh}  # Strip .sh extension if present.
mydir=$(dirname $0)
mypid=$$
mystamp="${myname}[${mypid}]"

#
# Configuration
# Edit in place here or use conf files, see 'Custom configuration files' below.
#
mnt_dir='/mnt'
backup_dir='/backupdir'
source_host='smb_server_name_here'
shares=(
  'cat_videos'
  'memes'
  'epstein_files'
)
rsync_opts=(
  '--archive'
  '--itemize-changes'
  '--partial'
  '--stats'
  '--dry-run'
)
# Delete (--delete) is not included above on purpose. Test with --dry-run first.
cifs_mount_creds_file='/your/secure/smb/credentials/file'
cifs_mount_opts="credentials=${cifs_mount_creds_file},uid=0,gid=0,vers=3.0"
lock_file="/var/lock/backup-dnasbox.lock"

#
# Output functions and vars
#
dateme() { TZ=UTC date +'%FT%H%M.%SZ'; }

pretty_out() {
  while IFS= read -r L ; do
    grep '^\s*$' <<<"$L" && continue
    $timestamp       && echo -n "$(dateme) "
    [ -n "$prefix" ] && echo -n "${prefix} "
    echo -e "$L"
  done
}

# Attempt to identify if being ran by process/timestamping
# automation.
if [ "${1:-}" == 'automated' ]; then
  Global_timestamp=false
  Global_prefix=''
else
  Global_timestamp=true
  Global_prefix=$mystamp
fi

#
# Custom configuration files
#

# Only place we do this, so we can set vars and keep them.
confs_loaded=()
for F in "/etc/${myname}.conf" "${mydir}/${myname}.conf" ; do
  if [ -e "$F" ] ; then
    confs_loaded+=( "Found '$F', loading...")
    source "$F"
  fi
done
prefix=${Global_prefix} timestamp=${Global_timestamp} pretty_out < <(
  printf "%s\n" "${confs_loaded[@]}"
)

#
# Task functions
#
mount_cifs(){
  local share="${1:-}"
  [ -z "$share" ] && return 1
  echo "Mounting //${source_host}/${share}..."
  mount -t cifs "//${source_host}/${share}" "${mnt_dir}/${share}" -o "${cifs_mount_opts}" 2>&1
}

rsync_from_mnt(){
  local share="${1:-}"
  [ -z "$share" ] && return 1
  echo "Rsyncing ${share}..."
  rsync "${rsync_opts[@]}" "${mnt_dir}/${share}/" "${backup_dir}/${share}/" 2>&1
}

cleanup() {
  (
    echo 'Ensuring all share mounts unounted'
    # Loop through shares and unmount any that are currently mounted.
    for share in "${shares[@]}"; do
      if mountpoint -q "${mnt_dir}/${share}"; then
        echo "Unmounting ${mnt_dir}/${share}..."
        umount "${mnt_dir}/${share}" 2>&1 \
        || echo "ERROR: Failed to unmount '${mnt_dir}/${share}'. It may be busy."
      fi
    done
  ) | prefix=${Global_prefix} timestamp=${Global_timestamp} pretty_out
}

#
# Obtain lock before proceding.
#
# Use flock for safe concurrent execution. The script will wait up to 5 seconds.
exec 9>"$lock_file"
if flock -n 9; then
  echo "Obtained lock via lock file '${lock_file}'."
else
  echo "Failed to obtain locak via lock file '${lock_file}'. Exiting."
  exit 1
fi | prefix=${Global_prefix} timestamp=${Global_timestamp} pretty_out

# Set a trap to run the cleanup function on any script exit.
trap cleanup EXIT

backup_share(){
  set -o pipefail
  local retcode=0
  ( echo 'Ensuring mount and desination dirs exist'
    mkdir -p "${mnt_dir}/${share}" "${backup_dir}/${share}" 2>&1 || exit 1
  ) | prefix='task:mkdirs' pretty_out || return 1

  ( if ! mount_cifs "$share" ; then
      echo "ERROR: Failed to mount ${share}. Skipping."
      exit 1
    fi
  ) | prefix='task:mount' pretty_out || return 1

  ( rsync_from_mnt "$share" \
    || echo "ERROR: rsync failed for ${share} with exit code $?. Continuing to unmount."
  ) | prefix='task:rsync' pretty_out || retcode=1

  ( echo "Unmounting '${mnt_dir}/${share}'"
    umount "${mnt_dir}/${share}" \
    || echo "ERROR: Failed to unmount '${mnt_dir}/${share}'. It may be busy."
  ) | prefix='task:umount' pretty_out
  return $retcode
}

(
  echo 'Starting backup job.'

  timestamp=false
  for share in "${shares[@]}" ; do
    backup_share | prefix="share:${share}" pretty_out
  done

  echo 'Backup job finished.'
) | prefix=${Global_prefix} timestamp=${Global_timestamp} pretty_out
