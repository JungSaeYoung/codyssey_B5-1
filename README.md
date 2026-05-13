# SQL로 만드는 나만의 데이터베이스 — 카페 주문 시스템

코디세이 B5-1 미션 산출물. 백엔드 프레임워크 없이 **SQL만으로** 도메인을 모델링하고, 샘플 데이터를 넣고, 요구사항을 쿼리로 해결하는 흐름 전체를 담았다.

- **DBMS**: SQLite 3 (3.51.2 에서 검증)
- **주제**: 카페 주문 관리
- **테이블 수**: 5개 (요구 4개 이상 충족)
- **1:N 관계**: 4개 (요구 2개 이상 충족)

---

## 1. 디렉터리 구성

```
codyssey_B5-1/
├── 01_schema.sql        # 스키마 생성 (CREATE TABLE, PK/FK/제약조건)
├── 02_data.sql          # 샘플 데이터 INSERT (각 테이블 ≥ 10행)
├── 03_queries.sql       # 핵심 쿼리 15개 (제출용)
├── 04_bonus.sql         # 보너스 과제 3종 (제출용)
├── run_queries.sql      # 결과 캡처용 실행 스크립트 (.mode box / .headers on)
├── run_bonus.sql        # 보너스 결과 캡처용 실행 스크립트
├── results/
│   ├── results.txt      # 15개 쿼리 실행 결과 캡처
│   └── bonus_results.txt# 보너스 실행 결과 (FK 위반 에러 포함)
├── cafe.db              # (재생성 가능) SQLite 데이터 파일
└── README.md
```

---

## 2. 실행 방법

SQLite CLI 가 설치되어 있다면 다음 한 묶음으로 전체 빌드와 결과 캡처가 끝난다.

```bash
# 1) DB 초기화 + 스키마 + 데이터 적재
sqlite3 cafe.db < 01_schema.sql
sqlite3 cafe.db < 02_data.sql

# 2) 15개 쿼리 실행 결과 캡처
sqlite3 cafe.db < run_queries.sql > results/results.txt

# 3) 보너스 실행 결과 캡처
#    FK 위반 실험이 포함되어 있어 종료코드 1 이 정상 (에러 메시지가 기록됨)
sqlite3 cafe.db < run_bonus.sql   > results/bonus_results.txt
```

GUI 도구(DBeaver, DataGrip, TablePlus 등)로도 동일하게 동작한다. 그 경우 `01_schema.sql → 02_data.sql → 03_queries.sql` 순서로 열어 실행하면 된다.

> **주의**: SQLite 는 외래 키 강제 적용이 **연결마다 기본 OFF** 다. 본 프로젝트의 모든 스크립트는 첫 줄에서 `PRAGMA foreign_keys = ON;` 을 켠다. GUI 도구에서 새 연결로 열면 직접 한 번 실행해 줘야 FK 가 동작한다.

---

## 3. 데이터 모델

```
category (1) ────< menu (N)
customer (1) ────< order_header (N) ────< order_detail (N) >──── (1) menu
```

| 테이블 | 역할 | 주요 컬럼 | 제약 |
| --- | --- | --- | --- |
| `category` | 메뉴 카테고리 | `id` (PK), `name` | `UNIQUE(name)` |
| `menu` | 판매 메뉴 | `id` (PK), `name`, `price`, `category_id` (FK), `is_available` | `NOT NULL`, `CHECK(price >= 0)` |
| `customer` | 고객 | `id` (PK), `name`, `email`, `phone`, `joined_at` | `UNIQUE(email)`, `NOT NULL` |
| `order_header` | 주문 헤더 | `id` (PK), `customer_id` (FK), `order_date`, `status` | `CHECK(status IN ('PENDING','COMPLETED','CANCELLED'))` |
| `order_detail` | 주문 라인 | `id` (PK), `order_id` (FK), `menu_id` (FK), `quantity`, `unit_price` | `ON DELETE CASCADE`, `CHECK(quantity > 0)` |

### 설계 포인트
- `order_detail.unit_price` 는 **주문 시점 가격을 스냅샷**으로 저장한다. 이후 `menu.price` 가 바뀌어도 과거 매출은 그대로 보존된다.
- `order_detail` 은 부모(`order_header`) 가 삭제될 때 `ON DELETE CASCADE` 로 함께 정리된다. → 보너스 과제의 "취소 주문 삭제" 시나리오에서 활용.
- `status` 는 `CHECK` 제약으로 허용 값을 강제해 잘못된 상태 문자열을 차단한다.

---

## 4. 핵심 쿼리 15개 (요약)

