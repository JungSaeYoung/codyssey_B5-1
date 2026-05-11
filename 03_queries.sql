-- =====================================================================
-- 카페 주문 관리 DB - 핵심 SQL 쿼리 15개
-- 각 쿼리는 "무엇을 확인하는 쿼리인지" 한 줄 설명을 주석으로 붙인다.
-- 범주별 구성:
--   기본 조회 4개 (Q1~Q4)
--   조인 4개   (Q5~Q8)  - INNER JOIN 2개 이상 + LEFT JOIN 1개 포함
--   집계 3개   (Q9~Q11) - COUNT/SUM/AVG + GROUP BY
--   서브쿼리 1개 (Q12)
--   수정/삭제 2개 (Q13, Q14)
--   인덱스 1개 (Q15)
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- [Q1] 기본 조회 - 판매중인 메뉴를 가격이 비싼 순으로 모두 조회
-- ---------------------------------------------------------------------
SELECT id, name, price, category_id
FROM   menu
WHERE  is_available = 1
ORDER  BY price DESC;

-- ---------------------------------------------------------------------
-- [Q2] 기본 조회 - 가격이 5,000원 이상인 메뉴를 비싼 순으로 정렬
-- ---------------------------------------------------------------------
SELECT name, price
FROM   menu
WHERE  price >= 5000
ORDER  BY price DESC;

-- ---------------------------------------------------------------------
-- [Q3] 기본 조회 - 최근에 가입한 고객 TOP 5
-- ---------------------------------------------------------------------
SELECT id, name, email, joined_at
FROM   customer
ORDER  BY joined_at DESC
LIMIT  5;

-- ---------------------------------------------------------------------
-- [Q4] 기본 조회 - 'COMPLETED' 상태 주문을 최신 순으로 10개
-- ---------------------------------------------------------------------
SELECT id, customer_id, order_date, status
FROM   order_header
WHERE  status = 'COMPLETED'
ORDER  BY order_date DESC
LIMIT  10;

-- ---------------------------------------------------------------------
-- [Q5] 조인 (INNER JOIN) - 메뉴와 그 카테고리 이름을 함께 조회
-- ---------------------------------------------------------------------
SELECT m.id, m.name AS menu_name, c.name AS category_name, m.price
FROM   menu m
INNER  JOIN category c ON c.id = m.category_id
ORDER  BY c.name, m.price DESC;

-- ---------------------------------------------------------------------
-- [Q6] 조인 (INNER JOIN, 3개 테이블) - 주문 상세를 고객명, 메뉴명과 함께 조회
-- ---------------------------------------------------------------------
SELECT  oh.id        AS order_id,
        c.name       AS customer_name,
        m.name       AS menu_name,
        od.quantity,
        od.unit_price,
        (od.quantity * od.unit_price) AS line_total
FROM    order_detail od
INNER   JOIN order_header oh ON oh.id = od.order_id
INNER   JOIN customer     c  ON c.id  = oh.customer_id
INNER   JOIN menu         m  ON m.id  = od.menu_id
ORDER   BY oh.id, od.id;

-- ---------------------------------------------------------------------
-- [Q7] 조인 (LEFT JOIN) - 한 번도 주문하지 않은 고객까지 포함해 고객별 주문 수
-- ---------------------------------------------------------------------
SELECT  c.id,
        c.name,
        COUNT(oh.id) AS order_count
FROM    customer c
LEFT    JOIN order_header oh ON oh.customer_id = c.id
GROUP   BY c.id, c.name
ORDER   BY order_count DESC, c.id;

-- ---------------------------------------------------------------------
-- [Q8] 조인 (INNER JOIN + 집계) - 카테고리별 등록 메뉴 개수
-- ---------------------------------------------------------------------
SELECT  c.name AS category_name,
        COUNT(m.id) AS menu_count
FROM    category c
INNER   JOIN menu m ON m.category_id = c.id
GROUP   BY c.id, c.name
ORDER   BY menu_count DESC, c.name;

-- ---------------------------------------------------------------------
-- [Q9] 집계 (COUNT + GROUP BY) - 상태별 주문 건수
-- ---------------------------------------------------------------------
SELECT  status,
        COUNT(*) AS order_count
FROM    order_header
GROUP   BY status
ORDER   BY order_count DESC;

-- ---------------------------------------------------------------------
-- [Q10] 집계 (SUM + GROUP BY) - 고객별 총 결제 금액 (취소 주문 제외)
-- ---------------------------------------------------------------------
SELECT  c.id,
        c.name,
        COALESCE(SUM(od.quantity * od.unit_price), 0) AS total_paid
FROM    customer c
LEFT    JOIN order_header oh ON oh.customer_id = c.id
                            AND oh.status <> 'CANCELLED'
LEFT    JOIN order_detail od ON od.order_id   = oh.id
GROUP   BY c.id, c.name
ORDER   BY total_paid DESC;

-- ---------------------------------------------------------------------
-- [Q11] 집계 (AVG + GROUP BY) - 카테고리별 평균 메뉴 가격
-- ---------------------------------------------------------------------
SELECT  c.name AS category_name,
        ROUND(AVG(m.price), 0) AS avg_price
FROM    category c
INNER   JOIN menu m ON m.category_id = c.id
GROUP   BY c.id, c.name
ORDER   BY avg_price DESC;

-- ---------------------------------------------------------------------
-- [Q12] 서브쿼리 - 전체 메뉴 평균가보다 비싼 메뉴 목록
-- ---------------------------------------------------------------------
SELECT  name, price
FROM    menu
WHERE   price > (SELECT AVG(price) FROM menu)
ORDER   BY price DESC;

-- ---------------------------------------------------------------------
-- [Q13] UPDATE - '아메리카노' 가격을 500원 인상
-- ---------------------------------------------------------------------
UPDATE menu
SET    price = price + 500
WHERE  name = '아메리카노';

-- 적용 결과 확인
SELECT id, name, price FROM menu WHERE name = '아메리카노';

-- ---------------------------------------------------------------------
-- [Q14] DELETE - 'CANCELLED' 상태의 주문 헤더 삭제
--   order_detail 은 ON DELETE CASCADE 로 함께 정리된다.
-- ---------------------------------------------------------------------
DELETE FROM order_header
WHERE  status = 'CANCELLED';

-- 적용 결과 확인 (남아 있는 주문 상태 분포)
SELECT status, COUNT(*) AS cnt FROM order_header GROUP BY status;

-- ---------------------------------------------------------------------
-- [Q15] CREATE INDEX
--   사유: order_header(customer_id) 는 "고객별 주문 조회" (Q7, Q10 등)에서
--         반복적으로 조건/조인 키로 사용된다. 데이터가 늘어날수록 풀스캔 비용이
--         커지므로 단일 컬럼 인덱스를 만들어 조회/조인 성능을 확보한다.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_order_header_customer_id
    ON order_header (customer_id);

-- 인덱스가 실제로 사용되는지 확인
EXPLAIN QUERY PLAN
SELECT * FROM order_header WHERE customer_id = 1;
