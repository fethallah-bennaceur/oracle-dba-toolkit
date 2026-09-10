# Linux VNC Privileged GUI Toolkit

[Version française](README_FR.md)

A generic administration toolkit for Linux systems where an administrator connects with a nominative account and then switches to technical identities such as `root`, `oracle` or `grid`.

The project demonstrates:

- nominative SSH/VNC access;
- controlled privilege switching with `sudo`;
- a shared session context (`personal`, `root`, `oracle`, `grid`);
- a `flock`-based menu lock;
- GNOME autostart and desktop launchers;
- controlled X11 authorization with `xhost +SI:localuser`;
- isolated graphical sessions with `dbus-run-session`;
- graphical applications launched under the currently selected technical identity.

> Public portfolio version. It contains no organization names, internal hostnames, IP addresses, credentials, password rules, infrastructure inventories, or business-specific information.

## Architecture

### SSH

```text
Admin workstation
      |
      | nominative account + SSH key
      v
Linux server
      |
      | sudo
      +--> root
      +--> oracle
      +--> grid
```

### VNC

```text
Admin workstation
      |
      | nominative VNC session
      v
GNOME session
      |
      v
adminenv
  |
  +--> root
  +--> oracle
  +--> grid
  |
  +--> adminenv.current
  +--> adminenv.lock
              |
      +-------+-------+
      |               |
 Files launcher   Editor launcher
      |               |
      +--> sudo + X11 + D-Bus
```

## Session state

The selected context is written to:

```text
${XDG_RUNTIME_DIR}/adminenv.current
```

Possible values are `personal`, `root`, `oracle`, and `grid`. Graphical launchers read this state before starting an application.

## Menu locking

`adminenv` prevents concurrent menus with `flock`:

```bash
exec 9>"$LOCK_FILE"
flock -n 9
```

Child login shells explicitly close file descriptor 9 with `9>&-`, preventing a technical shell from keeping the menu lock alive.

## Privileged GUI execution

The graphical launchers grant X11 access only to the selected local account and create an isolated D-Bus session:

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

## Module structure

```text
vnc-privileged-gui-toolkit/
├── README.md
├── README_FR.md
├── architecture.md
├── installation.md
├── troubleshooting.md
├── config/
│   ├── sudoers-admin-groups.example
│   └── vncserver.users.example
├── desktop/
│   ├── adminenv-autostart.desktop
│   ├── files-administration.desktop
│   ├── menu-administration.desktop
│   └── text-editor-administration.desktop
├── diagrams/
│   ├── components.mmd
│   ├── ssh-flow.mmd
│   └── vnc-flow.mmd
└── scripts/
    ├── adminenv.sh
    ├── install.sh
    ├── open-editor-current.sh
    ├── open-files-current.sh
    └── start-adminenv.sh
```

## Quick start

```bash
git clone <repository-url>
cd oracle-dba-toolkit/linux/vnc-privileged-gui-toolkit
sudo ./scripts/install.sh adminuser
```

See [installation.md](installation.md).

## Documentation

- [Architecture](architecture.md)
- [Installation](installation.md)
- [Troubleshooting](troubleshooting.md)

## Disclaimer

This project is a generic technical reference. Review and adapt sudo, VNC, X11 and GNOME behavior before production use.
