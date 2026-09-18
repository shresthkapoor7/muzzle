#!/bin/zsh
set -euo pipefail
umask 077

if [[ "$EUID" != 0 || "$#" != 0 ]]; then
  echo 'Usage: sudo scripts/uninstall-helper.sh (end protection first)' >&2
  exit 1
fi
state_path='/Library/Application Support/MuzzleService/session.json'
if [[ -f "$state_path" ]]; then /usr/bin/plutil -lint "$state_path" >/dev/null; fi
if [[ -f "$state_path" ]] && /usr/bin/plutil -extract session json -o - "$state_path" >/dev/null 2>&1; then
  echo 'An active session is saved. End protection in Muzzle before uninstalling.' >&2
  exit 1
fi
if /usr/bin/grep -q '^# MUZZLE_BEGIN' /etc/hosts || [[ -e /etc/pf.anchors/muzzle ]]; then
  echo 'Blocking rules still exist. Let Muzzle finish clearing them before uninstalling.' >&2
  exit 1
fi
was_running=0
if /bin/launchctl print system/local.muzzle.helper >/dev/null 2>&1; then
  /bin/launchctl bootout system/local.muzzle.helper
  was_running=1
fi
# Recheck after stopping: a client could have started a session during the first check.
if { [[ -f "$state_path" ]] && /usr/bin/plutil -extract session json -o - "$state_path" >/dev/null 2>&1; } ||
   /usr/bin/grep -q '^# MUZZLE_BEGIN' /etc/hosts || [[ -e /etc/pf.anchors/muzzle ]]; then
  if [[ "$was_running" == 1 ]]; then /bin/launchctl bootstrap system /Library/LaunchDaemons/local.muzzle.helper.plist; fi
  echo 'Protection became active. Service retained; end protection before uninstalling.' >&2
  exit 1
fi
archive_path="$(/usr/bin/mktemp -d /private/var/tmp/muzzle-service-uninstall.XXXXXX)"
for service_file in /Library/LaunchDaemons/local.muzzle.helper.plist /Library/PrivilegedHelperTools/local.muzzle.helper; do
  if [[ -e "$service_file" ]]; then /bin/mv "$service_file" "$archive_path/"; fi
done
if [[ -d '/Library/Application Support/MuzzleService' ]]; then
  /bin/mv '/Library/Application Support/MuzzleService' "$archive_path/state"
fi
echo "Service uninstalled. Root-only backup: $archive_path"
