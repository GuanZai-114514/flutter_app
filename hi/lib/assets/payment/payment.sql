BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS "Easy_wallet" (
	"id"	INT,
	"payment_method"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "JKOPay" (
	"id"	INT,
	"payment_method"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "Line_Pay" (
	"id"	INT,
	"payment_method"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "PXPay_Plus" (
	"id"	INT,
	"payment_method"	VARCHAR(50),
	PRIMARY KEY("id")
);
CREATE TABLE IF NOT EXISTS "Taiwan_Pay" (
	"id"	INT,
	"payment_method"	VARCHAR(50),
	PRIMARY KEY("id")
);
INSERT INTO "Easy_wallet" ("id","payment_method") VALUES (20001,'錢包or銀行帳戶');
INSERT INTO "JKOPay" ("id","payment_method") VALUES (21001,'街口帳戶');
INSERT INTO "JKOPay" ("id","payment_method") VALUES (21002,'街利存帳戶');
INSERT INTO "JKOPay" ("id","payment_method") VALUES (21003,'街利存帳戶_新戶');
INSERT INTO "Line_Pay" ("id","payment_method") VALUES (24001,'中國信託Line Pay聯名卡 Visa');
INSERT INTO "Line_Pay" ("id","payment_method") VALUES (24002,'中國信託Line Pay聯名卡 JCB');
INSERT INTO "Line_Pay" ("id","payment_method") VALUES (24003,'富邦J卡');
INSERT INTO "Line_Pay" ("id","payment_method") VALUES (24004,'聯邦賴點卡');
INSERT INTO "Line_Pay" ("id","payment_method") VALUES (24005,'聯邦賴點卡_新戶');
INSERT INTO "Line_Pay" ("id","payment_method") VALUES (24006,'永豐DAWAY卡');
INSERT INTO "Line_Pay" ("id","payment_method") VALUES (24007,'永豐DAWAY卡_新戶');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22001,'全支付帳戶');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22002,'國泰世華');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22003,'將來銀行');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22004,'華泰銀行');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22005,'國泰世華信用卡');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22006,'富邦銀行信用卡');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22007,'華泰銀行信用卡');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22008,'上海商銀信用卡');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22009,'玉山銀行信用卡');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22010,'聯邦銀行信用卡');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22011,'華南銀行信用卡');
INSERT INTO "PXPay_Plus" ("id","payment_method") VALUES (22012,'台新銀行信用卡');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23001,'台灣銀行');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23002,'土地銀行');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23003,'合作金庫銀行');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23004,'第一銀行');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23005,'華南銀行');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23006,'彰化銀行');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23007,'兆豐銀行');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23008,'台灣企銀');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23009,'台灣銀行信用卡');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23010,'土地銀行信用卡');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23011,'合作金庫銀行信用卡');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23012,'第一銀行信用卡');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23013,'彰化銀行信用卡');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23014,'兆豐銀行信用卡');
INSERT INTO "Taiwan_Pay" ("id","payment_method") VALUES (23015,'台灣企銀信用卡');
COMMIT;
