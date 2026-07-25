-- =====================================================================
-- 카페 주문 관리 DB - 핵심 SQL 쿼리 15개 (+ 대조/보강 쿼리 6개)
-- 각 쿼리는 "무엇을 확인하는 쿼리인지" 한 줄 설명을 주석으로 붙인다.
--
-- 범주별 구성 (미션 요구 대비):
--   기본 조회 4개 (Q1~Q4)      - WHERE / ORDER BY / LIMIT 포함
--   조인 4개     (Q5~Q8)      - INNER JOIN 3개 + LEFT JOIN 1개
--   집계 3개     (Q9~Q11)     - COUNT / SUM / AVG + GROUP BY
--   서브쿼리 1개 (Q12)
--   수정/삭제 2개 (Q13, Q14)
--   인덱스 1개   (Q15)
--   ------------------------------------------------------------------
--   보강 (번호에 -B) : Q4-B 검색(LIKE), Q7-B COUNT 함정 대조,
--                      Q8-B INNER vs LEFT 대조, Q10-B 0원의 두 종류 구분,
--                      Q11-B HAVING, Q15-A/B 인덱스 적용 전후 실행계획
--
-- ★ 실행 순서 주의: Q13(UPDATE) / Q14(DELETE) 는 DB 상태를 실제로 바꾼다.
--   04_bonus.sql 은 '취소 주문이 살아 있는 상태'를 전제로 하므로 이 파일보다 먼저 실행해야 한다.
--
-- [이 파일의 DB 고유 문법]
--   EXPLAIN QUERY PLAN - SQLite 전용 (MySQL/PostgreSQL 은 EXPLAIN / EXPLAIN ANALYZE)
--   PRAGMA             - SQLite 전용
--   CREATE INDEX IF NOT EXISTS / DROP INDEX IF EXISTS - SQLite·PostgreSQL 지원, MySQL 8.0 은 미지원
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- >> [Q1] 기본 조회 - 판매중인 메뉴를 가격이 비싼 순으로 모두 조회
--   기준: is_available = 1 (품절 제외). "지금 손님에게 보여줄 메뉴판"이 목적이다.
--   ORDER BY 에 id 를 덧붙인 이유: 5000원 동점(바닐라라떼/초콜릿라떼)이 있어
--   tie-break 가 없으면 실행할 때마다 행 순서가 달라질 수 있고 캡처가 재현되지 않는다.
-- ---------------------------------------------------------------------
SELECT id, name, price, category_id
FROM   menu
WHERE  is_available = 1
ORDER  BY price DESC, id;

-- ---------------------------------------------------------------------
-- >> [Q2] 기본 조회 - 가격이 5,000원 이상인 메뉴를 비싼 순으로 정렬 (품절 포함)
--   Q1 과 달리 is_available 조건이 없다. 목적이 '메뉴판'이 아니라
--   '가격대 분석(품절 메뉴도 원가/가격 검토 대상)' 이기 때문이다.
--   -> 같은 파일 안에서 기준이 엇갈리지 않도록 의도를 명시해 둔다.
-- ---------------------------------------------------------------------
SELECT name, price, is_available
FROM   menu
WHERE  price >= 5000
ORDER  BY price DESC, id;

-- ---------------------------------------------------------------------
-- >> [Q3] 기본 조회 - 최근에 가입한 고객 TOP 5
--   joined_at 은 TEXT 'YYYY-MM-DD' 로 저장되지만 이 포맷은 사전순 정렬 = 날짜순 정렬이라
--   문자열 비교만으로 올바르게 정렬된다. (01_schema.sql 의 컬럼 주석 참고)
-- ---------------------------------------------------------------------
SELECT id, name, email, joined_at
FROM   customer
ORDER  BY joined_at DESC, id DESC
LIMIT  5;

-- ---------------------------------------------------------------------
-- >> [Q4] 기본 조회 - 'COMPLETED' 상태 주문을 최신 순으로 10개
--   현재 데이터에서 COMPLETED 는 9건이라 LIMIT 10 이 실제로 자르는 행은 없다.
--   데이터가 늘어났을 때 한 화면 분량만 끊어 오는 페이징의 형태를 보여주는 것이 목적이다.
-- ---------------------------------------------------------------------
SELECT id, customer_id, order_date, status
FROM   order_header
WHERE  status = 'COMPLETED'
ORDER  BY order_date DESC
LIMIT  10;

