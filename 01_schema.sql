-- =====================================================================
-- 카페 주문 관리 데이터베이스 - 스키마 생성 스크립트
-- DBMS: SQLite 3
-- 실행 순서: 01_schema.sql -> 02_data.sql -> (04_bonus.sql) -> 03_queries.sql
--   ※ 03_queries.sql 의 Q13(UPDATE)/Q14(DELETE)가 DB 상태를 바꾸므로 맨 마지막에 실행한다.
--     자세한 이유는 README '2. 실행 방법' 참고.
--
-- [이 파일에서 쓰인 DB 고유 문법 요약]  (미션 요구: DB 전용 문법은 주석으로 명시)
--   PRAGMA              - SQLite 전용 설정 구문
--   AUTOINCREMENT       - SQLite 전용 키워드 (MySQL AUTO_INCREMENT / PostgreSQL SERIAL·IDENTITY)
--   DATE('now')         - SQLite 내장 함수 (MySQL CURDATE() / PostgreSQL CURRENT_DATE)
--   DATE / DATETIME 타입 - SQLite 에는 이런 타입이 실제로 없다 (아래 각 컬럼 주석 참고)
-- =====================================================================

-- [SQLite 전용] PRAGMA 는 SQLite 고유 설정 구문이다.
--   foreign_keys 는 하위호환 때문에 '연결(connection)마다 기본 OFF' 다.
--   즉 아래에 FOREIGN KEY 를 선언해도 이 PRAGMA 없이는 검사 자체를 하지 않는다.
--   MySQL / PostgreSQL 은 FK 가 기본 활성이라 이런 스위치가 필요 없다.
--   -> 자세한 내용은 README '7.1 FK를 선언했는데 안 막혔다' 참고.
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
    -- [SQLite 전용] INTEGER PRIMARY KEY 는 그 자체로 rowid 의 별칭이라 이미 자동 증가한다.
    --   AUTOINCREMENT 를 덧붙이면 "삭제된 id 를 재사용하지 않는다"는 보장이 추가된다.
    --   주문/결제처럼 과거 식별자가 재사용되면 안 되는 도메인이라 명시적으로 붙였다.
    --   대신 sqlite_sequence 테이블을 유지하는 약간의 쓰기 비용이 생긴다.
    id          INTEGER PRIMARY KEY AUTOINCREMENT,

    -- TEXT : 이름은 길이가 가변이고 산술 연산 대상이 아니다. NOT NULL - 이름 없는 고객은 없다.
    name        TEXT    NOT NULL,

    -- UNIQUE : 로그인/식별에 쓰이는 자연키. 같은 이메일로 두 계정이 생기면 안 된다.
    --   UNIQUE 를 걸면 SQLite 가 sqlite_autoindex_customer_1 인덱스를 자동 생성한다(03_queries.sql Q15 참고).
    email       TEXT    NOT NULL UNIQUE,

    -- TEXT : '010-1234-5678' 처럼 하이픈/선행 0 이 의미를 갖는다. INTEGER 로 저장하면 앞의 0 이 사라진다.
    --   유일하게 NULL 을 허용하는 컬럼이다 (전화번호를 안 남기는 고객이 있을 수 있다).
    phone       TEXT,

    -- [SQLite 전용] DATE 는 SQLite 의 '실제 타입'이 아니라 NUMERIC 어피니티(affinity) 힌트일 뿐이다.
    --   값은 TEXT 'YYYY-MM-DD' 로 저장된다 (SELECT typeof(joined_at) -> 'text').
    --   이 포맷은 사전순 정렬 = 날짜순 정렬이라 Q3 의 ORDER BY joined_at DESC 가 그대로 동작한다.
    -- [SQLite 전용] DATE('now') 는 SQLite 내장 함수이며 반환값은 로컬시각이 아니라 UTC 다.
    --   KST 가 필요하면 DATE('now','localtime').
    joined_at   DATE    NOT NULL DEFAULT (DATE('now'))
);

-- ---------------------------------------------------------------------
-- 2) category : 메뉴 카테고리
--   menu 에서 카테고리명을 문자열로 반복 저장하지 않고 테이블로 분리한 이유:
--   ① 이름을 고치면 한 행만 고치면 된다(엑셀식 반복 입력은 전부 찾아 고쳐야 한다)
--   ② FK 로 오타('커피'/'커 피')를 원천 차단한다
--   ③ 메뉴가 0개인 카테고리('굿즈')도 독립적으로 존재할 수 있다 -> LEFT JOIN 대조 재료(Q8/Q8-B)
-- ---------------------------------------------------------------------
CREATE TABLE category (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,   -- [SQLite 전용] AUTOINCREMENT
    name        TEXT    NOT NULL UNIQUE              -- 카테고리 이름은 유일해야 함 (자동 인덱스 생성됨)
);

