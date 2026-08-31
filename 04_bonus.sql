-- =====================================================================
-- 보너스 과제
-- (1) 같은 요구를 JOIN / 서브쿼리 두 방식으로 풀고 실행계획까지 비교
-- (2) 데이터 정합성 깨뜨려 보기 (FK/UNIQUE/CHECK/NOT NULL 위반) + 올바른 해결법
-- (3) 미니 리포트 - 이 DB로 뽑을 수 있는 핵심 지표 3개
--
-- ★ 실행 순서: 이 파일은 01_schema.sql + 02_data.sql 직후,
--   03_queries.sql 보다 '먼저' 실행해야 한다.
--   03_queries.sql 의 Q14 DELETE 가 CANCELLED 주문(박지호의 유일한 주문)을 지우면
--   아래 (1)의 결과가 4행 -> 3행으로 달라져 캡처가 재현되지 않는다.
--
-- ※ (2) 는 일부러 실패하는 문장을 포함한다. 에러 메시지가 출력되는 것이 정상이며
--   sqlite3 CLI 는 `.bail off` 상태에서 계속 진행한다 (종료코드 1 이 정상).
-- =====================================================================

PRAGMA foreign_keys = ON;

-- 전제조건 자가진단: 이 캡처가 '초기 데이터 상태'에서 생성되었음을 파일 스스로 증명한다.
SELECT (SELECT COUNT(*) FROM order_header)                           AS orders_expect_12,
       (SELECT COUNT(*) FROM order_header WHERE status='CANCELLED')  AS cancelled_expect_2,
       (SELECT COUNT(*) FROM order_detail)                           AS details_expect_20,
       (SELECT price FROM menu WHERE name='아메리카노')              AS americano_expect_3500;

-- =====================================================================
-- (1) 같은 요구를 JOIN / 서브쿼리 두 방식으로 풀기
--     요구: "아메리카노를 한 번이라도 주문한 고객 이름 목록"
-- =====================================================================

-- ---------------------------------------------------------------------
-- >> (1-a) JOIN 방식 - 네 테이블을 이어 붙여 결과 행을 직접 만든다
--   한 고객이 아메리카노를 여러 번 주문하면 그만큼 행이 늘어나므로 DISTINCT 가 필요하다.
-- ---------------------------------------------------------------------
SELECT DISTINCT c.id, c.name
FROM   customer c
INNER  JOIN order_header oh ON oh.customer_id = c.id
INNER  JOIN order_detail od ON od.order_id    = oh.id
INNER  JOIN menu m          ON m.id           = od.menu_id
WHERE  m.name = '아메리카노'
ORDER  BY c.id;

-- ---------------------------------------------------------------------
-- >> (1-b) 서브쿼리 방식 (IN) - 조건에 맞는 customer_id 목록을 먼저 만들고 그걸로 거른다
--   결과가 고객 컬럼뿐이므로 DISTINCT 가 필요 없다 (IN 은 존재 여부만 보기 때문).
-- ---------------------------------------------------------------------
SELECT id, name
FROM   customer
WHERE  id IN (
    SELECT oh.customer_id
    FROM   order_header oh
    JOIN   order_detail od ON od.order_id = oh.id
    JOIN   menu         m  ON m.id        = od.menu_id
    WHERE  m.name = '아메리카노'
)
ORDER BY id;

-- ---------------------------------------------------------------------
-- >> (1-c) 서브쿼리 방식 (EXISTS, 상관 서브쿼리)
--   (1-b)는 서브쿼리 '안에서' JOIN 을 3개 써서 사실 JOIN 과 대조가 완전하지 않다.
--   EXISTS 는 바깥 행 하나하나에 대해 "이런 행이 존재하는가?"만 물으며,
--   조건에 맞는 행을 하나 찾는 순간 즉시 멈춘다(short-circuit).
-- ---------------------------------------------------------------------
SELECT c.id, c.name
FROM   customer c
WHERE  EXISTS (
    SELECT 1
    FROM   order_header oh
    JOIN   order_detail od ON od.order_id = oh.id
    JOIN   menu         m  ON m.id        = od.menu_id
    WHERE  oh.customer_id = c.id           -- 바깥 쿼리의 c 를 참조 = 상관(correlated) 서브쿼리
      AND  m.name = '아메리카노'
)
ORDER BY c.id;

-- ---------------------------------------------------------------------
-- >> (1-d) 세 방식의 실행계획 비교 - 주장을 실측으로 뒷받침한다
-- [SQLite 전용] EXPLAIN QUERY PLAN
-- ---------------------------------------------------------------------
EXPLAIN QUERY PLAN
SELECT DISTINCT c.id, c.name
FROM   customer c
INNER  JOIN order_header oh ON oh.customer_id = c.id
INNER  JOIN order_detail od ON od.order_id    = oh.id
INNER  JOIN menu m          ON m.id           = od.menu_id
WHERE  m.name = '아메리카노'
ORDER  BY c.id;