-- ---------------------------------------------------------------------
-- >> [Q4-B] 기본 조회(검색) - 메뉴 이름에 '라떼'가 들어가는 메뉴 부분일치 검색
--   실무의 '검색창'에 해당한다. = 는 완전일치라 '카페라떼'를 '라떼'로 찾을 수 없다.
--   LIKE 의 % 는 0글자 이상 아무 문자열. 앞에 % 가 붙으면 인덱스를 쓸 수 없어 풀스캔이 된다
--   (그래서 대량 데이터의 텍스트 검색은 보통 전용 검색엔진/FTS 를 쓴다).
-- ---------------------------------------------------------------------
SELECT id, name, price
FROM   menu
WHERE  name LIKE '%라떼%'
ORDER  BY price DESC, id;

-- ---------------------------------------------------------------------
-- >> [Q5] 조인 (INNER JOIN) - 메뉴와 그 카테고리 이름을 함께 조회
--   menu 에는 category_id 라는 숫자만 있다. 사람이 읽을 이름은 category 테이블에 있으므로
--   두 테이블을 키로 연결해야 한 줄로 볼 수 있다. = 정규화의 대가를 JOIN 으로 치르는 것.
-- ---------------------------------------------------------------------
SELECT m.id, m.name AS menu_name, c.name AS category_name, m.price
FROM   menu m
INNER  JOIN category c ON c.id = m.category_id
ORDER  BY c.name, m.price DESC, m.id;

-- ---------------------------------------------------------------------
-- >> [Q6] 조인 (INNER JOIN, 4개 테이블) - 주문 상세를 고객명, 메뉴명과 함께 조회
--   order_detail 을 기준(FROM)으로 잡고 부모들을 끌어온다. 이 방향이 자연스러운 이유:
--   결과의 한 행 = 주문 상세 한 줄 이므로, 가장 세밀한 테이블이 기준이 되어야 행이 부풀지 않는다.
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
-- >> [Q7] 조인 (LEFT JOIN) - 한 번도 주문하지 않은 고객까지 포함해 고객별 주문 수
--   ★ COUNT(oh.id) 를 쓴 이유 (COUNT(*) 를 쓰면 안 되는 이유):
--     LEFT JOIN 은 짝이 없는 왼쪽 행도 남기면서 오른쪽 컬럼을 전부 NULL 로 채운다.
--     COUNT(*)     -> '행'을 세므로 NULL 로 채워진 그 한 줄까지 세어 서지안이 1 이 된다.
--     COUNT(oh.id) -> '컬럼의 NULL 아닌 값'만 세므로 서지안이 정확히 0 이 된다.
--     실측 비교는 바로 아래 Q7-B 참고.
-- ---------------------------------------------------------------------
SELECT  c.id,
        c.name,
        COUNT(oh.id) AS order_count
FROM    customer c
LEFT    JOIN order_header oh ON oh.customer_id = c.id
GROUP   BY c.id, c.name
ORDER   BY order_count DESC, c.id;

-- ---------------------------------------------------------------------
-- >> [Q7-B] 대조 - COUNT(*) 와 COUNT(컬럼) 을 한 줄에 놓고 차이를 눈으로 확인
--   주문이 0건인 서지안(id=10)만 두 값이 1 과 0 으로 갈린다. 나머지 고객은 값이 같다.
-- ---------------------------------------------------------------------
SELECT  c.id,
        c.name,
        COUNT(*)        AS cnt_star,      -- 행을 센다 (NULL 로 채워진 행도 1)
        COUNT(oh.id)    AS cnt_column,    -- NULL 아닌 값을 센다 (정답)
        CASE WHEN COUNT(*) <> COUNT(oh.id) THEN '<== 차이 발생' ELSE '' END AS note
FROM    customer c
LEFT    JOIN order_header oh ON oh.customer_id = c.id
GROUP   BY c.id, c.name
ORDER   BY c.id;

-- ---------------------------------------------------------------------
-- >> [Q8] 조인 (INNER JOIN + 집계) - 카테고리별 등록 메뉴 개수
--   결과는 9행. 카테고리는 10개인데 메뉴가 0개인 '굿즈'가 통째로 사라진다.
--   INNER JOIN 은 '양쪽에 짝이 있는 행'만 남기기 때문이다.
-- ---------------------------------------------------------------------
SELECT  c.name AS category_name,
        COUNT(m.id) AS menu_count