-- ---------------------------------------------------------------------
-- 3) menu : 메뉴 (category 1:N menu)
-- ---------------------------------------------------------------------
CREATE TABLE menu (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,   -- [SQLite 전용] AUTOINCREMENT

    -- UNIQUE : Q13 UPDATE 와 보너스 리포트가 name 을 식별자로 쓴다(WHERE name = '아메리카노').
    --   동명 메뉴가 두 개 생기면 UPDATE 가 의도치 않게 2행을 치므로 유일성을 강제한다.
    name            TEXT    NOT NULL UNIQUE,

    -- INTEGER : 원(KRW)은 소수점이 없다. 금액에 REAL(부동소수)을 쓰면 합계에 오차가 누적된다.
    price           INTEGER NOT NULL CHECK (price >= 0),     -- CHECK 제약: 음수 가격 차단

    category_id     INTEGER NOT NULL,

    -- INTEGER 0/1 : SQLite 에는 BOOLEAN 타입이 없다. CHECK 로 0/1 외의 값을 막는다.
    is_available    INTEGER NOT NULL DEFAULT 1
                    CHECK (is_available IN (0, 1)),          -- 1=판매중, 0=품절

    -- ON DELETE 정책을 쓰지 않았다(= NO ACTION). 메뉴가 달려 있는 카테고리는 삭제를 '막는' 게 맞다.
    --   실측: DELETE FROM category WHERE id=1 -> FOREIGN KEY constraint failed
    FOREIGN KEY (category_id) REFERENCES category(id)
);

-- ---------------------------------------------------------------------
-- 4) order_header : 주문 헤더 (customer 1:N order_header)
-- ---------------------------------------------------------------------
CREATE TABLE order_header (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,   -- [SQLite 전용] AUTOINCREMENT
    customer_id     INTEGER NOT NULL,

    -- [SQLite 전용] DATETIME 도 실제 타입이 아니라 NUMERIC 어피니티 힌트다.
    --   'YYYY-MM-DD HH:MM:SS' TEXT 로 저장된다 (SELECT typeof(order_date) -> 'text').
    --   CURRENT_TIMESTAMP 는 표준 SQL 키워드지만 SQLite 는 UTC 기준 값을 돌려준다.
    --   -> 일자별 매출(04_bonus.sql 지표 1)의 날짜 경계가 KST 와 9시간 어긋날 수 있다.
    order_date      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- TEXT + CHECK 화이트리스트 : 상태값을 문자열로 두되 허용 집합을 DB가 강제한다.
    --   실측: status='DONE' 삽입 시 CHECK constraint failed
    status          TEXT    NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING','COMPLETED','CANCELLED')),

    -- ON DELETE 정책 없음(= NO ACTION). 주문 이력이 있는 고객은 삭제를 막는 것이 회계상 맞다.
    --   실측: DELETE FROM customer WHERE id=1 -> FOREIGN KEY constraint failed
    FOREIGN KEY (customer_id) REFERENCES customer(id)
);

-- ---------------------------------------------------------------------
-- 5) order_detail : 주문 상세 (order_header 1:N order_detail, menu 1:N order_detail)
-- ---------------------------------------------------------------------
CREATE TABLE order_detail (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,   -- [SQLite 전용] AUTOINCREMENT
    order_id        INTEGER NOT NULL,
    menu_id         INTEGER NOT NULL,
    quantity        INTEGER NOT NULL CHECK (quantity > 0),

    -- 주문 시점 단가 스냅샷. menu.price 를 조인해서 쓰지 않는 이유:
    --   가격이 바뀌면 과거 매출까지 소급 변경되어 버린다.
    --   실증: Q13 에서 아메리카노를 3500 -> 4000 으로 올려도 과거 주문 합계는 3500 기준으로 유지된다.
    unit_price      INTEGER NOT NULL CHECK (unit_price >= 0),

    -- 4개 FK 중 유일하게 CASCADE 를 건 곳. 주문 헤더가 사라지면 그 상세 라인은 존재 의미가 없다
    -- (주문 없는 주문상세 = 고아 데이터). 반대로 고객/카테고리/메뉴는 이력 보존이 우선이라 NO ACTION.
    --   실측: DELETE FROM order_header WHERE id=1 -> 성공, order_detail 20행 -> 18행
    FOREIGN KEY (order_id) REFERENCES order_header(id) ON DELETE CASCADE,

    -- 메뉴는 단종되더라도 과거 주문 이력이 남아야 하므로 CASCADE 를 걸지 않는다.
    FOREIGN KEY (menu_id)  REFERENCES menu(id)

    -- [설계 판단] (order_id, menu_id) 복합 UNIQUE 는 일부러 걸지 않았다.
    --   같은 주문에 '아메리카노 ICE 1잔 + 아메리카노 HOT 1잔' 처럼 옵션이 다른 같은 메뉴가
    --   별도 라인으로 들어갈 수 있어야 하기 때문이다(옵션 컬럼은 이번 과제 범위 밖).
    --   대신 집계 쿼리는 전부 SUM(quantity) 기준이라 라인이 나뉘어도 수치는 정확하다.
);

-- ---------------------------------------------------------------------
-- 관계 요약 (1:N 관계 4개 - 미션 요구는 2개 이상)
--   category (1) ---- (N) menu            : 카테고리 하나에 메뉴 여러 개
--   customer (1) ---- (N) order_header    : 고객 한 명이 주문 여러 번
--   order_header (1) -- (N) order_detail  : 주문 한 건에 메뉴 라인 여러 개
--   menu (1) -------- (N) order_detail    : 메뉴 하나가 여러 주문에 등장
--
-- 인덱스는 스키마가 아니라 03_queries.sql 의 [Q15] 에서 다룬다
-- (미션이 인덱스를 '쿼리 범주'로 요구하기 때문 + 적용 전/후 실행계획을 대조하기 위해).
-- ---------------------------------------------------------------------