EXPLAIN QUERY PLAN
SELECT id, name FROM customer
WHERE  id IN (SELECT oh.customer_id FROM order_header oh
              JOIN order_detail od ON od.order_id = oh.id
              JOIN menu m ON m.id = od.menu_id
              WHERE m.name = '아메리카노')
ORDER BY id;

EXPLAIN QUERY PLAN
SELECT c.id, c.name FROM customer c
WHERE  EXISTS (SELECT 1 FROM order_header oh
               JOIN order_detail od ON od.order_id = oh.id
               JOIN menu m ON m.id = od.menu_id
               WHERE oh.customer_id = c.id AND m.name = '아메리카노')
ORDER BY c.id;

-- ---------------------------------------------------------------------
-- 차이 요약 (위 실행계획 실측 결과 기준)
--
--   * 결과 집합은 세 방식 모두 동일하다 (김민준·이서연·박지호·정우진 4명).
--
--   * JOIN 방식만 임시 자료구조를 두 번 만든다:
--       USE TEMP B-TREE FOR DISTINCT
--       USE TEMP B-TREE FOR ORDER BY
--     order_detail 을 스캔하며 조인해 만든 중복 행을 나중에 DISTINCT 로 걷어내야 하고,
--     그 과정에서 정렬 순서도 흐트러지기 때문이다.
--     -> "SQLite 가 두 형태를 어차피 비슷하게 바꾼다"는 통념은 이 케이스에선 사실이 아니다.
--
--   * IN 서브쿼리는 LIST SUBQUERY 로 customer_id 목록을 한 번 만든 뒤
--     customer 를 PK 로 SEARCH 한다. 중복이 목록 단계에서 사라져 DISTINCT 가 불필요하다.
--
--   * EXISTS 는 고객마다 "있냐/없냐"만 확인하고 조기 종료한다.
--     한 고객이 같은 메뉴를 100번 주문해도 첫 번째 행에서 멈춘다.
--
--   * 그럼 언제 뭘 쓰나:
--       - 주문일시·수량 같은 '자식 쪽 컬럼'을 결과에 함께 보여줘야 한다  -> JOIN (다른 선택지가 없다)
--       - 부모 컬럼만 필요하고 '존재 여부'로 거르는 게 목적이다          -> EXISTS / IN
--       - 자식 목록이 아주 크다                                          -> EXISTS (조기 종료 이점)
--   * 주의: NOT IN 은 서브쿼리 결과에 NULL 이 하나라도 섞이면 전체가 빈 결과가 된다.
--     반대로 NOT EXISTS 는 NULL 에 안전하다. 부정 조건에서는 EXISTS 계열이 더 안전하다.
-- ---------------------------------------------------------------------

-- =====================================================================
-- (2) 데이터 정합성 깨뜨려 보기
--     아래 네 문장은 '일부러' 실패한다. 에러가 나는 것이 정상 동작이다.
-- =====================================================================

-- >> (2-a) FK 위반 : customer 에 없는 999번을 참조
--   기대 에러: FOREIGN KEY constraint failed
--   왜 막히나: order_header.customer_id 는 customer.id 를 참조하는 외래 키다.
--             부모 테이블에 실재하지 않는 값을 자식이 가리키면 '고아 데이터'가 되므로 DB가 거부한다.
INSERT INTO order_header (customer_id, status) VALUES (999, 'PENDING');

-- >> (2-b) UNIQUE 위반 : 이미 존재하는 이메일로 가입 시도
--   기대 에러: UNIQUE constraint failed: customer.email
INSERT INTO customer (name, email) VALUES ('중복이', 'minjun@example.com');

-- >> (2-c) CHECK 위반 : 정의되지 않은 주문 상태
--   기대 에러: CHECK constraint failed
--   status 는 CHECK (status IN ('PENDING','COMPLETED','CANCELLED')) 로 허용값이 고정되어 있다.
INSERT INTO order_header (customer_id, status) VALUES (1, 'DONE');

-- >> (2-d) NOT NULL 위반 : 필수 컬럼 누락
--   기대 에러: NOT NULL constraint failed: customer.email
INSERT INTO customer (name, email) VALUES ('이메일없음', NULL);

-- ---------------------------------------------------------------------
-- >> (2-e) 올바른 해결법 : 부모를 먼저 만들고 그 id 를 참조한다
--   트랜잭션으로 감싸고 ROLLBACK 해서 실험이 실제 데이터를 오염시키지 않게 한다.
--   BEGIN ~ ROLLBACK 사이의 변경은 전부 없던 일이 된다 (원자성).
-- ---------------------------------------------------------------------
BEGIN;

