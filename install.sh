#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
install.sh — install `makeboot` into a bin directory on your PATH

Usage:
  ./install.sh [--prefix <dir>]
  ./install.sh --help

Defaults:
  If `~/.oh_my_bash/bin` (or `$OH_MY_BASH/bin`) exists, installs there.
  Otherwise installs to: "$HOME/.local/bin"

Examples:
  ./install.sh
  ./install.sh --prefix /usr/local/bin   # may prompt for sudo
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

OH_MY_BASH_DIR="${OH_MY_BASH:-$HOME/.oh_my_bash}"
if [[ -d "$OH_MY_BASH_DIR" ]]; then
  PREFIX="$OH_MY_BASH_DIR/bin"
else
  PREFIX="${HOME}/.local/bin"
fi
if [[ "${1:-}" == "--prefix" ]]; then
  [[ -n "${2:-}" ]] || { echo "Error: --prefix requires a value" >&2; exit 2; }
  PREFIX="$2"
  shift 2
fi

if [ $# -ne 0 ]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/makeboot"
DEST="$PREFIX/makeboot"

[ -f "$SRC" ] || { echo "Error: missing $SRC" >&2; exit 1; }

if mkdir -p "$PREFIX" 2>/dev/null; then
  install -m 0755 "$SRC" "$DEST" 2>/dev/null || {
    cp -f "$SRC" "$DEST"
    chmod +x "$DEST"
  }
  echo "Installed: $DEST"
  exit 0
fi

command -v sudo >/dev/null 2>&1 || { echo "Error: sudo not found (needed to install into $PREFIX)" >&2; exit 1; }
sudo mkdir -p "$PREFIX"
sudo install -m 0755 "$SRC" "$DEST" 2>/dev/null || {
  sudo cp -f "$SRC" "$DEST"
  sudo chmod +x "$DEST"
}
echo "Installed: $DEST"
