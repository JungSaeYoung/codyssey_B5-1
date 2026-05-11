.headers on
.mode box
PRAGMA foreign_keys = ON;
.print
.print ====================================================================
.print [Q1] 판매중인 메뉴를 가격이 비싼 순으로 모두 조회
.print ====================================================================
SELECT id, name, price, category_id FROM menu WHERE is_available = 1 ORDER BY price DESC;

.print
.print ====================================================================
.print [Q2] 가격이 5,000원 이상인 메뉴를 비싼 순으로 정렬
.print ====================================================================
SELECT name, price FROM menu WHERE price >= 5000 ORDER BY price DESC;

.print
.print ====================================================================
.print [Q3] 최근에 가입한 고객 TOP 5
.print ====================================================================
SELECT id, name, email, joined_at FROM customer ORDER BY joined_at DESC LIMIT 5;

.print
.print ====================================================================
.print [Q4] 'COMPLETED' 상태 주문을 최신 순으로 10개
.print ====================================================================
SELECT id, customer_id, order_date, status FROM order_header WHERE status = 'COMPLETED' ORDER BY order_date DESC LIMIT 10;

.print
.print ====================================================================
.print [Q5] 메뉴와 카테고리 이름을 함께 조회 (INNER JOIN)
.print ====================================================================
SELECT m.id, m.name AS menu_name, c.name AS category_name, m.price
FROM   menu m INNER JOIN category c ON c.id = m.category_id
ORDER  BY c.name, m.price DESC;

.print
.print ====================================================================
.print [Q6] 주문 상세 + 고객명 + 메뉴명 (3개 테이블 INNER JOIN)
.print ====================================================================
SELECT  oh.id AS order_id, c.name AS customer_name, m.name AS menu_name,
        od.quantity, od.unit_price, (od.quantity * od.unit_price) AS line_total
FROM    order_detail od
INNER   JOIN order_header oh ON oh.id = od.order_id
INNER   JOIN customer     c  ON c.id  = oh.customer_id
INNER   JOIN menu         m  ON m.id  = od.menu_id
ORDER   BY oh.id, od.id;

.print
.print ====================================================================
.print [Q7] 주문 없는 고객까지 포함한 고객별 주문 수 (LEFT JOIN)
.print ====================================================================
SELECT  c.id, c.name, COUNT(oh.id) AS order_count
FROM    customer c
LEFT    JOIN order_header oh ON oh.customer_id = c.id
GROUP   BY c.id, c.name
ORDER   BY order_count DESC, c.id;

.print
.print ====================================================================
.print [Q8] 카테고리별 등록 메뉴 개수 (INNER JOIN + GROUP BY)
.print ====================================================================
SELECT  c.name AS category_name, COUNT(m.id) AS menu_count
FROM    category c INNER JOIN menu m ON m.category_id = c.id
GROUP   BY c.id, c.name
ORDER   BY menu_count DESC, c.name;

.print
.print ====================================================================
.print [Q9] 상태별 주문 건수 (COUNT + GROUP BY)
.print ====================================================================
SELECT status, COUNT(*) AS order_count FROM order_header GROUP BY status ORDER BY order_count DESC;

.print
.print ====================================================================
.print [Q10] 고객별 총 결제 금액 (취소 주문 제외, SUM + GROUP BY)
.print ====================================================================
SELECT  c.id, c.name, COALESCE(SUM(od.quantity * od.unit_price), 0) AS total_paid
FROM    customer c
LEFT    JOIN order_header oh ON oh.customer_id = c.id AND oh.status <> 'CANCELLED'
LEFT    JOIN order_detail od ON od.order_id   = oh.id
GROUP   BY c.id, c.name
ORDER   BY total_paid DESC;

.print
.print ====================================================================
.print [Q11] 카테고리별 평균 메뉴 가격 (AVG + GROUP BY)
.print ====================================================================
SELECT  c.name AS category_name, ROUND(AVG(m.price), 0) AS avg_price
FROM    category c INNER JOIN menu m ON m.category_id = c.id
GROUP   BY c.id, c.name
ORDER   BY avg_price DESC;

.print
.print ====================================================================
.print [Q12] 전체 메뉴 평균가보다 비싼 메뉴 목록 (서브쿼리)
.print ====================================================================
SELECT name, price FROM menu WHERE price > (SELECT AVG(price) FROM menu) ORDER BY price DESC;

.print
.print ====================================================================
.print [Q13] UPDATE - '아메리카노' 가격 500원 인상 후 확인
.print ====================================================================
UPDATE menu SET price = price + 500 WHERE name = '아메리카노';
SELECT id, name, price FROM menu WHERE name = '아메리카노';

.print
.print ====================================================================
.print [Q14] DELETE - 'CANCELLED' 주문 삭제 (order_detail 도 CASCADE 정리)
.print ====================================================================
DELETE FROM order_header WHERE status = 'CANCELLED';
SELECT status, COUNT(*) AS cnt FROM order_header GROUP BY status;

.print
.print ====================================================================
.print [Q15] CREATE INDEX + EXPLAIN QUERY PLAN
.print  사유: order_header(customer_id) 는 고객별 조회/조인에서 반복 사용되는
.print        조건/조인 키이므로 단일 컬럼 인덱스로 풀스캔을 막는다.
.print ====================================================================
CREATE INDEX IF NOT EXISTS idx_order_header_customer_id ON order_header (customer_id);
EXPLAIN QUERY PLAN SELECT * FROM order_header WHERE customer_id = 1;