FROM    category c
INNER   JOIN menu m ON m.category_id = c.id
GROUP   BY c.id, c.name
ORDER   BY menu_count DESC, c.name;

-- ---------------------------------------------------------------------
-- >> [Q8-B] 대조 (LEFT JOIN) - Q8 과 '같은 요구'를 LEFT JOIN 으로 풀어 차이를 확인
--   Q8(INNER) = 9행  : 메뉴 0개인 '굿즈'가 결과에서 소멸
--   Q8-B(LEFT) = 10행 : '굿즈'가 menu_count = 0 으로 보존
--   -> "재고가 0인 카테고리를 찾고 싶다" 같은 요구는 INNER JOIN 으로는 아예 답이 안 나온다.
-- ---------------------------------------------------------------------
SELECT  c.name AS category_name,
        COUNT(m.id) AS menu_count
FROM    category c
LEFT    JOIN menu m ON m.category_id = c.id
GROUP   BY c.id, c.name
ORDER   BY menu_count DESC, c.name;

-- ---------------------------------------------------------------------
-- >> [Q9] 집계 (COUNT + GROUP BY) - 상태별 주문 건수
--   GROUP BY 는 같은 status 값을 가진 행들을 한 바구니로 묶고,
--   COUNT(*) 는 그 바구니 안의 행 수를 센다. 결과 행 수 = 서로 다른 status 값의 개수.
-- ---------------------------------------------------------------------
SELECT  status,
        COUNT(*) AS order_count
FROM    order_header
GROUP   BY status
ORDER   BY order_count DESC, status;

-- ---------------------------------------------------------------------
-- >> [Q10] 집계 (SUM + GROUP BY) - 고객별 총 결제 금액
--   ★ 설계 판단 1 - '결제 금액'의 정의: status = 'COMPLETED' 만 센다.
--     PENDING 은 아직 결제되지 않은 주문이라 매출로 잡으면 안 된다.
--     (실제로 order_id=9 이서연의 PENDING 3,500원이 여기서 제외된다.)
--   ★ 설계 판단 2 - status 필터를 WHERE 가 아니라 LEFT JOIN 의 ON 절에 둔 이유:
--     ON  절 필터 -> "조건에 맞는 주문만 붙여라". 짝이 없어도 왼쪽 고객 행은 남는다 (10행).
--     WHERE 절 필터 -> 조인이 끝난 뒤 걸러내는데, NULL 은 어떤 비교에도 참이 되지 않아
--                      주문 없는 고객이 통째로 탈락한다 = 사실상 INNER JOIN (7행).
--     실측: ON 절 10행 / WHERE 절 7행 (박지호·윤하늘·서지안 소멸)
--   ★ COALESCE : SUM 은 대상 행이 하나도 없으면 0 이 아니라 NULL 을 반환하므로 0 으로 바꿔준다.
-- ---------------------------------------------------------------------
SELECT  c.id,
        c.name,
        COALESCE(SUM(od.quantity * od.unit_price), 0) AS total_paid
FROM    customer c
LEFT    JOIN order_header oh ON oh.customer_id = c.id
                            AND oh.status = 'COMPLETED'
LEFT    JOIN order_detail od ON od.order_id   = oh.id
GROUP   BY c.id, c.name
ORDER   BY total_paid DESC, c.id;

-- ---------------------------------------------------------------------
-- >> [Q10-B] 보강 - '0원'의 두 종류를 구분해서 보여준다
--   Q10 은 박지호(취소만 함) / 윤하늘(취소만 함) / 서지안(주문 자체가 없음) 을 모두 0원으로 뭉갠다.
--   마케팅 관점에서 셋은 완전히 다른 고객이므로 주문 이력 자체를 함께 센다.
-- ---------------------------------------------------------------------
SELECT  c.id,
        c.name,
        COUNT(DISTINCT oh.id)                                                   AS orders_total,
        COUNT(DISTINCT CASE WHEN oh.status = 'COMPLETED' THEN oh.id END)        AS orders_completed,
        COUNT(DISTINCT CASE WHEN oh.status = 'CANCELLED' THEN oh.id END)        AS orders_cancelled,
        CASE
            WHEN COUNT(oh.id) = 0                                          THEN '주문 이력 없음'
            WHEN COUNT(CASE WHEN oh.status = 'COMPLETED' THEN 1 END) = 0    THEN '주문했으나 결제 완료 0건'
            ELSE                                                                '결제 이력 있음'
        END AS segment
