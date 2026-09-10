# Installation

## Prerequisites

Typical packages:

```bash
dnf install -y tigervnc-server gnome-terminal nautilus gedit dbus-x11 xorg-x11-xauth
```

Check:

```bash
command -v gnome-terminal
command -v nautilus
command -v gedit
command -v dbus-run-session
command -v xhost
command -v flock
```

## Groups

```bash
groupadd -f linux-admins
groupadd -f oracle-admins
groupadd -f grid-admins
```

Add a nominative account as appropriate:

```bash
usermod -aG linux-admins,oracle-admins,grid-admins adminuser
```

## Sudo

Adapt `config/sudoers-admin-groups.example` and validate with:

```bash
visudo -c
```

## TigerVNC

Adapt `config/vncserver.users.example` to your environment.

## Install scripts and launchers

```bash
sudo ./scripts/install.sh adminuser
```

Inside the graphical session, mark the desktop launchers as trusted if required by the desktop environment:

```bash
gio set ~/Desktop/Menu-Administration.desktop metadata::trusted true
gio set ~/Desktop/Files-Administration.desktop metadata::trusted true
gio set ~/Desktop/Text-Editor-Administration.desktop metadata::trusted true
```

## Validate

```bash
bash -n /usr/local/bin/adminenv
bash -n /usr/local/bin/open-files-current
bash -n /usr/local/bin/open-editor-current
visudo -c
```
