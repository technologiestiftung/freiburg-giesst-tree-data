# Freiburg gießt: Baumdaten-Import

Freiburg nutzt das Berliner Tool unverändert. Neu ist nur [sql/freiburg/fill-temp-trees.sql](sql/freiburg/fill-temp-trees.sql): Es bildet den WFS-Layer `ms:baum` der Stadt Freiburg auf `temp_trees` ab.

Was das Skript macht:
- `baum_nr` wird zur `id`.
- Botanische Namen werden normalisiert. Daraus werden Gattung und deutsche Gattung abgeleitet. Die Gattungsliste steht in der Datei. Die deutschen Gattungen sind in Großbuchstaben geschrieben, wie die IDs in `src/i18n` des Frontends.
- Ausreißer werden auf NULL gesetzt.
- „Standort ohne Baum“ wird entfernt.
- Exakte Duplikate werden zusammengefasst. IDs, die zu mehreren verschiedenen Bäumen gehören, werden übersprungen und am Ende ausgegeben.

`bezirk` bleibt leer, bis die Stadtteil-Geometrien geklärt sind. `pflanzjahr` gibt es im WFS nicht.

## Ablauf

Benötigt: Node (siehe `mise.toml`), `npm ci`, GDAL (`ogr2ogr`), `psql`. Die DB-Zugangsdaten kommen als `PG*`-Variablen in `.env` (siehe `sample.env`). Lokal ist das der Supabase-Stack auf Port 54322.

```bash
set -a; source .env; set +a
WFS='https://geoportal.freiburg.de/wfs/gut_pit/gut_pit?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=ms:baum&SRSNAME=EPSG:4326&OUTPUTFORMAT=application/json;%20subtype=geojson;%20charset=utf-8'

node src/cli.ts --create-temp-table
ogr2ogr -f PostgreSQL PG:"host=$PGHOST port=$PGPORT user=$PGUSER password=$PGPASSWORD dbname=$PGDATABASE" \
  "$WFS" -nln fr_baum_raw -lco GEOMETRY_NAME=geom -nlt POINT -overwrite
psql -X -f sql/freiburg/fill-temp-trees.sql      # Bericht prüfen: Kollisionen, fehlende Gattungen
psql -X -f sql/sanity-checks.sql                 # optional: Vergleich mit trees
psql -X -f sql/disable-tree-refresh-triggers.sql
node src/cli.ts --delete-trees --dry-run         # wie viele Bäume, Gießungen und Adoptionen würden gelöscht?
node src/cli.ts --delete-trees                   # nur wenn die Zahlen plausibel sind
node src/cli.ts --upsert-trees
psql -X -f sql/enable-tree-refresh-triggers.sql  # Trigger an, Views neu berechnen
node src/cli.ts --clean-up
```

**Vorsicht:** `--delete-trees` löscht auch alle Gießungen und Adoptionen der Bäume, die nicht mehr im WFS stehen. Verschwinden viele Bäume auf einmal, hat sich vermutlich die ID-Vergabe der Stadt geändert. Dann nicht löschen, sondern erst mit der Stadt klären.

**Hinweis Updates:** `--upsert-trees` setzt bei bestehenden Bäumen auch `radolan_sum`, `radolan_days`, `adopted`, `watered` und `caretaker` auf NULL (Berliner Verhalten). Nach einem Update deshalb den DWD-Harvester laufen lassen.

Reihenfolge der Umgebungen: lokal, dann Staging, dann Produktion. Wenn auf Staging alles stimmt, kann `temp_trees` mit `backup-and-restore/` nach Produktion übertragen werden, siehe README.

Stand 04.11.2026: 45.602 Features im WFS. Davon werden 45.365 Bäume importiert, 20 IDs werden als Kollision übersprungen.
