# Linux VNC Privileged GUI Toolkit

[English version](README.md)

Ce mini-projet présente une architecture d’administration Linux permettant à un administrateur de se connecter avec **son compte nominatif**, puis de basculer vers les identités techniques `root`, `oracle` ou `grid` en fonction de ses habilitations.

L’objectif principal est d’étendre cette logique aux sessions graphiques VNC : une application telle que Nautilus ou Gedit peut être lancée sous l’identité technique actuellement sélectionnée, sans ouvrir une session graphique séparée pour chaque compte technique.

> Version publique et générique : aucun nom d’entreprise, hostname interne, adresse IP, mot de passe, formule de mot de passe, inventaire ou donnée métier n’est présent dans ce dépôt.

## Fonctionnalités

Le projet met en œuvre :

- connexion initiale avec un compte nominatif ;
- bascule contrôlée avec `sudo` vers `root`, `oracle` ou `grid` ;
- session VNC/GNOME nominative ;
- menu d’administration `adminenv` ;
- contrôle des habilitations par groupes Linux ;
- fichier d’état partagé `adminenv.current` ;
- verrou non bloquant avec `flock` via `adminenv.lock` ;
- fermeture du descripteur de verrou dans les shells enfants avec `9>&-` ;
- autorisation X11 ciblée avec `xhost +SI:localuser:<user>` ;
- session D-Bus isolée avec `dbus-run-session` ;
- lancement de Nautilus ou Gedit sous le compte technique sélectionné ;
- confirmation explicite avant un lancement graphique sous `root` ;
- raccourcis GNOME et démarrage automatique du menu.

## Architecture SSH

```text
Poste administrateur
        |
        | compte nominatif + clé SSH
        v
Serveur Linux
        |
        | sudo
        +------> root
        +------> oracle
        +------> grid
```

Exemples :

```bash
sudo -i
sudo -iu oracle
sudo -iu grid
```

## Architecture VNC

```text
Poste administrateur
        |
        | session VNC nominative
        v
Session GNOME
        |
        v
adminenv
   |
   +------> root
   +------> oracle
   +------> grid
   |
   +------> adminenv.current
   +------> adminenv.lock
                  |
          +-------+-------+
          |               |
       Nautilus          Gedit
          |               |
          +------ sudo + X11 + D-Bus
```

## Gestion du contexte graphique

Le menu écrit l’environnement courant dans :

```text
${XDG_RUNTIME_DIR}/adminenv.current
```

Valeurs possibles :

```text
personal
root
oracle
grid
```

Les lanceurs graphiques lisent cette valeur avant de démarrer l’application.

Exemple de chaîne d’exécution :

```text
adminenv.current = oracle
        |
        v
open-files-current
        |
        +--> xhost +SI:localuser:oracle
        +--> sudo -u oracle
        +--> dbus-run-session
        |
        v
Nautilus exécuté sous oracle
```

## Verrouillage du menu

`adminenv` utilise un verrou `flock` afin d’éviter plusieurs menus simultanés dans la même session :

```bash
exec 9>"$LOCK_FILE"
flock -n 9
```

La présence physique du fichier `adminenv.lock` ne signifie pas que le menu est verrouillé. Le verrou réel est détenu par le descripteur ouvert.

Les shells enfants ferment explicitement ce descripteur :

```bash
9>&-
```

Cela évite qu’un shell `root`, `oracle` ou `grid` conserve le verrou après la fermeture du menu principal.

## Applications graphiques privilégiées

L’autorisation X11 est limitée au compte local cible :

```bash
xhost +SI:localuser:${TARGET_USER}
```

Puis l’application est exécutée dans une session D-Bus distincte :

```bash
sudo -u "$TARGET_USER" -H \
  env DISPLAY="$DISPLAY" \
      XDG_RUNTIME_DIR="$RUNTIME_DIR" \
      DBUS_SESSION_BUS_ADDRESS= \
  dbus-run-session -- \
  /usr/bin/nautilus --new-window
```

L’autorisation X11 est retirée à la fermeture de l’application.

## Structure du module

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

## Installation rapide

```bash
git clone <repository-url>
cd oracle-dba-toolkit/linux/vnc-privileged-gui-toolkit
sudo ./scripts/install.sh adminuser
```

Voir [installation.md](installation.md) pour les prérequis et la configuration des groupes et de `sudo`.

## Points techniques intéressants

Ce projet illustre plusieurs sujets souvent rencontrés en administration Linux/Oracle :

- séparation entre identité de connexion et identité technique ;
- comportement des applications GNOME avec D-Bus ;
- partage d’un contexte entre un terminal et des raccourcis graphiques ;
- autorisations X11 ciblées ;
- gestion de concurrence avec `flock` ;
- héritage des descripteurs de fichiers ;
- exécution graphique sous une autre identité Unix ;
- intégration de scripts Bash dans une session GNOME/VNC.

## Avertissement

Ce projet constitue une base technique générique. Les règles `sudo`, les groupes, le serveur VNC et les applications graphiques doivent être adaptés et validés avant utilisation sur un environnement de production.