FROM    customer c
LEFT    JOIN order_header oh ON oh.customer_id = c.id
GROUP   BY c.id, c.name
ORDER   BY c.id;

-- ---------------------------------------------------------------------
-- >> [Q11] 집계 (AVG + GROUP BY) - 카테고리별 평균 메뉴 가격
--   ROUND() 는 REAL(실수)을 반환해 '4333.0' 처럼 원 단위에 소수점이 남는다.
--   금액은 정수이므로 CAST(... AS INTEGER) 로 정수형으로 되돌린다.
--   ROUND 를 먼저 하고 CAST 하는 이유: CAST 만 쓰면 반올림이 아니라 버림이 된다.
-- ---------------------------------------------------------------------
SELECT  c.name AS category_name,
        CAST(ROUND(AVG(m.price)) AS INTEGER) AS avg_price
FROM    category c
INNER   JOIN menu m ON m.category_id = c.id
GROUP   BY c.id, c.name
ORDER   BY avg_price DESC, c.name;

-- ---------------------------------------------------------------------
-- >> [Q11-B] 집계 (GROUP BY + HAVING) - 메뉴를 2개 이상 보유한 카테고리만
--   ★ WHERE 와 HAVING 의 차이:
--     WHERE  는 '묶기 전에' 개별 행을 거른다 -> 집계 함수를 쓸 수 없다.
--     HAVING 은 '묶은 뒤에' 그룹을 거른다   -> COUNT/SUM 같은 집계 결과로 조건을 걸 수 있다.
--   아래 쿼리에서 WHERE 는 4000원 이상 메뉴만 골라 바구니에 담고,
--   HAVING 은 그렇게 담긴 바구니 중 2개 이상인 것만 남긴다.
-- ---------------------------------------------------------------------
SELECT  c.name AS category_name,
        COUNT(m.id) AS menu_count,
        SUM(m.price) AS price_sum
FROM    category c
INNER   JOIN menu m ON m.category_id = c.id
WHERE   m.price >= 4000            -- 묶기 전 필터 (행 단위)
GROUP   BY c.id, c.name
HAVING  COUNT(m.id) >= 2           -- 묶은 뒤 필터 (그룹 단위)
ORDER   BY menu_count DESC, c.name;

-- ---------------------------------------------------------------------
-- >> [Q12] 서브쿼리 - 판매중인 메뉴 중 '판매중 메뉴 평균가'보다 비싼 메뉴 목록
--   서브쿼리가 먼저 1행 1열(스칼라)의 평균값을 계산하고, 바깥 쿼리가 그 값과 각 행을 비교한다.
--   ★ 기준선과 대상 모두 is_available = 1 로 통일했다.
--     품절 메뉴(에그샌드위치 6800)를 평균에 넣으면 '지금 파는 메뉴의 비싼 편'이라는
--     질문의 의도와 기준선이 어긋나기 때문이다.
--   ★ 이 쿼리는 Q13(UPDATE) 보다 앞에 있어야 한다. 뒤로 가면 인상된 가격이 평균에 반영된다.
-- ---------------------------------------------------------------------
SELECT  name, price
FROM    menu
WHERE   is_available = 1
  AND   price > (SELECT AVG(price) FROM menu WHERE is_available = 1)
ORDER   BY price DESC, id;

-- ---------------------------------------------------------------------
-- >> [Q13] UPDATE - '아메리카노' 판매가를 4,000원으로 조정
--   ★ 멱등(idempotent)하게 절대값을 대입한다.
--     price = price + 500 으로 쓰면 스크립트를 두 번 돌릴 때 4500, 세 번이면 5000 이 되어
--     캡처한 결과가 재현되지 않는다 (실측: 3500 -> 4000 -> 4500 -> 5000).
--     절대값 대입은 몇 번을 실행해도 항상 4000 이다.
--   ★ WHERE 에 name 을 쓸 수 있는 이유: menu.name 에 UNIQUE 를 걸어 두어 반드시 1행만 맞는다.
--   ※ 과거 주문 금액은 order_detail.unit_price 스냅샷이라 이 UPDATE 의 영향을 받지 않는다.
-- ---------------------------------------------------------------------
UPDATE menu
SET    price = 4000
WHERE  name = '아메리카노';

-- 적용 결과 확인
SELECT id, name, price FROM menu WHERE name = '아메리카노';

