-- 01_stores.sql
CREATE TABLE IF NOT EXISTS stores (
    id                    INTEGER PRIMARY KEY,
    keyword               TEXT    NOT NULL,
    icon                  TEXT,
    support_payment_store TEXT
);

INSERT INTO stores (id, keyword, icon, support_payment_store) VALUES (1, '7-ELEVE', '1.png', '10、11、13、14');
INSERT INTO stores (id, keyword, icon, support_payment_store) VALUES (2, '全家', '2.png', '10、11、13、14');
INSERT INTO stores (id, keyword, icon, support_payment_store) VALUES (3, '萊爾富', '3.png', '10、11、13、14');
INSERT INTO stores (id, keyword, icon, support_payment_store) VALUES (4, 'OK', '4.png', '10、11、12、13、14');
