"""모의 API 점검 스크립트 (강사용)

server.py를 임시 포트로 직접 실행해 명세의 요청과 응답을 대조한 뒤 서버를 끈다.
Docker 없이 Python만 있으면 된다.

    python check_api.py

컨테이너로 실행 중인 서버를 점검하려면 주소와 키를 넘긴다.

    python check_api.py http://localhost:8000 <MOCK_API_KEY 값>
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent


def request(base, path, key):
    headers = {"X-API-Key": key} if key else {}
    req = urllib.request.Request(base + path, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            return res.status, json.loads(res.read())
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read())


def run_checks(base, key):
    results = []

    def check(name, condition):
        results.append(condition)
        print(("통과  " if condition else "실패  ") + name)

    def get(path, use_key=True, wrong=False):
        return request(base, path, ("wrong-key" if wrong else key) if use_key else None)

    def opt(value):
        return "?option=" + urllib.parse.quote(value)

    s, b = get("/health", use_key=False)
    check("health: 기준일 2026-09-10", s == 200 and b.get("as_of") == "2026-09-10")

    s, b = get("/orders/O-1002")
    check("O-1002: 출고 후 1영업일, 09-10~09-14 도착 예상", s == 200 and b["shipping"] == {
        "business_days_since_shipped": 1, "expected_delivery_from": "2026-09-10",
        "expected_delivery_to": "2026-09-14", "delay_check_required": False})
    s, b = get("/orders/O-1001")
    check("O-1001: 출고 후 6영업일, 지연 조사 대상", b["shipping"]["business_days_since_shipped"] == 6
          and b["shipping"]["delay_check_required"] is True)
    s, b = get("/orders/O-2005")
    check("O-2005: 09-10~09-11 출고 예정", b["shipping"] == {
        "expected_ship_from": "2026-09-10", "expected_ship_to": "2026-09-11", "ship_overdue": False})
    s, b = get("/orders/O-2008")
    check("O-2008: 출고 예정일 지남", b["shipping"]["ship_overdue"] is True)
    s, b = get("/orders/O-2009")
    check("O-2009: 배송 완료면 shipping은 null", b["shipping"] is None)
    s, b = get("/orders/O-9999")
    check("없는 주문: 404 ORDER_NOT_FOUND", s == 404 and b["error"]["code"] == "ORDER_NOT_FOUND")
    s, b = get("/orders/O-12")
    check("형식 오류: 400 INVALID_ORDER_ID", s == 400 and b["error"]["code"] == "INVALID_ORDER_ID")
    s, b = get("/orders/O-1002", wrong=True)
    check("틀린 키: 401 INVALID_API_KEY", s == 401 and b["error"]["code"] == "INVALID_API_KEY")
    s, b = get("/orders/O-9999", use_key=False)
    check("키 없음: 없는 주문이어도 401", s == 401)

    base_ex = "/orders/{}/exchange-eligibility"
    s, b = get(base_ex.format("O-2001") + opt("L"))
    check("E-1 O-2001 L: 교환 가능, 수령 후 4일, 재고 12", b["eligible"] and b["checks"]["days_since_delivery"] == 4
          and b["checks"]["exchange_deadline"] == "2026-09-13" and b["checks"]["stock"] == 12)
    s, b = get(base_ex.format("O-2002") + opt("네이비 M"))
    check("E-2 O-2002 네이비 M: 재고 없음", b["reasons"] == ["out_of_stock"])
    s, b = get(base_ex.format("O-2004") + opt("260"))
    check("E-3 O-2004 260: 기한 초과, 수령 후 13일", b["reasons"] == ["period_expired"])
    s, b = get(base_ex.format("O-2011") + opt("한 치수 큰 것"))
    check("E-4 O-2011 원문 표현: 제공하지 않는 옵션", b["reasons"] == ["option_not_offered"])
    s, b = get(base_ex.format("O-2011") + opt("250"))
    check("E-4 O-2011 250: 교환 가능, 재고 9", b["eligible"] and b["checks"]["stock"] == 9)
    s, b = get(base_ex.format("O-2015") + opt("그래이 엘"))
    check("E-5 O-2015 원문 표현: 제공하지 않는 옵션", b["reasons"] == ["option_not_offered"])
    s, b = get(base_ex.format("O-2015") + opt("그레이 L"))
    check("E-5 O-2015 그레이 L: 교환 가능, 재고 3", b["eligible"] and b["checks"]["stock"] == 3)
    s, b = get(base_ex.format("O-2099") + opt("L"))
    check("E-6 O-2099: 404", s == 404)
    s, b = get(base_ex.format("O-2001") + opt(""))
    check("옵션 없음: 400 OPTION_REQUIRED", s == 400 and b["error"]["code"] == "OPTION_REQUIRED")

    s, b = get("/practice/geocoding/v1/search?name=" + urllib.parse.quote("도쿄"), use_key=False)
    check("대체 경로 지명 검색: 도쿄", s == 200 and b["results"][0]["timezone"] == "Asia/Tokyo")
    s, b = get("/practice/forecast/v1/forecast?latitude=35.6&longitude=139.6&forecast_days=3", use_key=False)
    check("대체 경로 예보: 3일", s == 200 and len(b["daily"]["time"]) == 3)
    s, b = get("/practice/frankfurter/v2/rate/KRW/JPY", use_key=False)
    check("대체 경로 환율: KRW/JPY", s == 200 and b["quote"] == "JPY")

    print(f"\n{sum(results)} / {len(results)} 통과")
    return all(results)


def main():
    if len(sys.argv) == 3:
        sys.exit(0 if run_checks(sys.argv[1].rstrip("/"), sys.argv[2]) else 1)

    port, key = "8765", "check-key"
    env = dict(os.environ, MOCK_API_KEY=key, PORT=port, MOCK_TODAY="2026-09-10")
    server = subprocess.Popen([sys.executable, str(HERE / "server.py")], env=env)
    try:
        time.sleep(1.5)
        ok = run_checks(f"http://127.0.0.1:{port}", key)
    finally:
        server.terminate()
        server.wait(timeout=5)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
