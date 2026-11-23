"""하루마켓 모의 주문 API (교재 4장과 6장 실습용)

강사가 실행해 두는 서버다. 학생은 이 파일을 읽지 않아도 된다.
Python 표준 라이브러리만 사용하므로 별도 설치가 필요 없다.

환경 변수
  MOCK_API_KEY  : 조회 전용 키. 요청 헤더 X-API-Key 로 받는다. 비어 있으면 서버가 시작하지 않는다
  MOCK_EXEC_KEY : 집행 키. 환불과 교환 발송에만 쓴다. 비어 있으면 서버가 시작하지 않는다
  MOCK_TODAY    : 날짜 계산의 기준일(YYYY-MM-DD). 기본값 2026-09-10
  MOCK_STATE_DIR: 집행 기록을 남길 폴더. 기본값 /app/state
  PORT          : 기본값 8000

엔드포인트(조회 키 필요)
  GET /orders/{order_id}
  GET /orders/{order_id}/exchange-eligibility?option=...

엔드포인트(집행 키 필요, 6장에서 더했다)
  POST /orders/{order_id}/refund      본문 {"request_id": "...", "amount": 33000}
  POST /orders/{order_id}/exchange    본문 {"request_id": "...", "option": "L"}

  두 엔드포인트는 request_id 로 중복 집행을 막는다. 같은 request_id 로 다시 오면
  새로 집행하지 않고 처음 집행의 결과를 그대로 돌려주며 repeated 를 true 로 표시한다.
  조회 키로 부르면 403 을 돌려준다.

엔드포인트(인증 없음)
  GET /health
  GET /practice/geocoding/v1/search?name=...          외부망이 막혔을 때 쓰는 대체 경로
  GET /practice/forecast/v1/forecast?latitude=...     외부망이 막혔을 때 쓰는 대체 경로
  GET /practice/frankfurter/v2/rate/{base}/{quote}    외부망이 막혔을 때 쓰는 대체 경로
"""

import csv
import datetime as dt
import json
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

API_KEY = os.environ.get("MOCK_API_KEY", "").strip()
EXEC_KEY = os.environ.get("MOCK_EXEC_KEY", "").strip()
TODAY = dt.date.fromisoformat(os.environ.get("MOCK_TODAY", "2026-09-10").strip())
PORT = int(os.environ.get("PORT", "8000"))
STATE_DIR = Path(os.environ.get("MOCK_STATE_DIR", "/app/state"))
STATE_PATH = STATE_DIR / "executions.json"

ORDER_ID_PATTERN = re.compile(r"^O-[0-9]{4}$")
REQUEST_ID_PATTERN = re.compile(r"^APV-[0-9]{4,}$")

# 집행 기록. request_id 를 열쇠로 삼아 같은 요청이 두 번 집행되지 않게 한다.
EXECUTIONS = {}
EXEC_LOCK = threading.Lock()