-- ① 부모(customer) 를 먼저 INSERT
INSERT INTO customer (name, email, phone, joined_at)
VALUES ('신규고객', 'newbie@example.com', '010-9999-0000', '2026-05-11');

-- ② 방금 만들어진 id 를 참조해 자식(order_header) INSERT -> 이번엔 성공한다
INSERT INTO order_header (customer_id, order_date, status)
VALUES ((SELECT id FROM customer WHERE email = 'newbie@example.com'),
        '2026-05-11 10:00:00', 'PENDING');

-- ③ 실험 결과 확인 (트랜잭션 안에서는 보인다)
SELECT c.name, oh.id AS order_id, oh.status
FROM   customer c
JOIN   order_header oh ON oh.customer_id = c.id
WHERE  c.email = 'newbie@example.com';

ROLLBACK;

-- ④ 롤백 후 확인 - 신규고객도 그 주문도 남아 있지 않다 (둘 다 0 이어야 정상)
SELECT (SELECT COUNT(*) FROM customer     WHERE email = 'newbie@example.com') AS customer_left,
       (SELECT COUNT(*) FROM order_header WHERE status = 'PENDING'
                                            AND order_date = '2026-05-11 10:00:00') AS order_left;

-- =====================================================================
-- (3) 미니 리포트 - 핵심 지표 3개
--     ★ '매출' 의 정의: status = 'COMPLETED' 만 집계한다.
--       CANCELLED 는 당연히 제외이고, PENDING 은 아직 결제되지 않았으므로 매출이 아니다.
--       (status <> 'CANCELLED' 로 쓰면 미결제 주문 3,500원이 매출에 섞여 들어간다.)
-- =====================================================================

-- ---------------------------------------------------------------------
-- >> 지표 1) 일자별 매출 추이
--   "어느 날짜에 얼마가 들어왔는지" - 가장 기본적인 매출 시계열
-- [SQLite 전용] DATE(...) 로 'YYYY-MM-DD HH:MM:SS' 에서 날짜 부분만 자른다.
--   MySQL 도 DATE() 가 있지만 PostgreSQL 은 CAST(order_date AS DATE) 를 쓴다.
-- ※ order_date 의 DEFAULT CURRENT_TIMESTAMP 는 UTC 기준이라, 실서비스라면
--   DATE(order_date,'localtime') 처럼 시간대를 맞춰야 날짜 경계가 어긋나지 않는다.
-- ---------------------------------------------------------------------
SELECT  DATE(oh.order_date) AS sales_date,
        SUM(od.quantity * od.unit_price) AS daily_revenue,
        COUNT(DISTINCT oh.id)            AS order_count
FROM    order_header oh
JOIN    order_detail od ON od.order_id = oh.id
WHERE   oh.status = 'COMPLETED'
GROUP   BY DATE(oh.order_date)
ORDER   BY sales_date;

-- ---------------------------------------------------------------------
-- >> 지표 2) 인기 메뉴 TOP 5 (수량 기준)
--   재고/프로모션 의사결정에 직결되는 가장 많이 팔린 메뉴
--   동점이 있으므로 total_sales, menu_id 로 tie-break 해 순서를 고정한다.
-- ---------------------------------------------------------------------
SELECT  m.name AS menu_name,
        SUM(od.quantity)                  AS total_qty,
        SUM(od.quantity * od.unit_price)  AS total_sales
FROM    order_detail od
JOIN    menu m          ON m.id  = od.menu_id
JOIN    order_header oh ON oh.id = od.order_id
WHERE   oh.status = 'COMPLETED'
GROUP   BY m.id, m.name
ORDER   BY total_qty DESC, total_sales DESC, m.id
LIMIT 5;

-- ---------------------------------------------------------------------
-- >> 지표 3) VIP 고객 TOP 3 (결제 금액 기준)
--   재방문 유도 마케팅 대상 선정에 사용
--   INNER JOIN 이므로 결제 이력이 없는 고객은 애초에 후보에서 빠진다(랭킹의 의도와 일치).
-- ---------------------------------------------------------------------
SELECT  c.name,
        COUNT(DISTINCT oh.id)            AS order_count,
        SUM(od.quantity * od.unit_price) AS total_paid
FROM    customer c
INNER   JOIN order_header oh ON oh.customer_id = c.id
INNER   JOIN order_detail od ON od.order_id    = oh.id
WHERE   oh.status = 'COMPLETED'
GROUP   BY c.id, c.name
ORDER   BY total_paid DESC, c.id
LIMIT 3;
