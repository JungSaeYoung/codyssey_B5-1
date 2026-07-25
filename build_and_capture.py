#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
카페 주문 관리 DB - 빌드 & 결과 캡처 스크립트

이 스크립트 하나가 다음을 순서대로 수행한다.

    1) cafe.db 를 지우고 01_schema.sql + 02_data.sql 로 새로 만든다
    2) 04_bonus.sql   -> results/bonus_results.txt
    3) 03_queries.sql -> results/results.txt

★ 왜 보너스를 먼저 캡처하나
   03_queries.sql 의 Q13(UPDATE) / Q14(DELETE) 는 DB 상태를 실제로 바꾼다.
   특히 Q14 는 CANCELLED 주문을 지우는데, 박지호의 유일한 주문이 취소건이라
   이걸 먼저 실행하면 04_bonus.sql (1)의 결과가 4행 -> 3행으로 달라진다.
   그래서 '깨끗한 데이터'를 전제로 하는 보너스를 항상 먼저 캡처한다.

★ 왜 파이썬인가
   sqlite3 CLI 가 설치되어 있지 않은 환경에서도 결과를 재생성할 수 있어야 하기 때문이다.
   (파이썬 표준 라이브러리의 sqlite3 모듈만 쓰므로 추가 설치가 필요 없다.)
   sqlite3 CLI 가 있다면 README '2. 실행 방법' 의 CLI 절차를 그대로 써도 결과는 같다.

★ 단일 진실 원천(single source of truth)
   출력은 제출용 SQL 파일(03_queries.sql / 04_bonus.sql)을 '직접' 읽어서 만든다.
   캡처용 사본을 따로 두지 않으므로 제출 파일과 결과가 어긋날 수 없다.

사용법:
    python build_and_capture.py
