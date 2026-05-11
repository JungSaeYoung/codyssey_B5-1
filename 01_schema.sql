-- =====================================================================
-- 카페 주문 관리 데이터베이스 - 스키마 생성 스크립트
-- DBMS: SQLite 3
-- 실행 순서: 01_schema.sql -> 02_data.sql -> 03_queries.sql
-- =====================================================================

-- FK 제약을 실제로 동작시키려면 SQLite는 세션마다 켜주어야 한다.
PRAGMA foreign_keys = ON;

-- 기존 테이블이 있으면 순서대로 정리 (자식 -> 부모)
DROP TABLE IF EXISTS order_detail;
DROP TABLE IF EXISTS order_header;
DROP TABLE IF EXISTS menu;
DROP TABLE IF EXISTS category;
DROP TABLE IF EXISTS customer;

-- ---------------------------------------------------------------------
-- 1) customer : 고객
-- ---------------------------------------------------------------------
CREATE TABLE customer (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,           -- PK (SQLite 전용 키워드: AUTOINCREMENT)
    name        TEXT    NOT NULL,                            -- NOT NULL 제약
    email       TEXT    NOT NULL UNIQUE,                     -- UNIQUE 제약
    phone       TEXT,
    joined_at   DATE    NOT NULL DEFAULT (DATE('now'))       -- SQLite 전용: DATE('now')
);

-- ---------------------------------------------------------------------
-- 2) category : 메뉴 카테고리
-- ---------------------------------------------------------------------
CREATE TABLE category (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE                      -- 카테고리 이름은 유일해야 함
);

-- ---------------------------------------------------------------------
-- 3) menu : 메뉴 (category 1:N menu)
-- ---------------------------------------------------------------------
CREATE TABLE menu (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT    NOT NULL,
    price           INTEGER NOT NULL CHECK (price >= 0),     -- CHECK 제약: 음수 가격 차단
    category_id     INTEGER NOT NULL,
    is_available    INTEGER NOT NULL DEFAULT 1,              -- 1=판매중, 0=품절
    FOREIGN KEY (category_id) REFERENCES category(id)
);

-- ---------------------------------------------------------------------
-- 4) order_header : 주문 헤더 (customer 1:N order_header)
-- ---------------------------------------------------------------------
CREATE TABLE order_header (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id     INTEGER NOT NULL,
    order_date      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status          TEXT    NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING','COMPLETED','CANCELLED')),
    FOREIGN KEY (customer_id) REFERENCES customer(id)
);

-- ---------------------------------------------------------------------
-- 5) order_detail : 주문 상세 (order_header 1:N order_detail, menu 1:N order_detail)
-- ---------------------------------------------------------------------
CREATE TABLE order_detail (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id        INTEGER NOT NULL,
    menu_id         INTEGER NOT NULL,
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    unit_price      INTEGER NOT NULL CHECK (unit_price >= 0),  -- 주문 시점 단가 스냅샷
    FOREIGN KEY (order_id) REFERENCES order_header(id) ON DELETE CASCADE,
    FOREIGN KEY (menu_id)  REFERENCES menu(id)
);

-- ---------------------------------------------------------------------
-- 관계 요약
--   category (1) ---- (N) menu
--   customer (1) ---- (N) order_header
--   order_header (1) -- (N) order_detail
--   menu (1) -------- (N) order_detail
-- ---------------------------------------------------------------------
