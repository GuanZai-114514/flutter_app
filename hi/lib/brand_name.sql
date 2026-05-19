BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS "brand_name" (
	"id"	INTEGER,
	"brand_name"	TEXT
);
INSERT INTO "brand_name" VALUES (1,'7-ELEVEN');
INSERT INTO "brand_name" VALUES (2,'全家便利商店');
INSERT INTO "brand_name" VALUES (3,'萊爾富');
INSERT INTO "brand_name" VALUES (4,'OK便利商店');
COMMIT;
