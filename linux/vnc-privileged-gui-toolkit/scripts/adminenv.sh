#!/usr/bin/env bash
set -u

LOGIN_USER="$(id -un)"
DISPLAY_VNC="${DISPLAY:-}"
USER_UID="$(id -u)"
STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/${USER_UID}}"
STATE_FILE="${STATE_DIR}/adminenv.current"
LOCK_FILE="${STATE_DIR}/adminenv.lock"
XHOST_USER=""

mkdir -p "$STATE_DIR"

exec 9>"$LOCK_FILE" || exit 1
if ! /usr/bin/flock -n 9; then
    echo "Administration menu already open."
    sleep 2
    exit 0
fi

set_current_env() {
    printf '%s\n' "$1" > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

has_group() {
    local group="$1"
    id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -Fxq "$group"
}

allow_graphical_display() {
    local target_user="$1"
    XHOST_USER=""
    [[ -z "$DISPLAY_VNC" ]] && return 0
    command -v xhost >/dev/null 2>&1 || return 0
    if xhost "+SI:localuser:${target_user}" >/dev/null 2>&1; then
        XHOST_USER="$target_user"
    fi
}

revoke_graphical_display() {
    if [[ -n "$XHOST_USER" ]] && [[ -n "$DISPLAY_VNC" ]]; then
        xhost "-SI:localuser:${XHOST_USER}" >/dev/null 2>&1 || true
    fi
    XHOST_USER=""
}

open_root_shell() {
    has_group linux-admins || { echo "Access denied."; sleep 2; return; }
    set_current_env root
    sudo -u root -H env -u DISPLAY -u XAUTHORITY /bin/bash -l 9>&-
    set_current_env personal
}

open_oracle_shell() {
    has_group oracle-admins || { echo "Access denied."; sleep 2; return; }
    allow_graphical_display oracle
    set_current_env oracle
    if [[ -n "$DISPLAY_VNC" ]]; then
        sudo -u oracle -H env DISPLAY="$DISPLAY_VNC" /bin/bash -l 9>&-
    else
        sudo -u oracle -H /bin/bash -l 9>&-
    fi
    set_current_env personal
    revoke_graphical_display
}

open_grid_shell() {
    has_group grid-admins || { echo "Access denied."; sleep 2; return; }
    allow_graphical_display grid
    set_current_env grid
    if [[ -n "$DISPLAY_VNC" ]]; then
        sudo -u grid -H env DISPLAY="$DISPLAY_VNC" /bin/bash -l 9>&-
    else
        sudo -u grid -H /bin/bash -l 9>&-
    fi
    set_current_env personal
    revoke_graphical_display
}

cleanup() {
    set_current_env personal
    revoke_graphical_display
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
set_current_env personal

while true; do
    clear
    echo "==========================================="
    echo "       PRIVILEGED ENVIRONMENT MENU"
    echo "==========================================="
    echo "1) root"
    echo "2) oracle"
    echo "3) grid"
    echo "0) exit"
    read -r -p "Choice: " choice
    case "$choice" in
        1) open_root_shell ;;
        2) open_oracle_shell ;;
        3) open_grid_shell ;;
        0) exit 0 ;;
        *) echo "Invalid choice"; sleep 1 ;;
    esac
done
