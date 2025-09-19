#!/usr/bin/env bash
set -euo pipefail

# ─── helpers ────────────────────────────────────────────────────────────────
abort()  { echo "Error: $1" >&2; exit 1; }
need()   { command -v "$1" >/dev/null 2>&1 || abort "$1 not found"; }

spinner() {                    # activity indicator with colored progress bar
  local pid=$1 delay=0.1
  local -a spin_chars=('=' '▒' '░' '▒')
  local -a fill_chars=('#' '▇' '█')
  local -a empty_chars=('-' '·' ' ')
  local -a accent_chars=('=' '▒' '░')
  local frame=0 progress=0 max_bar=20
  local reset='' spinner_color='' fill_color='' empty_color='' percent_color='' accent_color=''

  if [ -t 1 ]; then
    reset=$'\033[0m'
    spinner_color=$'\033[36m'   # cyan
    fill_color=$'\033[32m'      # green
    empty_color=$'\033[90m'     # bright black / grey
    percent_color=$'\033[33m'   # yellow
    accent_color=$'\033[35m'    # magenta
  fi

  printf '\r'
  while kill -0 "$pid" 2>/dev/null; do
    local spinner_char=${spin_chars[$((frame % ${#spin_chars[@]}))]}
    if (( progress < 99 )); then
      progress=$((progress + 1))
    fi
    local filled=$((progress * max_bar / 100))
    local empty=$((max_bar - filled))
    local fill_char=${fill_chars[$((frame % ${#fill_chars[@]}))]}
    local empty_char=${empty_chars[$((frame % ${#empty_chars[@]}))]}
    local accent_char=${accent_chars[$((frame % ${#accent_chars[@]}))]}

    local bar_fill=''
    for ((i = 0; i < filled; i++)); do
      bar_fill+="$fill_char"
    done

    local bar_empty=''
    if (( empty > 1 )); then
      for ((i = 0; i < empty - 1; i++)); do
        bar_empty+="$empty_char"
      done
    fi

    local bar=''
    bar+="${fill_color}${bar_fill}${reset}"
    if (( empty > 0 )); then
      bar+="${accent_color}${accent_char}${reset}"
      if (( empty > 1 )); then
        bar+="${empty_color}${bar_empty}${reset}"
      fi
    fi
    printf '\r[%s%s%s][%s] %s%3d%%%s' \
      "$spinner_color" "$spinner_char" "$reset" \
      "$bar" \
      "$percent_color" "$progress" "$reset"
    frame=$((frame + 1))
    sleep "$delay"
  done

  progress=100
  local final_fill=''
  for ((i = 0; i < max_bar; i++)); do
    final_fill+="${fill_chars[${#fill_chars[@]}-1]}"
  done
  local bar="${fill_color}${final_fill}${reset}"
  local spinner_char=${spin_chars[$((frame % ${#spin_chars[@]}))]}
  printf '\r[%s%s%s][%s] %s%3d%%%s\n' \
    "$spinner_color" "$spinner_char" "$reset" \
    "$bar" \
    "$percent_color" "$progress" "$reset"
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

TARGET_DISK=""
TARGET_RAW=""

need hdiutil; need diskutil; need dd

# ─── gather external disks without mapfile/readarray ───────────────────────
echo "Detecting removable drives..."
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
TARGET_DISK=$(printf '%s\n' "${DISK_LINES[$CHOICE]}" | awk '{print $1}' | sed 's#/dev/##')
TARGET_RAW="/dev/r$TARGET_DISK"
[ -n "$TARGET_DISK" ] || abort "Failed to resolve disk identifier."

echo "WARNING: All data on $TARGET_DISK will be destroyed!"
read -rp "Type YES to continue: " ok; [ "$ok" = YES ] || abort "Aborted."

# ─── convert ISO if needed ─────────────────────────────────────────────────
IMG_BASE="${ISO%.*}.img"
IMG="$IMG_BASE"
IMG_DMG="$IMG_BASE.dmg"

if [[ -f "$IMG_DMG" ]]; then
  echo "Image already exists: $IMG_DMG (skipping conversion)"
  IMG="$IMG_DMG"
elif [[ -f "$IMG_BASE" ]]; then
  echo "Image already exists: $IMG_BASE (skipping conversion)"
else
  echo "Converting ISO -> IMG..."
  hdiutil convert -format UDRW -o "$IMG_BASE" "$ISO" >/dev/null
  [[ -f "$IMG_DMG" ]] && IMG="$IMG_DMG"
fi

# ─── unmount, flash, eject ────────────────────────────────────────────────
echo "Unmounting /dev/${TARGET_DISK}..."; diskutil unmountDisk "/dev/$TARGET_DISK"
echo "Writing image to $TARGET_RAW..."
flash "$IMG" "$TARGET_RAW"
sync
diskutil eject "/dev/$TARGET_DISK"
echo "✅ Done!"
