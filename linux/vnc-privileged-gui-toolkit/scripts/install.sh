#!/usr/bin/env bash
set -euo pipefail
ADMIN_USER="${1:-}"
[[ -n "$ADMIN_USER" ]] || { echo "Usage: sudo $0 <nominative_user>"; exit 1; }
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root."; exit 1; }
id "$ADMIN_USER" >/dev/null 2>&1 || { echo "User not found."; exit 1; }

ADMIN_HOME="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

install -o root -g root -m 0755 "$REPO_DIR/scripts/adminenv.sh" /usr/local/bin/adminenv
install -o root -g root -m 0755 "$REPO_DIR/scripts/start-adminenv.sh" /usr/local/bin/start-adminenv
install -o root -g root -m 0755 "$REPO_DIR/scripts/open-files-current.sh" /usr/local/bin/open-files-current
install -o root -g root -m 0755 "$REPO_DIR/scripts/open-editor-current.sh" /usr/local/bin/open-editor-current

install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0700 "$ADMIN_HOME/.config/autostart"
install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0755 "$ADMIN_HOME/Desktop"
install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0644 "$REPO_DIR/desktop/adminenv-autostart.desktop" "$ADMIN_HOME/.config/autostart/adminenv.desktop"
install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0755 "$REPO_DIR/desktop/menu-administration.desktop" "$ADMIN_HOME/Desktop/Menu-Administration.desktop"
install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0755 "$REPO_DIR/desktop/files-administration.desktop" "$ADMIN_HOME/Desktop/Files-Administration.desktop"
install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0755 "$REPO_DIR/desktop/text-editor-administration.desktop" "$ADMIN_HOME/Desktop/Text-Editor-Administration.desktop"

echo "Installation complete for $ADMIN_USER"