def load_executions():
    """서버를 다시 시작해도 집행 기록이 남아 있어야 중복을 막을 수 있다."""
    if not STATE_PATH.exists():
        return {}
    try:
        with STATE_PATH.open(encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_executions():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(EXECUTIONS, f, ensure_ascii=False, indent=2)
    tmp.replace(STATE_PATH)


def next_execution_id(prefix):
    used = [v["execution_id"] for v in EXECUTIONS.values() if v["execution_id"].startswith(prefix)]
    return "%s-%04d" % (prefix, len(used) + 1)


# ---------------------------------------------------------------------------
# 데이터 읽기
# ---------------------------------------------------------------------------

def read_csv(name):
    with open(DATA_DIR / name, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def read_holidays():
    path = DATA_DIR / "holidays.txt"
    days = set()
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                days.add(dt.date.fromisoformat(line))
    return days


ORDERS = {row["order_id"]: row for row in read_csv("orders.csv")}
STOCK = read_csv("stock.csv")
HOLIDAYS = read_holidays()


def parse_date(value):
    value = (value or "").strip()
    return dt.date.fromisoformat(value) if value else None


def to_iso(day):
    return day.isoformat() if day else None


# ---------------------------------------------------------------------------
# 영업일 계산: 토요일, 일요일, holidays.txt의 날짜를 뺀다
# ---------------------------------------------------------------------------

def is_business_day(day):
    return day.weekday() < 5 and day not in HOLIDAYS


def add_business_days(start, count):
    day = start
    added = 0
    while added < count:
        day += dt.timedelta(days=1)
        if is_business_day(day):
            added += 1
    return day


def business_days_between(start, end):
    """start 다음 날부터 end까지(end 포함) 영업일 수"""
    count = 0
    day = start
    while day < end:
        day += dt.timedelta(days=1)
        if is_business_day(day):
            count += 1
    return count


# ---------------------------------------------------------------------------
# 응답 만들기
# ---------------------------------------------------------------------------

def shipping_info(order):
    status = order["order_status"]
    if status in ("paid", "preparing"):
        ordered = parse_date(order["ordered_at"])
        ship_from = add_business_days(ordered, 1)
        ship_to = add_business_days(ordered, 2)
        return {
            "expected_ship_from": to_iso(ship_from),
            "expected_ship_to": to_iso(ship_to),
            "ship_overdue": TODAY > ship_to,
        }
    if status == "shipped":
        shipped = parse_date(order["shipped_at"])
        days = business_days_between(shipped, TODAY)
        return {
            "business_days_since_shipped": days,
            "expected_delivery_from": to_iso(add_business_days(shipped, 1)),
            "expected_delivery_to": to_iso(add_business_days(shipped, 3)),
            "delay_check_required": days > 5,
        }
    return None


def order_body(order):
    return {
        "order_id": order["order_id"],
        "customer_name": order["customer_name"],
        "product_name": order["product_name"],
        "option": order["option"],
        "quantity": int(order["quantity"]),
        "amount": int(order["amount"]),
        "order_status": order["order_status"],
        "ordered_at": order["ordered_at"] or None,
        "shipped_at": order["shipped_at"] or None,
        "delivered_at": order["delivered_at"] or None,
        "shipping": shipping_info(order),
        "as_of": TODAY.isoformat(),
    }


def normalize_option(value):
    return " ".join((value or "").split())


def exchange_body(order, requested):
    options = [
        {"option": row["option"], "stock": int(row["stock"])}
        for row in STOCK
        if row["product_name"] == order["product_name"]
    ]
    stock_by_option = {item["option"]: item["stock"] for item in options}

    delivered = parse_date(order["delivered_at"])
    reasons = []

    if order["order_status"] != "delivered" or delivered is None:
        reasons.append("not_delivered")
        days = None
        deadline = None
        within = False
    else:
        days = (TODAY - delivered).days
        deadline = delivered + dt.timedelta(days=7)
        within = days <= 7
        if not within:
            reasons.append("period_expired")

    offered = requested in stock_by_option
    stock = stock_by_option.get(requested)

    if requested == order["option"]:
        reasons.append("same_option")
    elif not offered:
        reasons.append("option_not_offered")
    elif stock == 0:
        reasons.append("out_of_stock")

    return {
        "order_id": order["order_id"],
        "customer_name": order["customer_name"],
        "product_name": order["product_name"],
        "current_option": order["option"],
        "requested_option": requested,
        "eligible": not reasons,
        "reasons": reasons,
        "checks": {
            "order_status": order["order_status"],
            "delivered_at": order["delivered_at"] or None,
            "days_since_delivery": days,
            "exchange_deadline": to_iso(deadline),
            "within_period": within,
            "same_product_option": offered,
            "stock": stock,
            "stock_checked_at": f"{TODAY.isoformat()}T09:00:00+09:00",
        },
        "available_options": options,
        "as_of": TODAY.isoformat(),
    }


def error_body(code, message):
    return {"error": {"code": code, "message": message}}


# ---------------------------------------------------------------------------
# 외부망이 막힌 환경에서 주제 실습에 쓰는 대체 응답
# 실제 서비스와 같은 모양으로 고정된 값을 돌려준다
# ---------------------------------------------------------------------------

PRACTICE_CITIES = {
    "서울": ("서울특별시", 37.566, 126.9784, "KR", "대한민국", "Asia/Seoul"),
    "seoul": ("서울특별시", 37.566, 126.9784, "KR", "대한민국", "Asia/Seoul"),
    "도쿄": ("도쿄", 35.6895, 139.69171, "JP", "일본", "Asia/Tokyo"),
    "tokyo": ("도쿄", 35.6895, 139.69171, "JP", "일본", "Asia/Tokyo"),
    "오사카": ("오사카 시", 34.69379, 135.50107, "JP", "일본", "Asia/Tokyo"),
    "osaka": ("오사카 시", 34.69379, 135.50107, "JP", "일본", "Asia/Tokyo"),
}

PRACTICE_RATES = {("KRW", "JPY"): 0.1138, ("KRW", "USD"): 0.00072, ("KRW", "EUR"): 0.00062}


def practice_geocoding(query):
    name = (query.get("name", [""])[0]).strip()
    city = PRACTICE_CITIES.get(name.lower())
    if not name:
        return 400, {"error": True, "reason": "Parameter 'name' is required"}
    if city is None:
        return 200, {"generationtime_ms": 0.1}
    label, lat, lon, code, country, tz = city
    return 200, {
        "results": [{
            "name": label, "latitude": lat, "longitude": lon,
            "country_code": code, "country": country, "timezone": tz,
        }],
        "generationtime_ms": 0.1,
    }


def practice_forecast(query):
    if "latitude" not in query or "longitude" not in query:
        return 400, {"error": True, "reason": "Parameter 'latitude' and 'longitude' must have the same number of elements"}
    days = min(int(query.get("forecast_days", ["7"])[0] or 7), 16)
    start = dt.date.today()
    dates = [(start + dt.timedelta(days=i)).isoformat() for i in range(days)]
    rain = [(i * 37) % 100 for i in range(days)]
    t_max = [24.0 + (i % 4) for i in range(days)]
    t_min = [16.0 + (i % 3) for i in range(days)]
    return 200, {
        "latitude": float(query["latitude"][0]),
        "longitude": float(query["longitude"][0]),
        "timezone": query.get("timezone", ["GMT"])[0],
        "daily_units": {
            "time": "iso8601", "precipitation_probability_max": "%",
            "temperature_2m_max": "°C", "temperature_2m_min": "°C",
        },
        "daily": {
            "time": dates, "precipitation_probability_max": rain,
            "temperature_2m_max": t_max, "temperature_2m_min": t_min,
        },
    }


def practice_rate(base, quote):
    base, quote = base.upper(), quote.upper()
    rate = PRACTICE_RATES.get((base, quote))
    if rate is None:
        return 422, {"status": 422, "message": f"invalid currency: {quote}"}
    return 200, {"date": dt.date.today().isoformat(), "base": base, "quote": quote, "rate": rate}


# ---------------------------------------------------------------------------
# HTTP 처리
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "HarumarketMockAPI/1.0"

    def send_json(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_json_body(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return None
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None

    def do_POST(self):
        """6장에서 더한 집행 엔드포인트. 조회와 달리 주문 데이터를 바꾼다."""
        url = urlparse(self.path)
        parts = [unquote(p) for p in url.path.split("/") if p]

        if len(parts) != 3 or parts[0] != "orders" or parts[2] not in ("refund", "exchange"):
            return self.send_json(404, error_body("NOT_FOUND", "없는 경로입니다."))

        # 인증과 권한을 먼저 본다. 조회 키로 집행을 부르면 401이 아니라 403이다.
        # 키는 맞지만 이 작업을 할 권한이 없다는 뜻을 구분해서 알린다.
        key = self.headers.get("X-API-Key", "")
        if key == API_KEY:
            return self.send_json(403, error_body("FORBIDDEN", "이 키에는 집행 권한이 없습니다. 집행 키를 사용하세요."))
        if key != EXEC_KEY:
            return self.send_json(401, error_body("INVALID_API_KEY", "API 키가 없거나 올바르지 않습니다."))

        order_id = parts[1]
        action = parts[2]

        if not ORDER_ID_PATTERN.match(order_id):
            return self.send_json(400, error_body("INVALID_ORDER_ID", "주문번호는 O- 뒤에 숫자 네 자리입니다."))

        body = self.read_json_body()
        if not isinstance(body, dict):
            return self.send_json(400, error_body("INVALID_BODY", "본문이 JSON 객체가 아닙니다."))

        request_id = str(body.get("request_id", "")).strip()
        if not REQUEST_ID_PATTERN.match(request_id):
            return self.send_json(400, error_body("INVALID_REQUEST_ID", "request_id는 APV- 뒤에 숫자 네 자리 이상입니다."))

        with EXEC_LOCK:
            # 같은 request_id 로 다시 오면 새로 집행하지 않는다.
            # 응답이 유실되어 워크플로우가 다시 보낸 경우가 여기에 해당한다.
            done = EXECUTIONS.get(request_id)
            if done is not None:
                if done["action"] != action or done["order_id"] != order_id:
                    return self.send_json(409, error_body("REQUEST_ID_CONFLICT", "같은 request_id가 다른 요청에 이미 쓰였습니다."))
                repeated = dict(done)
                repeated["repeated"] = True
                return self.send_json(200, repeated)

            order = ORDERS.get(order_id)
            if order is None:
                return self.send_json(404, error_body("ORDER_NOT_FOUND", "주문을 찾을 수 없습니다."))

            result = {
                "request_id": request_id,
                "order_id": order_id,
                "action": action,
                "executed_at": dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).isoformat(timespec="seconds"),
                "repeated": False,
            }

            if action == "refund":
                amount = body.get("amount")
                if not isinstance(amount, int) or amount <= 0:
                    return self.send_json(400, error_body("INVALID_AMOUNT", "amount는 0보다 큰 정수여야 합니다."))
                if amount > int(order["amount"]):
                    return self.send_json(400, error_body("AMOUNT_TOO_LARGE", "환불 금액이 주문 금액보다 큽니다."))
                result["execution_id"] = next_execution_id("RFD")
                result["amount"] = amount
            else:
                option = normalize_option(str(body.get("option", "")))
                if not option:
                    return self.send_json(400, error_body("OPTION_REQUIRED", "교환할 옵션(option)을 적어야 합니다."))
                result["execution_id"] = next_execution_id("EXG")
                result["option"] = option

            EXECUTIONS[request_id] = result
            save_executions()
            return self.send_json(200, dict(result))

    def do_GET(self):
        url = urlparse(self.path)
        parts = [unquote(p) for p in url.path.split("/") if p]
        query = parse_qs(url.query, keep_blank_values=True)

        if parts == ["health"]:
            return self.send_json(200, {"status": "ok", "as_of": TODAY.isoformat(), "executions": len(EXECUTIONS)})

        if parts[:1] == ["practice"]:
            if parts[1:] == ["geocoding", "v1", "search"]:
                return self.send_json(*practice_geocoding(query))
            if parts[1:] == ["forecast", "v1", "forecast"]:
                return self.send_json(*practice_forecast(query))
            if len(parts) == 6 and parts[1:4] == ["frankfurter", "v2", "rate"]:
                return self.send_json(*practice_rate(parts[4], parts[5]))
            return self.send_json(404, error_body("NOT_FOUND", "없는 경로입니다."))

        if parts[:1] != ["orders"] or len(parts) not in (2, 3):
            return self.send_json(404, error_body("NOT_FOUND", "없는 경로입니다."))

        # 인증은 다른 어떤 검사보다 먼저 한다. 키가 틀리면 주문의 존재 여부도 알려 주지 않는다.
        if self.headers.get("X-API-Key", "") != API_KEY:
            return self.send_json(401, error_body("INVALID_API_KEY", "API 키가 없거나 올바르지 않습니다."))

        order_id = parts[1]
        if not ORDER_ID_PATTERN.match(order_id):
            return self.send_json(400, error_body("INVALID_ORDER_ID", "주문번호는 O- 뒤에 숫자 네 자리입니다."))

        if len(parts) == 3 and parts[2] != "exchange-eligibility":
            return self.send_json(404, error_body("NOT_FOUND", "없는 경로입니다."))

        requested = None
        if len(parts) == 3:
            requested = normalize_option(query.get("option", [""])[0])
            if not requested:
                return self.send_json(400, error_body("OPTION_REQUIRED", "교환할 옵션(option)을 적어야 합니다."))

        order = ORDERS.get(order_id)
        if order is None:
            return self.send_json(404, error_body("ORDER_NOT_FOUND", "주문을 찾을 수 없습니다."))

        if requested is None:
            return self.send_json(200, order_body(order))
        return self.send_json(200, exchange_body(order, requested))

    def log_message(self, fmt, *args):
        sys.stdout.write("%s %s\n" % (self.log_date_time_string(), fmt % args))


def main():
    if not API_KEY:
        sys.exit("MOCK_API_KEY 환경 변수가 비어 있습니다. .env 파일을 확인하세요.")
    if not EXEC_KEY:
        sys.exit("MOCK_EXEC_KEY 환경 변수가 비어 있습니다. .env 파일을 확인하세요.")
    if API_KEY == EXEC_KEY:
        sys.exit("MOCK_API_KEY와 MOCK_EXEC_KEY가 같습니다. 조회 키와 집행 키는 달라야 합니다.")
    EXECUTIONS.update(load_executions())
    print(f"하루마켓 모의 API 시작: 포트 {PORT}, 기준일 {TODAY.isoformat()}, 집행 기록 {len(EXECUTIONS)}건", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
