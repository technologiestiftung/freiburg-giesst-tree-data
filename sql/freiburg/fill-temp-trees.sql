-- ABOUTME: Maps the raw Freiburg WFS layer ms:baum (table fr_baum_raw) into temp_trees.
-- ABOUTME: Run after --create-temp-table and the ogr2ogr load, before delete-trees/upsert-trees.
--
-- Load fr_baum_raw first (see README-FREIBURG.md):
--   ogr2ogr -f PostgreSQL PG:"$DB_URL" "<WFS GeoJSON URL>" -nln fr_baum_raw \
--     -lco GEOMETRY_NAME=geom -nlt POINT -overwrite

\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE fr_gattungen (gattung text PRIMARY KEY, gattung_deutsch text NOT NULL) ON COMMIT DROP;

-- Keys: first word of the cleaned botanical name. Values: uppercase like Berlin, because the
-- frontend matches gattung_deutsch against ids in src/i18n/*.ts (LINDE, AHORN, ROSSKASTANIE, ...).
INSERT INTO fr_gattungen VALUES
	('Abies', 'TANNE'),
	('Acer', 'AHORN'),
	('Aesculus', 'ROSSKASTANIE'),
	('Ailanthus', 'GÖTTERBAUM'),
	('Albizia', 'SEIDENAKAZIE'),
	('Alnus', 'ERLE'),
	('Amelanchier', 'FELSENBIRNE'),
	('Araucaria', 'ARAUKARIE'),
	('Betula', 'BIRKE'),
	('Buxus', 'BUCHSBAUM'),
	('Calocedrus', 'WEIHRAUCHZEDER'),
	('Carpinus', 'HAINBUCHE'),
	('Carya', 'HICKORY'),
	('Castanea', 'KASTANIE'),
	('Catalpa', 'TROMPETENBAUM'),
	('Cedrus', 'ZEDER'),
	('Celtis', 'ZÜRGELBAUM'),
	('Cercidiphyllum', 'KATSURABAUM'),
	('Cercis', 'JUDASBAUM'),
	('Chamaecyparis', 'SCHEINZYPRESSE'),
	('Cladrastis', 'GELBHOLZ'),
	('Cornus', 'HARTRIEGEL'),
	('Corylus', 'HASEL'),
	('Cotinus', 'PERÜCKENSTRAUCH'),
	('Crataegus', 'WEISSDORN'),
	('Cryptomeria', 'SICHELTANNE'),
	('Cupressus', 'ZYPRESSE'),
	('Cydonia', 'QUITTE'),
	('Davidia', 'TASCHENTUCHBAUM'),
	('Elaeagnus', 'ÖLWEIDE'),
	('Eucommia', 'GUTTAPERCHABAUM'),
	('Euodia', 'BIENENBAUM'),
	('Fagus', 'BUCHE'),
	('Fraxinus', 'ESCHE'),
	('Ginkgo', 'GINKGO'),
	('Gleditsia', 'GLEDITSCHIE'),
	('Gymnocladus', 'GEWEIHBAUM'),
	('Hamamelis', 'ZAUBERNUSS'),
	('Ilex', 'STECHPALME'),
	('Juglans', 'WALNUSS'),
	('Juniperus', 'WACHOLDER'),
	('Koelreuteria', 'BLASENESCHE'),
	('Larix', 'LÄRCHE'),
	('Liquidambar', 'AMBERBAUM'),
	('Liriodendron', 'TULPENBAUM'),
	('Magnolia', 'MAGNOLIE'),
	('Malus', 'APFEL'),
	('Metasequoia', 'URWELTMAMMUTBAUM'),
	('Morus', 'MAULBEERE'),
	('Nyssa', 'TUPELOBAUM'),
	('Ostrya', 'HOPFENBUCHE'),
	('Parrotia', 'EISENHOLZBAUM'),
	('Paulownia', 'BLAUGLOCKENBAUM'),
	('Phellodendron', 'KORKBAUM'),
	('Picea', 'FICHTE'),
	('Pinus', 'KIEFER'),
	('Platanus', 'PLATANE'),
	('Populus', 'PAPPEL'),
	('Prunus', 'KIRSCHE'),
	('Pseudotsuga', 'DOUGLASIE'),
	('Pterocarya', 'FLÜGELNUSS'),
	('Pyrus', 'BIRNE'),
	('Quercus', 'EICHE'),
	('Rhamnus', 'KREUZDORN'),
	('Robinia', 'ROBINIE'),
	('Salix', 'WEIDE'),
	('Sambucus', 'HOLUNDER'),
	('Sequoiadendron', 'MAMMUTBAUM'),
	('Sophora', 'SCHNURBAUM'),
	('Sorbus', 'EBERESCHE'),
	('Taxodium', 'SUMPFZYPRESSE'),
	('Taxus', 'EIBE'),
	('Thuja', 'LEBENSBAUM'),
	('Tilia', 'LINDE'),
	('Tsuga', 'HEMLOCKTANNE'),
	('Ulmus', 'ULME'),
	('Zelkova', 'ZELKOVE');

CREATE TEMP TABLE fr_clean ON COMMIT DROP AS
SELECT
	baum_nr::bigint::text AS id,
	-- collapse double spaces and fix known typos in the source
	regexp_replace(regexp_replace(regexp_replace(
		regexp_replace(trim(baumart_botanisch), '\s+', ' ', 'g'),
		'^Prununs ', 'Prunus '),
		'^Eucomia ', 'Eucommia '),
		'^Scandsorbus ', 'Sorbus ') AS art_bot,
	trim(baumart_deutsch) AS art_dtsch,
	-- plausibility limits, see notes.md "Ausreißer"
	CASE WHEN stammumfang > 0 AND stammumfang <= 1000 THEN round(stammumfang)::int::text END AS stammumfg,
	CASE WHEN kronendurchmesser > 0 AND kronendurchmesser <= 40 THEN round(kronendurchmesser)::int::text END AS kronedurch,
	CASE WHEN baumhoehe > 0 THEN baumhoehe END AS baumhoehe,
	-- snap to ~10 cm so duplicates with float noise in the coordinates count as exact
	ST_SnapToGrid(ST_Force2D(geom), 0.000001) AS geom
FROM fr_baum_raw
WHERE baum_nr IS NOT NULL
	AND baumart_botanisch IS DISTINCT FROM 'Standort ohne Baum';

-- Exact duplicates collapse via DISTINCT. Ids that still occur more than once are real
-- collisions (different trees, same baum_nr): skip them and print them below.
-- ponytail: collisions are dropped, not resolved; clarify with the city (notes.md, open questions).
CREATE TEMP TABLE fr_unique ON COMMIT DROP AS
SELECT DISTINCT art_bot, art_dtsch, stammumfg, kronedurch, baumhoehe, geom, id FROM fr_clean;

CREATE TEMP TABLE fr_collisions ON COMMIT DROP AS
SELECT id FROM fr_unique GROUP BY id HAVING count(*) > 1;

INSERT INTO temp_trees (gml_id, art_bot, art_dtsch, gattung, gattung_deutsch,
	stammumfg, kronedurch, baumhoehe, eigentuemer, geom)
SELECT
	u.id,
	u.art_bot,
	u.art_dtsch,
	upper(g.gattung), -- uppercase like Berlin (e.g. CARPINUS)
	g.gattung_deutsch,
	u.stammumfg,
	u.kronedurch,
	u.baumhoehe,
	'Stadt Freiburg',
	u.geom
FROM fr_unique u
LEFT JOIN fr_gattungen g ON g.gattung = split_part(u.art_bot, ' ', 1)
WHERE u.id NOT IN (SELECT id FROM fr_collisions);

-- Report
SELECT 'raw features' AS metric, count(*) AS value FROM fr_baum_raw
UNION ALL SELECT 'skipped: collision ids', count(*) FROM fr_collisions
UNION ALL SELECT 'temp_trees rows', count(*) FROM temp_trees
UNION ALL SELECT 'temp_trees without gattung_deutsch', count(*) FROM temp_trees WHERE gattung_deutsch IS NULL;

SELECT 'collision' AS info, c.id, u.art_dtsch, ST_AsText(u.geom) AS geom
FROM fr_collisions c JOIN fr_unique u USING (id)
ORDER BY c.id;

SELECT 'no gattung_deutsch' AS info, art_bot, count(*)
FROM temp_trees WHERE gattung_deutsch IS NULL
GROUP BY art_bot ORDER BY count(*) DESC;

DROP TABLE fr_baum_raw;

COMMIT;
