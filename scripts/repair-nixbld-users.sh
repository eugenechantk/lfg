#!/usr/bin/env bash
# Repair the Nix build-users group after a macOS update on Darwin.
#
# Symptom:
#     error: the user '_nixbld1' in the group 'nixbld' does not exist
# which blocks `nix build`, `home-manager switch`, and `reload-home-manager`.
#
# Root cause on this machine: a macOS update DELETED _nixbld1.._nixbld8 and
# REASSIGNED their UIDs (301-308) to Apple's own system daemons (e.g. UID 301 is
# now _modelmanagerd). The nixbld group still lists _nixbld1..8 as members, so
# Nix fails resolving them. The surviving build users _nixbld9.._nixbld32 (24 of
# them) are untouched and plenty for builds.
#
# Fix (minimal, no UID collisions): drop the 8 dangling names from the nixbld
# group, and delete any partial/orphaned _nixbld1..8 records (a previous repair
# attempt may have created a UID-less _nixbld1). We do NOT recreate them, because
# their old UIDs now belong to real macOS daemons.
#
# Run with sudo:  sudo bash scripts/repair-nixbld-users.sh
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root: sudo bash $0" >&2
  exit 1
fi

for i in $(seq 1 8); do
  u="_nixbld$i"
  # Remove from the group's name-based membership (the list Nix reads).
  dscl . -delete /Groups/nixbld GroupMembership "$u" 2>/dev/null \
    && echo "removed $u from nixbld GroupMembership" \
    || echo "$u not in GroupMembership (ok)"
  # Delete any orphaned/partial user record left behind.
  if dscl . -read "/Users/$u" >/dev/null 2>&1; then
    dscl . -delete "/Users/$u" 2>/dev/null \
      && echo "deleted orphaned user record $u" \
      || echo "could not delete $u record"
  fi
done

echo
echo "Remaining nixbld members:"
dscl . -read /Groups/nixbld GroupMembership

echo
echo "Restarting nix-daemon..."
launchctl kickstart -k system/org.nixos.nix-daemon 2>/dev/null \
  && echo "daemon restarted" \
  || echo "(could not kick the daemon; a reboot also works)"

echo
echo "Done. Test with:  nix --extra-experimental-features 'nix-command flakes' store ping"
