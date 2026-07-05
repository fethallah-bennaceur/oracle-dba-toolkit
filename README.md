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

## Structure proposée

```text
oracle-dba-toolkit/
├── rman/
│   ├── backup_database.sh
│   ├── backup_archivelog.sh
│   └── check_rman_status.sql
├── performance/
│   ├── top_sql.sql
│   ├── temp_usage.sql
│   ├── pga_usage.sql
│   ├── blocking_sessions.sql
│   └── awr_ash_notes.md
├── rac/
│   ├── crs_status.sh
│   ├── services_status.sh
│   ├── instance_status.sql
│   └── rac_diagnostic_notes.md
├── weblogic/
│   ├── datasource_check.md
│   ├── forms_reports_notes.md
│   └── weblogic_logs_check.md
├── linux/
│   ├── disk_usage_check.sh
│   ├── memory_cpu_check.sh
│   └── network_dns_check.sh
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
