# Troubleshooting

## Menu reports that it is already open

```bash
LOCK_FILE="${XDG_RUNTIME_DIR}/adminenv.lock"
fuser -v "$LOCK_FILE"
```

The file itself may remain after the process exits; `flock` is tied to the open descriptor.

## Graphical application does not open

Check:

```bash
echo "$DISPLAY"
command -v xhost
command -v dbus-run-session
```

Verify that the selected technical account exists and that the requested `sudo` transition is allowed.

## Application opens under the nominative user

Some desktop applications reuse an existing D-Bus process. The launchers isolate the target identity with:

```text
DBUS_SESSION_BUS_ADDRESS=
dbus-run-session
```

## Duplicate login profile execution

Use one login-shell mechanism only. For example:

```bash
sudo -u oracle -H /bin/bash -l
```