-- ---------------------------------------------------------------------
-- >> [Q14] DELETE - 'CANCELLED' 상태의 주문 헤더 삭제
--   order_detail 은 ON DELETE CASCADE 로 함께 정리된다 (20행 -> 18행).
--   ★ 이 DELETE 는 되돌릴 수 없고 후속 쿼리 결과를 바꾼다.
--     예: 박지호의 유일한 주문이 취소건이라, 이 시점 이후 '아메리카노를 주문한 고객'(04_bonus.sql)
--         목록에서 박지호가 사라진다. 그래서 보너스는 반드시 이 파일보다 먼저 실행한다.
-- ---------------------------------------------------------------------
DELETE FROM order_header
WHERE  status = 'CANCELLED';

-- 적용 결과 확인 (남아 있는 주문 상태 분포 + CASCADE 로 함께 지워진 상세 행 수)
SELECT status, COUNT(*) AS cnt FROM order_header GROUP BY status ORDER BY status;
SELECT COUNT(*) AS order_detail_rows FROM order_detail;

-- ---------------------------------------------------------------------
-- >> [Q15-A] 인덱스 적용 '전' 실행계획 (대조군)
--   재현성을 위해 인덱스를 먼저 지우고 기준선을 잡는다.
--   SCAN = 테이블을 처음부터 끝까지 훑는 풀스캔.
-- [SQLite 전용] EXPLAIN QUERY PLAN / DROP INDEX IF EXISTS
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_order_header_customer_id;
DROP INDEX IF EXISTS idx_order_detail_order_id;

EXPLAIN QUERY PLAN
SELECT * FROM order_header WHERE customer_id = 1;
-- 기대: SCAN order_header

EXPLAIN QUERY PLAN
SELECT * FROM order_detail WHERE order_id = 1;
-- 기대: SCAN order_detail

-- ---------------------------------------------------------------------
-- >> [Q15] CREATE INDEX
--   사유 1) order_header(customer_id) : "고객별 주문 조회"(Q7, Q10)에서 반복적으로
--           조인 키이자 검색 조건으로 쓰인다. 데이터가 늘수록 풀스캔 비용이 선형으로 커진다.
--   사유 2) order_detail(order_id)    : FK 이면서 ON DELETE CASCADE 대상이다.
--           부모 주문을 지울 때마다 "이 주문에 딸린 상세가 뭐냐"를 찾아야 하는데,
--           인덱스가 없으면 부모 1행 삭제마다 자식 테이블 전체를 훑는다
--           (Q14 의 DELETE 실행계획에 SCAN order_detail 로 드러난다).
--   ※ 인덱스는 조회를 빠르게 하는 대신 INSERT/UPDATE/DELETE 때 함께 갱신되는 비용이 있다.
--     그래서 '자주 조건/조인 키로 쓰이는 컬럼'에만 선별적으로 건다.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_order_header_customer_id
    ON order_header (customer_id);

CREATE INDEX IF NOT EXISTS idx_order_detail_order_id
    ON order_detail (order_id);

-- ---------------------------------------------------------------------
-- >> [Q15-B] 인덱스 적용 '후' 실행계획 - Q15-A 와 비교하면 SCAN -> SEARCH 로 바뀐다
-- ---------------------------------------------------------------------
EXPLAIN QUERY PLAN
SELECT * FROM order_header WHERE customer_id = 1;
-- 기대: SEARCH order_header USING INDEX idx_order_header_customer_id (customer_id=?)

EXPLAIN QUERY PLAN
SELECT * FROM order_detail WHERE order_id = 1;
-- 기대: SEARCH order_detail USING INDEX idx_order_detail_order_id (order_id=?)

-- 현재 DB에 존재하는 인덱스 전체 목록
--   UNIQUE 제약(customer.email, category.name, menu.name)은 SQLite 가 sqlite_autoindex_* 를
--   자동 생성한다. 유일성을 매번 확인하려면 결국 인덱스가 필요하기 때문이다.
--   즉 이 DB의 인덱스는 "직접 만든 2개 + UNIQUE 가 만든 3개" 로 총 5개다.
SELECT name AS index_name,
       tbl_name AS table_name,
       CASE WHEN name LIKE 'sqlite_autoindex%' THEN 'UNIQUE 제약이 자동 생성' ELSE '직접 생성' END AS created_by
FROM   sqlite_master
WHERE  type = 'index'
ORDER  BY tbl_name, index_name;
