# Architecture

## Objective

Use a nominative administrative identity for the initial SSH/VNC connection, then switch to `root`, `oracle` or `grid` according to group-based `sudo` authorization.

## Session context

The menu stores the current context in:

```text
${XDG_RUNTIME_DIR}/adminenv.current
```

Possible values:

```text
personal
root
oracle
grid
```

Graphical launchers read this value before starting an application.

## Locking

The menu uses:

```bash
exec 9>"$LOCK_FILE"
flock -n 9
```

The presence of the file does not mean the lock is active. The open file descriptor holds the lock.

Child login shells explicitly close descriptor 9 with:

```bash
9>&-
```

so they cannot keep the menu locked after it closes.

## Privileged GUI path

```text
selected context
      |
      v
xhost +SI:localuser:<target>
      |
      v
sudo -u <target>
      |
      v
dbus-run-session
      |
      v
graphical application
```
