#!/usr/bin/env bash
set -euo pipefail

LOGIN_UID="$(id -u)"
STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/${LOGIN_UID}}"
STATE_FILE="${STATE_DIR}/adminenv.current"
DISPLAY_VNC="${DISPLAY:?DISPLAY is not set}"
CURRENT_ENV="$(cat "$STATE_FILE" 2>/dev/null || printf '%s\n' personal)"
FILES=("$@")

case "$CURRENT_ENV" in
    personal)
        if (( ${#FILES[@]} > 0 )); then
            exec /usr/bin/gedit --standalone "${FILES[@]}"
        else
            exec /usr/bin/gedit --standalone
        fi
        ;;
    root|oracle|grid) TARGET_USER="$CURRENT_ENV" ;;
    *) exec /usr/bin/gedit --standalone ;;
esac

if [[ "$TARGET_USER" == root ]]; then
    echo "Warning: editor will run as root."
    read -r -p "Type YES to continue: " CONFIRMATION
    [[ "$CONFIRMATION" == YES ]] || exit 1
fi

TARGET_UID="$(id -u "$TARGET_USER")"
xhost "+SI:localuser:${TARGET_USER}" >/dev/null
trap 'xhost "-SI:localuser:'"$TARGET_USER"'" >/dev/null 2>&1 || true' EXIT HUP INT TERM

RUNTIME_DIR="/run/user/${TARGET_UID}"
if [[ ! -d "$RUNTIME_DIR" ]]; then
    RUNTIME_DIR="/tmp/adminenv-runtime-${TARGET_USER}-${TARGET_UID}"
    sudo -u "$TARGET_USER" install -d -m 700 "$RUNTIME_DIR"
fi

if (( ${#FILES[@]} > 0 )); then
    sudo -u "$TARGET_USER" -H \
        env DISPLAY="$DISPLAY_VNC" XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS= \
        dbus-run-session -- /usr/bin/gedit --standalone "${FILES[@]}"
else
    sudo -u "$TARGET_USER" -H \
        env DISPLAY="$DISPLAY_VNC" XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS= \
        dbus-run-session -- /usr/bin/gedit --standalone
fi
