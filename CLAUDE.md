# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Freiburg-Kopie von `giessdenkiez-de-tree-data` (Upstream = `upstream`-Remote). Importiert den jährlichen Baumbestand in die Supabase-Tabelle `trees`. Freiburg nutzt den Berliner Code unverändert; Freiburg-Spezifisches liegt nur in `sql/freiburg/` und `README-FREIBURG.md`. Neue Freiburg-Logik dort ablegen, nicht in `src/` (hält Upstream-Merges klein).

Siehe auch `AGENTS.md`: `.geojson`-Dateien nie komplett in den Speicher laden (`jq` oder streamende `.ts`-Skripte).

## Befehle

Node 26 via `mise` (lädt `.env` automatisch), kein Build-Schritt: `.ts` läuft direkt per Type Stripping.

- Setup: `mise install && npm ci`, `.env` aus `sample.env` (`PG*`-Variablen; lokal Supabase auf Port 54322)
- CLI: `node src/cli.ts --help` (ohne mise: `node --env-file=.env src/cli.ts …`)
- Tests (node:test; `npm test` ist ein No-op): `node --test tests/*.test.ts`, einzeln `node --test tests/import-report.test.ts`
- DB-Verbindung prüfen: `node src/cli.ts --test-connection`
- Fast alle Schritte unterstützen `--dry-run`

## Ablauf Freiburg

Vollständig in `README-FREIBURG.md`. Kurz: `--create-temp-table` → WFS `ms:baum` per `ogr2ogr` nach `fr_baum_raw` → `psql -X -f sql/freiburg/fill-temp-trees.sql` → `sql/disable-tree-refresh-triggers.sql` → `--delete-trees` (erst `--dry-run`) → `--upsert-trees` → `sql/enable-tree-refresh-triggers.sql` → `--clean-up`.

Der Berliner GeoJSON-Weg (`--import-geojson`, `sql/normalize-temp-tree-ids.sql`) wird in Freiburg nicht genutzt.

## Architektur

- `src/cli.ts`: einziger Einstieg, `node:util` `parseArgs`; jedes Flag ruft genau einen Schritt in `src/db/*.ts` auf und beendet sich. Schritte laufen bewusst einzeln, damit man dazwischen prüfen kann.
- `src/config.ts`: globaler Config-Store (`temp-trees-table`, `dry-run`), wird von der CLI gesetzt und in den DB-Modulen per `config()` gelesen.
- `temp_trees` (Schema in `src/db/create-table.ts`) ist die Staging-Tabelle; ihre Spalten sind eine Obermenge der Berliner WFS-Jahrgänge. `fill-temp-trees.sql` muss auf genau diese Spalten mappen.
- `upsert-trees.ts`: batchweise `INSERT … ON CONFLICT (id) DO UPDATE` aus `temp_trees WHERE processed = false`, markiert Zeilen als `processed` → abgebrochene Läufe sind fortsetzbar. Setzt bei bestehenden Bäumen `radolan_*`, `adopted`, `watered`, `caretaker` auf NULL → danach DWD-Harvester laufen lassen.
- `delete-trees.ts`: löscht Bäume, die nicht in `temp_trees` sind, inkl. ihrer `trees_watered`/`trees_adopted`-Einträge. Verschwinden viele Bäume, hat sich wahrscheinlich die ID-Vergabe der Stadt geändert → nicht löschen, klären.
- Trigger auf `public.trees` refreshen Materialized Views bei jeder Änderung; für Bulk-Läufe und `pg_restore` deaktivieren (`sql/disable-…`/`enable-…`).
- `backup-and-restore/`: Shell-Skripte für DB-Dumps und zum Übertragen von `temp_trees` von Staging nach Produktion (setzt `processed` zurück).
- `data-wrangling/<jahr>/`, `REPORT*.md`: Berliner Einmal-Aufbereitungen, für Freiburg nur Referenz.

## Konventionen

- Neue Dateien beginnen mit zwei `ABOUTME:`-Kommentarzeilen (wie in `src/`, `tests/`, `sql/`).
- Freiburg-SQL-Skripte: `\set ON_ERROR_STOP on`, in einer Transaktion, mit `psql -X` ausführen.
- Prettier über `@technologiestiftung/prettier-config` (Tabs).
