-- =====================================================================
-- 보너스 과제
-- (1) 조인 vs 서브쿼리 같은 요구를 두 방식으로 풀어 비교
-- (2) 데이터 정합성 깨뜨려 보기 (FK 위반 시도)
-- (3) 미니 리포트 - 이 DB로 뽑을 수 있는 핵심 지표 3개
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- (1) 같은 요구를 JOIN / 서브쿼리 두 방식으로 풀기
--     요구: "아메리카노"를 한 번이라도 주문한 고객 이름 목록
-- ---------------------------------------------------------------------

-- (1-a) JOIN 방식
SELECT DISTINCT c.id, c.name
FROM   customer c
INNER  JOIN order_header oh ON oh.customer_id = c.id
INNER  JOIN order_detail od ON od.order_id    = oh.id
INNER  JOIN menu m          ON m.id           = od.menu_id
WHERE  m.name = '아메리카노'
ORDER  BY c.id;

-- (1-b) 서브쿼리 방식 (IN)
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

-- 차이 요약(주석):
--   * JOIN 방식은 결과 행을 직접 만들기 때문에 SELECT 절에서 주문/메뉴 컬럼을
--     같이 꺼내올 수 있다. 단, DISTINCT 가 필요할 수 있다.
--   * 서브쿼리(IN) 방식은 "필터링"에 집중한 가독성을 가진다. 고객 컬럼만 필요할
--     때 자연스럽고 중복 제거가 따로 필요 없다.
--   * 실행 계획상 SQLite는 두 형태를 비슷한 계획으로 변환하는 경우가 많다.

-- ---------------------------------------------------------------------
-- (2) 데이터 정합성 깨뜨려 보기
--     아래 INSERT 는 일부러 FK 를 위반하도록 작성했다.
--     실행하면 다음과 같이 막힌다:
--       Runtime error near line ...: FOREIGN KEY constraint failed
--     원인: order_header.customer_id = 999 는 customer 테이블에 존재하지 않음
--     올바른 방법: customer 에 먼저 행을 INSERT 한 뒤 그 id 로 참조해야 한다.
-- ---------------------------------------------------------------------
-- 의도적 실패 케이스 (주석 처리 - 직접 실행해보고 싶을 때 주석 해제)
-- INSERT INTO order_header (customer_id, status) VALUES (999, 'PENDING');

-- ---------------------------------------------------------------------
-- (3) 미니 리포트 - 핵심 지표 3개
-- ---------------------------------------------------------------------

-- 지표 1) 일자별 매출 추이 (취소 제외)
--   "어느 날짜에 얼마가 들어왔는지" - 가장 기본적인 매출 시계열
SELECT  DATE(oh.order_date) AS sales_date,
        SUM(od.quantity * od.unit_price) AS daily_revenue,
        COUNT(DISTINCT oh.id)            AS order_count
FROM    order_header oh
JOIN    order_detail od ON od.order_id = oh.id
WHERE   oh.status <> 'CANCELLED'
GROUP   BY DATE(oh.order_date)
ORDER   BY sales_date;

-- 지표 2) 인기 메뉴 TOP 5 (수량 기준)
--   재고/프로모션 의사결정에 직결되는 가장 많이 팔린 메뉴
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

-- 지표 3) 고객 충성도 - 결제 금액 기준 VIP TOP 3
--   재방문 유도 마케팅 대상 선정에 사용
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
