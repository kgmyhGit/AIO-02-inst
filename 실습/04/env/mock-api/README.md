# 하루마켓 모의 주문 API (강사용)

> 4장부터 쓰는 모의 API의 실행과 점검 안내다. 학생에게는 [`모의API_명세.md`](../../configs/모의API_명세.md)만 안내한다.

## 무엇인가

하루마켓의 사내 주문 시스템을 흉내 내는 작은 HTTP 서버다. 2장 `주문목록.csv`, `재고목록.csv`와 같은 데이터를 읽어 주문 정보와 교환 가능 여부를 돌려준다. Python 표준 라이브러리만 쓰므로 이미지를 새로 만들지 않고 공식 Python 이미지로 실행한다.

| 파일 | 내용 |
|---|---|
| `server.py` | 서버 |
| `check_api.py` | 명세대로 응답하는지 점검하는 스크립트 |
| `data/orders.csv` | 주문 29건. 2장 `실습/02/템플릿_가이드/data/주문목록.csv`와 같다 |
| `data/stock.csv` | 옵션별 재고 9행. 2장 `실습/02/템플릿_가이드/data/재고목록.csv`와 같다 |
| `data/holidays.txt` | 영업일 계산에서 뺄 공휴일. 기준일 주변에 공휴일이 없어 비어 있다 |

## 실행

4장 `compose.yml`에 `mock-api` 서비스로 들어 있다. 학생 환경에서는 `docker compose up -d`로 n8n과 함께 실행된다.

- n8n 안에서 부르는 주소: `http://mock-api:8000`
- 내 컴퓨터에서 부르는 주소: `http://localhost:8000`
- 키: `.env`의 `MOCK_API_KEY`. 요청 헤더 `X-API-Key`로 보낸다

컨테이너 없이 서버만 실행하려면 이 폴더에서 다음을 실행한다.

```bash
MOCK_API_KEY=test-key python server.py
```

PowerShell에서는 다음과 같이 실행한다.

```powershell
$env:MOCK_API_KEY = "test-key"; python server.py
```

## 점검

Python만 있으면 서버를 임시로 실행해 점검한다.

```bash
python check_api.py
```

컨테이너로 실행 중인 서버를 점검하려면 주소와 키를 넘긴다.

```bash
python check_api.py http://localhost:8000 <MOCK_API_KEY 값>
```

모든 항목이 통과해야 한다. 22개 항목은 1·2장 사례의 결론(INQ-001 지연 조사, INQ-002 도착 예상일, INQ-101·102·104의 교환 판단 등)과 4장 실습의 시험 사례를 대조한다.

## 기준일

모든 날짜 계산은 `MOCK_TODAY`(기본값 `2026-09-10`)를 오늘로 보고 한다. 실습 사례가 모두 이 날짜의 문의이기 때문이다. 실제 날짜로 계산하면 모든 배송이 지연으로 판정된다. 기준일을 바꾸면 `data/holidays.txt`에 그 기간의 공휴일을 적고, 교재의 시험 사례 기대값이 달라진다는 점에 주의한다.

## 계산 규칙

| 값 | 규칙 | 근거 |
|---|---|---|
| `expected_ship_from`, `expected_ship_to` | 주문일 다음 영업일부터 1~2영업일. 주문일을 결제일로 본다 | 정책 요약 "결제 후 1~2영업일 안에 출고" |
| `ship_overdue` | 기준일이 `expected_ship_to`보다 뒤이고 아직 출고 전 | 교재 가정 |
| `business_days_since_shipped` | 출고일 다음 날부터 기준일까지의 영업일 수 | 정책 요약 |
| `expected_delivery_from`, `expected_delivery_to` | 출고일 다음 영업일부터 1~3영업일 | 정책 요약 "출고 후 통상 1~3영업일" |
| `delay_check_required` | 출고 후 5영업일 초과 | 정책 요약 "출고 후 5영업일이 지나도 delivered가 아니면 지연 조사" |
| `days_since_delivery` | 기준일 − 수령일(달력 날짜) | 1장 실습 1-3의 가정(수령일 다음 날부터 센다) |
| `exchange_deadline` | 수령일 + 7일 | 정책 요약 "수령 후 7일 이내" |

## 이후 장에서 더할 것

6장의 환불·교환 집행 요청과 8장의 장애 주입(429, 500, 시간 초과)은 이 서버에 더한다. 4장 명세에는 조회만 싣는다.
