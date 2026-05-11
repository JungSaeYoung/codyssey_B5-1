.headers on
.mode box
PRAGMA foreign_keys = ON;
.print
.print ====================================================================
.print [BONUS 1-a] '아메리카노' 주문 고객 - JOIN 방식
.print ====================================================================
SELECT DISTINCT c.id, c.name
FROM   customer c
INNER  JOIN order_header oh ON oh.customer_id = c.id
INNER  JOIN order_detail od ON od.order_id    = oh.id
INNER  JOIN menu m          ON m.id           = od.menu_id
WHERE  m.name = '아메리카노'
ORDER  BY c.id;

.print
.print ====================================================================
.print [BONUS 1-b] '아메리카노' 주문 고객 - 서브쿼리(IN) 방식
.print ====================================================================
SELECT id, name FROM customer
WHERE  id IN (
    SELECT oh.customer_id FROM order_header oh
    JOIN order_detail od ON od.order_id = oh.id
    JOIN menu m ON m.id = od.menu_id
    WHERE m.name = '아메리카노'
)
ORDER BY id;

.print
.print ====================================================================
.print [BONUS 2] FK 위반 실험 - 존재하지 않는 customer_id=999 로 주문 INSERT
.print  기대 동작: FOREIGN KEY constraint failed 에러로 차단
.print ====================================================================
.bail off
INSERT INTO order_header (customer_id, status) VALUES (999, 'PENDING');

.print
.print ====================================================================
.print [BONUS 3-1] 일자별 매출 추이 (취소 제외)
.print ====================================================================
SELECT  DATE(oh.order_date) AS sales_date,
        SUM(od.quantity * od.unit_price) AS daily_revenue,
        COUNT(DISTINCT oh.id)            AS order_count
FROM    order_header oh
JOIN    order_detail od ON od.order_id = oh.id
WHERE   oh.status <> 'CANCELLED'
GROUP   BY DATE(oh.order_date)
ORDER   BY sales_date;

.print
.print ====================================================================
.print [BONUS 3-2] 인기 메뉴 TOP 5 (수량 기준)
.print ====================================================================
SELECT  m.name AS menu_name,
        SUM(od.quantity)                  AS total_qty,
        SUM(od.quantity * od.unit_price)  AS total_sales
FROM    order_detail od
JOIN    menu m         ON m.id = od.menu_id
JOIN    order_header oh ON oh.id = od.order_id
WHERE   oh.status <> 'CANCELLED'
GROUP   BY m.id, m.name
ORDER   BY total_qty DESC, total_sales DESC
LIMIT 5;

.print
.print ====================================================================
.print [BONUS 3-3] VIP 고객 TOP 3 (결제 금액 기준)
.print ====================================================================
SELECT  c.name,
        COUNT(DISTINCT oh.id)            AS order_count,
        SUM(od.quantity * od.unit_price) AS total_paid
FROM    customer c
JOIN    order_header oh ON oh.customer_id = c.id
JOIN    order_detail od ON od.order_id    = oh.id
WHERE   oh.status <> 'CANCELLED'
GROUP   BY c.id, c.name
ORDER   BY total_paid DESC
LIMIT 3;
