BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS "payment_software" (
	"id"	INT,
	"payment_software"	VARCHAR(50),
	"icon"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "store_members" (
	"id"	INT,
	"store_member"	VARCHAR(50),
	"icon"	VARCHAR(50),
	PRIMARY KEY("id")
);
INSERT INTO "payment_software" ("id","payment_software","icon") VALUES (1000,'悠遊付','1000.png');
INSERT INTO "payment_software" ("id","payment_software","icon") VALUES (1100,'街口支付','1100.png');
INSERT INTO "payment_software" ("id","payment_software","icon") VALUES (1200,'全支付','1200.png');
INSERT INTO "payment_software" ("id","payment_software","icon") VALUES (1300,'台灣Pay','1300.png');
INSERT INTO "payment_software" ("id","payment_software","icon") VALUES (1400,'Line Pay','1400.png');
INSERT INTO "store_members" ("id","store_member","icon") VALUES (101,'7-ELEVE','1.png');
INSERT INTO "store_members" ("id","store_member","icon") VALUES (102,'全家','2.png');
INSERT INTO "store_members" ("id","store_member","icon") VALUES (103,'萊爾富','3.png');
INSERT INTO "store_members" ("id","store_member","icon") VALUES (104,'OK','4.png');
COMMIT;
