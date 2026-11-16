"""하루마켓 모의 주문 API (교재 4장 실습용)

강사가 실행해 두는 서버다. 학생은 이 파일을 읽지 않아도 된다.
Python 표준 라이브러리만 사용하므로 별도 설치가 필요 없다.

환경 변수
  MOCK_API_KEY : 요청 헤더 X-API-Key 로 받아야 하는 키. 비어 있으면 서버가 시작하지 않는다
  MOCK_TODAY   : 날짜 계산의 기준일(YYYY-MM-DD). 기본값 2026-09-10
  PORT         : 기본값 8000

엔드포인트(인증 필요)
  GET /orders/{order_id}
  GET /orders/{order_id}/exchange-eligibility?option=...

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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

API_KEY = os.environ.get("MOCK_API_KEY", "").strip()
TODAY = dt.date.fromisoformat(os.environ.get("MOCK_TODAY", "2026-09-10").strip())
PORT = int(os.environ.get("PORT", "8000"))

ORDER_ID_PATTERN = re.compile(r"^O-[0-9]{4}$")


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

    def do_GET(self):
        url = urlparse(self.path)
        parts = [unquote(p) for p in url.path.split("/") if p]
        query = parse_qs(url.query, keep_blank_values=True)

        if parts == ["health"]:
            return self.send_json(200, {"status": "ok", "as_of": TODAY.isoformat()})

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
    print(f"하루마켓 모의 API 시작: 포트 {PORT}, 기준일 {TODAY.isoformat()}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
