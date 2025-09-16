#!/usr/bin/env bash
set -euo pipefail

# ─── helpers ────────────────────────────────────────────────────────────────
abort()  { echo "Error: $1" >&2; exit 1; }
need()   { command -v "$1" >/dev/null 2>&1 || abort "$1 not found"; }

spinner() {                    # simple activity indicator
  local pid=$1 delay=0.1 spin='|/-\'
  printf ' '
  while kill -0 "$pid" 2>/dev/null; do
    printf '\b%s' "${spin:i++%${#spin}:1}"
    sleep "$delay"
  done
  printf '\b'
}

flash() {                      # dd with status and spinner
  local img=$1 raw=$2
  if dd --help 2>&1 | grep -q 'status='; then
    dd if="$img" of="$raw" bs=4m status=progress &
  elif command -v pv >/dev/null; then
    pv "$img" | dd of="$raw" bs=4m &
  else
    dd if="$img" of="$raw" bs=4m &
  fi
  spinner $!
  wait $!
}

# ─── prerequisites ─────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || abort "Run with sudo"
[ $# -eq 1 ]         || abort "Usage: sudo $0 /path/to/linux.iso"
ISO=$1; [ -r "$ISO" ] || abort "Cannot read ISO: $ISO"

need hdiutil; need diskutil; need dd

# ─── gather external disks without mapfile/readarray ───────────────────────
echo "Detecting removable drives…"
DISK_LINES=()
while IFS= read -r line; do
  DISK_LINES+=( "$line" )
done < <(diskutil list external physical | grep '^/dev/disk')

[ ${#DISK_LINES[@]} -gt 0 ] || abort "No external physical disks found."

echo
for idx in "${!DISK_LINES[@]}"; do
  ident=$(printf '%s\n' "${DISK_LINES[$idx]}" | awk '{print $1}' | sed 's#/dev/##')
  size=$(diskutil info "$ident" | awk -F': *' '/Total Size/{print $2; exit}')
  printf '[%d] %s  –  %s\n' "$idx" "$ident" "$size"
done
echo

read -rp "Enter disk number to overwrite: " CHOICE
[[ "$CHOICE" =~ ^[0-9]+$ && "$CHOICE" -lt ${#DISK_LINES[@]} ]] || abort "Invalid index."
DISK=$(printf '%s\n' "${DISK_LINES[$CHOICE]}" | awk '{print $1}' | sed 's#/dev/##')
RAW="/dev/r$DISK"

echo "WARNING: All data on $DISK will be destroyed!"
read -rp "Type YES to continue: " ok; [ "$ok" = YES ] || abort "Aborted."

# ─── convert ISO if needed ─────────────────────────────────────────────────
IMG="${ISO%.*}.img"
if [[ ! -f "$IMG"* ]]; then
  echo "Converting ISO → IMG…"
  hdiutil convert -format UDRW -o "$IMG" "$ISO" >/dev/null
  [[ -f $IMG.dmg ]] && IMG=$IMG.dmg
fi

# ─── unmount, flash, eject ────────────────────────────────────────────────
echo "Unmounting /dev/$DISK…";  diskutil unmountDisk "/dev/$DISK"
echo "Writing image to $RAW (spinner shows activity)…"
flash "$IMG" "$RAW"
sync
diskutil eject "/dev/$DISK"
echo "✅ Done!"