| # | 범주 | 설명 |
| --- | --- | --- |
| Q1 | 기본 조회 | 판매중인 메뉴를 가격 내림차순으로 조회 |
| Q2 | 기본 조회 | 5,000원 이상 메뉴 비싼 순 |
| Q3 | 기본 조회 | 최근 가입 고객 TOP 5 (`ORDER BY ... LIMIT`) |
| Q4 | 기본 조회 | 'COMPLETED' 주문 최신 10건 (`WHERE` + `ORDER BY` + `LIMIT`) |
| Q5 | INNER JOIN | 메뉴 + 카테고리명 함께 조회 |
| Q6 | INNER JOIN (3테이블) | 주문 상세 + 고객명 + 메뉴명 + 라인 합계 |
| Q7 | LEFT JOIN | 주문이 0건인 고객까지 포함한 고객별 주문 수 |
| Q8 | INNER JOIN + 집계 | 카테고리별 등록 메뉴 개수 |
| Q9 | COUNT + GROUP BY | 상태별 주문 건수 |
| Q10 | SUM + GROUP BY | 고객별 총 결제 금액 (취소 제외) |
| Q11 | AVG + GROUP BY | 카테고리별 평균 메뉴 가격 |
| Q12 | 서브쿼리 | 전체 메뉴 평균가보다 비싼 메뉴 |
| Q13 | UPDATE | '아메리카노' 가격 500원 인상 |
| Q14 | DELETE | 'CANCELLED' 주문 삭제 (`order_detail` CASCADE) |
| Q15 | INDEX | `order_header(customer_id)` 인덱스 + `EXPLAIN QUERY PLAN` 으로 사용 확인 |

> 각 쿼리의 실제 실행 결과는 [results/results.txt](results/results.txt) 에서 박스 포맷으로 확인할 수 있다.

---

## 5. 보너스 과제

[04_bonus.sql](04_bonus.sql) 에 다음 3가지를 담았고, 실행 결과는 [results/bonus_results.txt](results/bonus_results.txt) 에 있다.

1. **같은 요구를 JOIN ↔ 서브쿼리 두 방식으로 풀기**
   "아메리카노를 주문한 고객 목록" 을 INNER JOIN 으로도, `IN (서브쿼리)` 로도 작성해 결과가 동일함을 확인.
2. **데이터 정합성 깨뜨려 보기**
   존재하지 않는 `customer_id = 999` 로 `order_header` INSERT 시도 → `Runtime error ...: FOREIGN KEY constraint failed (19)` 로 차단되는 것을 확인.
3. **미니 리포트 — 핵심 지표 3개**
   - 일자별 매출 추이
   - 인기 메뉴 TOP 5 (수량 기준)
   - VIP 고객 TOP 3 (결제 금액 기준)

---

## 6. 학습 정리 — 과제 목표 답안

### 6.1 DB 가 엑셀과 뭐가 다른가?
엑셀은 셀 단위로 사람이 직접 보는 데 최적화된 도구다. DB 는 **테이블 사이의 "관계"** 를 표현할 수 있고, **제약조건 (PK/FK/UNIQUE/CHECK/NOT NULL)** 으로 잘못된 데이터를 입력 단계에서 차단한다. 예를 들어 이 프로젝트에서 `order_header.customer_id` 는 `customer.id` 를 참조하는 FK 이므로 존재하지 않는 고객 ID 로 주문을 만들 수 없다. 엑셀에서는 그 무결성을 손으로 지켜야 한다.

### 6.2 PK / FK 와 1:N 관계
- **PK (Primary Key)**: 한 행을 유일하게 식별하는 키. 본 프로젝트의 모든 테이블에 `id INTEGER PRIMARY KEY AUTOINCREMENT` 로 정의됨.
- **FK (Foreign Key)**: 다른 테이블의 PK 를 참조하는 컬럼. 데이터가 부모 테이블에 실제로 있어야만 자식 테이블에 들어갈 수 있다.
- **1:N**: 한 행(부모) 이 자식 테이블의 여러 행과 연결되는 관계. 예: `customer` 1명이 여러 `order_header` 를 가질 수 있고, 각 주문은 정확히 1명의 고객에 속한다.

### 6.3 SELECT / INSERT / UPDATE / DELETE
- `SELECT` — 읽기. 가장 자주 쓰임.
- `INSERT` — 새 행 추가.
- `UPDATE` — 기존 행의 값 변경 (`WHERE` 빼먹지 말 것).
- `DELETE` — 행 삭제. FK CASCADE 가 걸려 있으면 자식 행도 함께 사라진다.

### 6.4 JOIN 과 GROUP BY 의 의미
JOIN 은 **여러 테이블을 키로 연결해 한 줄로 합치는 작업**, GROUP BY 는 **같은 카테고리끼리 묶어 집계(COUNT/SUM/AVG) 하는 작업** 이다. Q10 (`고객별 총 결제 금액`) 처럼 거의 항상 함께 쓰인다 — 고객·주문·주문상세를 JOIN 한 뒤 고객으로 GROUP BY 해서 SUM 한다.

### 6.5 인덱스가 왜 필요한가
인덱스가 없으면 DB 는 조건에 맞는 행을 찾기 위해 테이블을 처음부터 끝까지 훑는다(풀스캔). 인덱스를 만들면 책 뒤의 색인처럼 빠르게 위치를 찾을 수 있다. **자주 `WHERE` / `JOIN` 의 키로 쓰이는 컬럼** (예: `order_header.customer_id`) 이 1순위 대상. 단, 인덱스는 쓰기 시 갱신 비용이 있으므로 모든 컬럼에 다는 건 안티패턴이다.

---

## 7. 제약사항 준수 확인

- 백엔드 프레임워크 미사용 — SQL 파일과 SQLite CLI 만 사용.
- 뷰/프로시저/트리거 미사용.
- DB 별 문법 (`AUTOINCREMENT`, `DATE('now')`) 은 해당 라인 주석으로 명시.
- 제출 산출물(스키마/데이터/쿼리/결과 캡처) 모두 위 구성대로 갖춤.