"""

import os
import re
import sqlite3
import sys
import unicodedata
from datetime import datetime, timezone

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "cafe.db")
RESULTS_DIR = os.path.join(BASE_DIR, "results")

SCHEMA_SQL = "01_schema.sql"
DATA_SQL = "02_data.sql"
QUERIES_SQL = "03_queries.sql"
BONUS_SQL = "04_bonus.sql"

# 일부러 실패하는 문장이 들어 있는 파일 (에러가 나도 계속 진행한다)
ALLOW_ERRORS = {BONUS_SQL}


# ---------------------------------------------------------------------
# 출력 포맷 - sqlite3 CLI 의 `.mode box` 를 재현한다
# ---------------------------------------------------------------------
def dwidth(text):
    """터미널 표시 폭. 한글/전각 문자는 2칸을 차지한다."""
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in str(text))


def pad(text, width, align="left"):
    text = str(text)
    space = width - dwidth(text)
    if space <= 0:
        return text
    if align == "center":
        left = space // 2
        return " " * left + text + " " * (space - left)
    return text + " " * space


def render_box(headers, rows):
    """헤더는 가운데, 값은 왼쪽 정렬 - sqlite3 .mode box 와 동일한 규칙."""
    cells = [[("" if v is None else str(v)) for v in row] for row in rows]
    widths = [
        max([dwidth(h)] + [dwidth(r[i]) for r in cells]) for i, h in enumerate(headers)
    ]

    def line(left, mid, right):
        return left + mid.join("─" * (w + 2) for w in widths) + right

    out = [line("┌", "┬", "┐")]
    out.append("│ " + " │ ".join(pad(h, widths[i], "center") for i, h in enumerate(headers)) + " │")
    out.append(line("├", "┼", "┤"))
    for r in cells:
        out.append("│ " + " │ ".join(pad(v, widths[i]) for i, v in enumerate(r)) + " │")
    out.append(line("└", "┴", "┘"))
    return "\n".join(out)


def render_query_plan(rows):
    """EXPLAIN QUERY PLAN 은 sqlite3 CLI 처럼 트리 모양으로 출력한다."""
    out = ["QUERY PLAN"]
    for row in rows:
        out.append("`--" + str(row[-1]))
    return "\n".join(out)


# ---------------------------------------------------------------------
# SQL 파일 파싱 - 문장 단위로 자르고, `-- [라벨] 설명` 주석을 섹션 제목으로 쓴다
# ---------------------------------------------------------------------
LABEL_RE = re.compile(r"^--\s*>>\s*(.+)$")


def parse_statements(path):
    """(label, statement) 목록을 돌려준다. label 은 직전에 나온 `-- [..]` 주석."""
    statements = []
    buffer = ""
    pending_label = None
    current_label = None

    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            stripped = raw.strip()

            # 아직 문장을 모으는 중이 아닐 때만 주석에서 라벨을 뽑는다
            if not buffer.strip():
                m = LABEL_RE.match(stripped)
                if m:
                    pending_label = m.group(1).strip()
                    continue
                if stripped.startswith("--") or not stripped:
                    continue

            buffer += raw
            if sqlite3.complete_statement(buffer):
                sql = buffer.strip()
                buffer = ""
                if pending_label is not None:
                    current_label = pending_label
                    pending_label = None
                    statements.append((current_label, sql))
                else:
                    statements.append((None, sql))

    if buffer.strip():
        statements.append((pending_label, buffer.strip()))
    return statements


# ---------------------------------------------------------------------
# 실행 & 캡처
# ---------------------------------------------------------------------
def run_script(con, filename, out_lines, allow_errors=False):
    path = os.path.join(BASE_DIR, filename)
    errors = 0

    for label, sql in parse_statements(path):
        if label:
            out_lines.append("")
            out_lines.append("=" * 70)
            out_lines.append(label)
            out_lines.append("=" * 70)

        cur = con.cursor()
        try:
            cur.execute(sql)
        except sqlite3.Error as exc:
            errors += 1
            out_lines.append(f"Runtime error: {type(exc).__name__}: {exc}")
            if not allow_errors:
                raise
            continue

        if cur.description:  # SELECT / EXPLAIN 계열
            headers = [d[0] for d in cur.description]
            rows = cur.fetchall()
            if not rows:
                out_lines.append("(결과 없음 - 0행)")
            elif sql.lstrip().upper().startswith("EXPLAIN QUERY PLAN"):
                out_lines.append(render_query_plan(rows))
            else:
                out_lines.append(render_box(headers, rows))
        else:  # INSERT / UPDATE / DELETE / DDL
            verb = sql.lstrip().split(None, 1)[0].upper()
            if verb in ("INSERT", "UPDATE", "DELETE"):
                out_lines.append(f"-- {verb} 완료: 변경된 행 {cur.rowcount}개")

    return errors


def build_database():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    # isolation_level=None : 자동 커밋 모드.
    #   BEGIN / ROLLBACK 을 SQL 에 쓴 그대로 동작시키려면 파이썬이 트랜잭션에 개입하면 안 된다.
    con = sqlite3.connect(DB_PATH, isolation_level=None)
    con.execute("PRAGMA foreign_keys = ON")

    for filename in (SCHEMA_SQL, DATA_SQL):
        with open(os.path.join(BASE_DIR, filename), encoding="utf-8") as fh:
            con.executescript(fh.read())
        # executescript 가 트랜잭션을 커밋하면서 PRAGMA 가 초기화될 수 있어 매번 다시 켠다
        con.execute("PRAGMA foreign_keys = ON")

    return con


def header_lines(source_file, con):
    fk = con.execute("PRAGMA foreign_keys").fetchone()[0]
    return [
        "=" * 70,
        f"  소스 파일    : {source_file}",
        f"  생성 시각    : {datetime.now(timezone.utc).astimezone().isoformat(timespec='seconds')}",
        f"  SQLite 버전  : {sqlite3.sqlite_version}",
        f"  Python 버전  : {sys.version.split()[0]} ({sys.platform})",
        f"  foreign_keys : {'ON' if fk else 'OFF'}",
        f"  생성 명령    : python build_and_capture.py",
        "=" * 70,
    ]


def write_capture(con, source_file, out_file, allow_errors):
    lines = header_lines(source_file, con)
    errors = run_script(con, source_file, lines, allow_errors=allow_errors)
    lines.append("")

    path = os.path.join(RESULTS_DIR, out_file)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    return path, errors


def main():
    os.makedirs(RESULTS_DIR, exist_ok=True)

    print("[1/3] cafe.db 재생성 (01_schema.sql + 02_data.sql)")
    con = build_database()
    counts = {
        t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        for t in ("customer", "category", "menu", "order_header", "order_detail")
    }
    print("      행수:", ", ".join(f"{k}={v}" for k, v in counts.items()))

    print("[2/3] 04_bonus.sql -> results/bonus_results.txt  (파괴적 DML 이전 상태에서 캡처)")
    path, errs = write_capture(con, BONUS_SQL, "bonus_results.txt", allow_errors=True)
    print(f"      완료: {path}  (의도된 제약 위반 에러 {errs}건)")

    print("[3/3] 03_queries.sql -> results/results.txt")
    path, _ = write_capture(con, QUERIES_SQL, "results.txt", allow_errors=False)
    print(f"      완료: {path}")

    americano = con.execute("SELECT price FROM menu WHERE name='아메리카노'").fetchone()[0]
    orders = con.execute("SELECT COUNT(*) FROM order_header").fetchone()[0]
    indexes = con.execute(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    ).fetchone()[0]
    con.close()

    print()
    print("커밋되는 cafe.db 최종 상태 (README 3장과 일치해야 함):")
    print(f"  아메리카노 price      = {americano}   (Q13 적용 후)")
    print(f"  order_header 행수     = {orders}    (Q14 로 CANCELLED 2건 삭제됨)")
    print(f"  직접 만든 인덱스 개수 = {indexes}    (Q15)")


if __name__ == "__main__":
    main()
