-- ============================================================
-- payment_options.sql
-- 行動支付選項資料表
-- 供 Flutter sqflite 讀取，對應 PaymentSelectionScreen 下拉選單
-- ============================================================

CREATE TABLE IF NOT EXISTS payment_options (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    platform       TEXT NOT NULL,   -- 支付平台
    method         TEXT NOT NULL,   -- 付款方式
    level          TEXT NOT NULL    -- 等級（無等級填 '無'）
);

-- ── 悠遊付 ────────────────────────────────────────────────────
-- 付款方式：錢包or銀行帳戶　等級：銀級 / 金級 / 白金級
INSERT INTO payment_options (platform, method, level) VALUES
('悠遊付', '錢包or銀行帳戶', '銀級'),
('悠遊付', '錢包or銀行帳戶', '金級'),
('悠遊付', '錢包or銀行帳戶', '白金級');

-- ── 街口支付 ─────────────────────────────────────────────────
-- 付款方式：街口帳戶（無等級）
INSERT INTO payment_options (platform, method, level) VALUES
('街口支付', '街口帳戶', '無');

-- 付款方式：街利存帳戶　等級：銅牌 / 銀牌 / 金牌 / 白金 / 尊爵
INSERT INTO payment_options (platform, method, level) VALUES
('街口支付', '街利存帳戶', '銅牌'),
('街口支付', '街利存帳戶', '銀牌'),
('街口支付', '街利存帳戶', '金牌'),
('街口支付', '街利存帳戶', '白金'),
('街口支付', '街利存帳戶', '尊爵');

-- 付款方式：街利存帳戶_新戶　等級：銅牌 / 銀牌 / 金牌 / 白金 / 尊爵
INSERT INTO payment_options (platform, method, level) VALUES
('街口支付', '街利存帳戶_新戶', '銅牌'),
('街口支付', '街利存帳戶_新戶', '銀牌'),
('街口支付', '街利存帳戶_新戶', '金牌'),
('街口支付', '街利存帳戶_新戶', '白金'),
('街口支付', '街利存帳戶_新戶', '尊爵');

-- ── 全支付 ────────────────────────────────────────────────────
-- 全支付無等級區分，所有付款方式 level = '無'
INSERT INTO payment_options (platform, method, level) VALUES
('全支付', '全支付帳戶',     '無'),
('全支付', '國泰世華',       '無'),
('全支付', '將來銀行',       '無'),
('全支付', '華泰銀行',       '無'),
('全支付', '國泰世華信用卡', '無'),
('全支付', '富邦銀行信用卡', '無'),
('全支付', '華泰銀行信用卡', '無'),
('全支付', '上海商銀信用卡', '無'),
('全支付', '玉山銀行信用卡', '無'),
('全支付', '聯邦銀行信用卡', '無'),
('全支付', '華南銀行信用卡', '無'),
('全支付', '台新銀行信用卡', '無');

-- ── 台灣Pay ───────────────────────────────────────────────────
-- 銀行帳戶（無等級）
INSERT INTO payment_options (platform, method, level) VALUES
('台灣Pay', '台灣銀行',       '無'),
('台灣Pay', '土地銀行',       '無'),
('台灣Pay', '合作金庫銀行',   '無'),
('台灣Pay', '第一銀行',       '無'),
('台灣Pay', '華南銀行',       '無'),
('台灣Pay', '兆豐銀行',       '無'),
('台灣Pay', '台灣企銀',       '無');

-- 彰化銀行有等級（黃金 / 白金 / 鑽石）
INSERT INTO payment_options (platform, method, level) VALUES
('台灣Pay', '彰化銀行', '黃金'),
('台灣Pay', '彰化銀行', '白金'),
('台灣Pay', '彰化銀行', '鑽石');

-- 信用卡（無等級）
INSERT INTO payment_options (platform, method, level) VALUES
('台灣Pay', '台灣銀行信用卡',     '無'),
('台灣Pay', '土地銀行信用卡',     '無'),
('台灣Pay', '合作金庫銀行信用卡', '無'),
('台灣Pay', '第一銀行信用卡',     '無'),
('台灣Pay', '兆豐銀行信用卡',     '無'),
('台灣Pay', '台灣企銀信用卡',     '無');

-- 彰化銀行信用卡有等級
INSERT INTO payment_options (platform, method, level) VALUES
('台灣Pay', '彰化銀行信用卡', '黃金'),
('台灣Pay', '彰化銀行信用卡', '白金'),
('台灣Pay', '彰化銀行信用卡', '鑽石');

-- ── Line Pay ──────────────────────────────────────────────────
-- Line Pay 全部無等級
INSERT INTO payment_options (platform, method, level) VALUES
('Line Pay', '中國信託Line Pay聯名卡 Visa', '無'),
('Line Pay', '中國信託Line Pay聯名卡 JCB',  '無'),
('Line Pay', '富邦J卡',                     '無'),
('Line Pay', '聯邦賴點卡',                  '無'),
('Line Pay', '聯邦賴點卡_新戶',             '無'),
('Line Pay', '永豐DAWAY卡',                 '無'),
('Line Pay', '永豐DAWAY卡_新戶',            '無');
