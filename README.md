# Oracle DBA Toolkit

Scripts, requêtes SQL et notes opérationnelles pour l’administration Oracle Database, Oracle RAC, RMAN, WebLogic et Linux.

Ce dépôt sert à centraliser des outils simples, documentés et réutilisables pour l’exploitation quotidienne d’environnements Oracle critiques.

---

## Auteur

**Fethallah Bennaceur**  
DBA Oracle Senior – Administrateur Systèmes Linux & Windows

Compétences principales :

- Oracle Database 10g / 11g / 12c / 19c
- Oracle RAC / Grid Infrastructure
- RMAN / sauvegarde / restauration
- Data Guard
- Performance Oracle : AWR, ASH, PGA, TEMP, sessions bloquantes
- WebLogic / Forms / Reports
- Linux OEL / Windows Server
- Bash / PowerShell
- Active Directory / DNS / BIND
- Stockage HPE Primera

---

## Objectif du dépôt

Ce dépôt regroupe progressivement :

- des scripts SQL de diagnostic Oracle ;
- des scripts Bash pour l’exploitation Oracle/Linux ;
- des procédures RMAN ;
- des requêtes de supervision RAC ;
- des notes techniques sur les incidents complexes ;
- des checklists d’administration ;
- des exemples de résolution de problèmes rencontrés en production.

---

## Projet mis en avant

### Oracle Materialized View Space Reclaimer

Solution PL/SQL de détection et de récupération d’espace pour les vues matérialisées Oracle dont le segment est devenu très supérieur au volume logique des données.

Le projet met en œuvre :

- une présélection dynamique à partir de `DBA_MVIEWS`, `DBA_TABLES` et `DBA_SEGMENTS` ;
- une comparaison entre allocation physique et volume logique estimé ;
- une collecte de statistiques fraîches avant toute décision ;
- un contrôle de l’historique des refresh et du mode `ATOMIC_REFRESH` ;
- un refresh `COMPLETE` contrôlé avec `atomic_refresh => FALSE` ;
- une mesure TABLE + INDEX avant/après et du volume réellement récupéré ;
- une journalisation par `RUN_ID` ;
- un rapport HTML ;
- une automatisation via `DBMS_SCHEDULER`.

Les validations réalisées sur des copies de test ont permis de récupérer de quelques centaines de Mo à plusieurs Go sur certaines vues matérialisées, avec mesure systématique avant/après.

➡️ **[Voir le projet complet](materialized-views/space-reclaimer/README_FR.md)**  
➡️ **[English version](materialized-views/space-reclaimer/README.md)**

---

## Structure du dépôt

Le dépôt est organisé progressivement par domaine. Le projet `materialized-views/space-reclaimer` est le premier module complet publié avec documentation, scripts, architecture, dépannage et résultats anonymisés.

```text
oracle-dba-toolkit/
├── materialized-views/
│   └── space-reclaimer/
│       ├── README.md
│       ├── README_FR.md
│       ├── architecture.md
│       ├── troubleshooting.md
│       ├── examples/
│       │   └── sample-results.md
│       └── sql/
│           ├── 01_create_repository_objects.sql
│           ├── 02_required_privileges.sql
│           ├── 03_adm_compact_mv_candidates.sql
│           ├── 04_adm_send_mv_compact_report.sql
│           ├── 05_scheduler_job.sql
│           └── 06_reporting_queries.sql
├── rman/                  # prévu / enrichissement progressif
├── performance/           # prévu / enrichissement progressif
├── rac/                   # prévu / enrichissement progressif
├── weblogic/              # prévu / enrichissement progressif
├── linux/                 # prévu / enrichissement progressif
└── README.md
```

---

## Domaines couverts

### Oracle Database

- Vérification des instances Oracle
- Contrôle des tablespaces
- Suivi de l’utilisation TEMP
- Suivi PGA / SGA
- Sessions bloquantes
- Top SQL
- Analyse AWR / ASH
- Erreurs ORA fréquentes
- Vues matérialisées : diagnostic, refresh, espace et automatisation

### Oracle RAC

- État CRS / Clusterware
- État des services RAC
- État des instances
- Diagnostic interconnexion
- Notes PRA / bascule / haute disponibilité

### RMAN

- Sauvegarde base complète
- Sauvegarde archivelogs
- Contrôle des jobs RMAN
- Nettoyage selon rétention
- Vérification des sauvegardes

### WebLogic / Forms / Reports

- Vérification des datasources
- Analyse des logs
- Notes d’administration WebLogic
- Incidents Forms / Reports

### Linux / Système

- Contrôle CPU / mémoire
- Contrôle espace disque
- Vérification réseau / DNS
- Automatisation Bash

---

## Exemples de scripts

### Sessions bloquantes Oracle

```sql
SELECT
    blocking_session,
    sid,
    serial#,
    username,
    status,
    event,
    wait_class,
    seconds_in_wait
FROM v$session
WHERE blocking_session IS NOT NULL
ORDER BY seconds_in_wait DESC;
```

### Utilisation TEMP

```sql
SELECT
    s.sid,
    s.serial#,
    s.username,
    s.program,
    u.tablespace,
    ROUND(u.blocks * t.block_size / 1024 / 1024, 2) AS temp_mb
FROM v$tempseg_usage u
JOIN v$session s ON u.session_addr = s.saddr
JOIN dba_tablespaces t ON u.tablespace = t.tablespace_name
ORDER BY temp_mb DESC;
```

### État des services RAC

```bash
#!/bin/bash

if [ -z "$ORACLE_UNQNAME" ]; then
  echo "Erreur : ORACLE_UNQNAME n'est pas défini."
  exit 1
fi

srvctl status service -d "$ORACLE_UNQNAME"
```

---

## Bonnes pratiques pour les scripts

Chaque script ajouté dans ce dépôt doit idéalement contenir :

- l’objectif du script ;
- les prérequis ;
- la version Oracle testée ;
- les droits nécessaires ;
- un exemple d’exécution ;
- une explication du résultat attendu.

Exemple d’en-tête recommandé :

```bash
#!/bin/bash
# Script      : check_rman_status.sh
# Auteur      : Fethallah Bennaceur
# Objectif    : Vérifier l’état des sauvegardes RMAN
# Plateforme  : Oracle Linux / Oracle Database 19c
# Usage       : ./check_rman_status.sh
```

---

## Avertissement

Les scripts publiés ici sont fournis comme base de travail et doivent être adaptés à chaque environnement avant une utilisation en production.

Avant toute exécution sur un environnement critique :

1. lire le script ;
2. comprendre son impact ;
3. tester sur un environnement de développement ou de recette ;
4. valider avec les procédures internes de l’entreprise.

---

## Contact

- Email : bennaceur.fethallah@gmail.com
- GitHub : https://github.com/fethallah-bennaceur
- Portfolio : https://fethallah-bennaceur.github.io
