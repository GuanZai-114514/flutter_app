BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS "Easy_wallet" (
	"id"	INT,
	"user_level"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "JKOPay" (
	"id"	INT,
	"user_level"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "Line_Pay" (
	"id"	INT,
	"user_level"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "PXPay_Plus" (
	"id"	INT,
	"user_level"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "Taiwan_Pay" (
	"id"	INT,
	"user_level"	VARCHAR(50),
	PRIMARY KEY("id")
);
INSERT INTO "Easy_wallet" ("id","user_level") VALUES (10001,'銀級');
INSERT INTO "Easy_wallet" ("id","user_level") VALUES (10002,'金級');
INSERT INTO "Easy_wallet" ("id","user_level") VALUES (10003,'白金級');
INSERT INTO "JKOPay" ("id","user_level") VALUES (11001,'銅牌');
INSERT INTO "JKOPay" ("id","user_level") VALUES (11002,'銀牌');
INSERT INTO "JKOPay" ("id","user_level") VALUES (11003,'金牌');
INSERT INTO "JKOPay" ("id","user_level") VALUES (11004,'白金');
INSERT INTO "JKOPay" ("id","user_level") VALUES (11005,'尊爵');
INSERT INTO "Line_Pay" ("id","user_level") VALUES (14001,'0');
INSERT INTO "PXPay_Plus" ("id","user_level") VALUES (12001,'0');
INSERT INTO "Taiwan_Pay" ("id","user_level") VALUES (13001,'0');
INSERT INTO "Taiwan_Pay" ("id","user_level") VALUES (13002,'黃金');
INSERT INTO "Taiwan_Pay" ("id","user_level") VALUES (13003,'白金');
INSERT INTO "Taiwan_Pay" ("id","user_level") VALUES (13004,'鑽石');
COMMIT;
