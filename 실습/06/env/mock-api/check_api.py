"""모의 API 점검 스크립트 (강사용)

server.py를 임시 포트로 직접 실행해 명세의 요청과 응답을 대조한 뒤 서버를 끈다.
Docker 없이 Python만 있으면 된다.

    python check_api.py

컨테이너로 실행 중인 서버를 점검하려면 주소와 두 키를 넘긴다.

    python check_api.py http://localhost:8000 <MOCK_API_KEY 값> <MOCK_EXEC_KEY 값>

6장 집행 점검은 서버에 집행 기록을 남긴다. 실행 중인 서버를 점검했다면
점검이 쓴 request_id(APV-9001, APV-9002)가 기록에 남는다는 점에 주의한다.
실습 전에는 집행 기록 볼륨을 지우고 시작한다(README 참고).
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent


def request(base, path, key, body=None):
    headers = {"X-API-Key": key} if key else {}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, headers=headers, data=data, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            return res.status, json.loads(res.read())
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read())


def run_checks(base, key, exec_key):
    results = []

    def check(name, condition):
        results.append(condition)
        print(("통과  " if condition else "실패  ") + name)

    def get(path, use_key=True, wrong=False):
        return request(base, path, ("wrong-key" if wrong else key) if use_key else None)

    def post(path, body, which="exec"):
        sent = {"exec": exec_key, "read": key, "none": None, "wrong": "wrong-key"}[which]
        return request(base, path, sent, body)

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

    # --- 6장 집행 엔드포인트 ---
    refund = "/orders/O-1004/refund"
    body1 = {"request_id": "APV-9001", "amount": 33000}

    s, b = post(refund, body1, "read")
    check("집행: 조회 키로 환불 요청은 403 FORBIDDEN", s == 403 and b["error"]["code"] == "FORBIDDEN")
    s, b = post(refund, body1, "none")
    check("집행: 키 없이 환불 요청은 401", s == 401 and b["error"]["code"] == "INVALID_API_KEY")
    s, b = request(base, "/orders/O-1004", exec_key)
    check("집행: 집행 키로 주문 조회는 401", s == 401 and b["error"]["code"] == "INVALID_API_KEY")

    s, b = post(refund, {"request_id": "9001", "amount": 1000})
    check("집행: request_id 형식 위반은 400", s == 400 and b["error"]["code"] == "INVALID_REQUEST_ID")
    s, b = post(refund, {"request_id": "APV-9003", "amount": 39001})
    check("집행: 주문 금액 초과는 400 AMOUNT_TOO_LARGE", s == 400 and b["error"]["code"] == "AMOUNT_TOO_LARGE")

    s, b = post(refund, body1)
    first_id = b.get("execution_id")
    check("집행: 집행 키로 환불 200, RFD- 집행 번호, repeated=false",
          s == 200 and str(first_id).startswith("RFD-") and b["repeated"] is False and b["amount"] == 33000)
    s, b = post(refund, body1)
    check("집행: 같은 request_id 반복은 같은 집행 번호에 repeated=true",
          s == 200 and b["execution_id"] == first_id and b["repeated"] is True)
    s, b = post("/orders/O-2001/exchange", {"request_id": "APV-9001", "option": "블루/L"})
    check("집행: 쓰인 request_id를 다른 주문에 쓰면 409", s == 409 and b["error"]["code"] == "REQUEST_ID_CONFLICT")

    s, b = post("/orders/O-2001/exchange", {"request_id": "APV-9002", "option": "블루/L"})
    check("집행: 교환 발송 200, EXG- 집행 번호",
          s == 200 and str(b.get("execution_id")).startswith("EXG-") and b["option"] == "블루/L")
    s, b = post("/orders/O-9999/refund", {"request_id": "APV-9004", "amount": 1000})
    check("집행: 없는 주문은 404 ORDER_NOT_FOUND", s == 404 and b["error"]["code"] == "ORDER_NOT_FOUND")

    s, b = get("/health", use_key=False)
    check("집행: health의 executions가 2건 이상", s == 200 and b.get("executions", 0) >= 2)

    print(f"\n{sum(results)} / {len(results)} 통과")
    return all(results)


def main():
    if len(sys.argv) == 4:
        sys.exit(0 if run_checks(sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3]) else 1)
    if len(sys.argv) == 3:
        sys.exit("6장부터는 집행 키도 넘겨야 한다: python check_api.py <주소> <조회 키> <집행 키>")

    port, key, exec_key = "8765", "check-key", "check-exec-key"
    # 집행 기록은 임시 폴더에 남긴다. 점검할 때마다 빈 상태에서 시작해야
    # 중복 집행 항목(repeated=false로 시작하는지)을 확인할 수 있다.
    with tempfile.TemporaryDirectory() as state:
        env = dict(os.environ, MOCK_API_KEY=key, MOCK_EXEC_KEY=exec_key, PORT=port,
                   MOCK_TODAY="2026-09-10", MOCK_STATE_DIR=state)
        server = subprocess.Popen([sys.executable, str(HERE / "server.py")], env=env)
        try:
            time.sleep(1.5)
            ok = run_checks(f"http://127.0.0.1:{port}", key, exec_key)
        finally:
            server.terminate()
            server.wait(timeout=5)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
