# 하루마켓 모의 주문 API (강사용, 6장판)

> 4장부터 쓰는 모의 API의 실행과 점검 안내다. 6장에서 집행 엔드포인트와 두 번째 키를 더했다.
> 학생에게는 [4장 명세](../../../../04/템플릿_가이드/configs/모의API_명세.md)와 [6장 집행 명세](../../configs/모의API_명세_집행.md)만 안내한다.
> 4장 폴더의 서버 대신 이 폴더의 서버를 쓴다. 조회 요청의 동작은 4장과 같다.

## 무엇인가

하루마켓의 사내 주문 시스템을 흉내 내는 작은 HTTP 서버다. 2장 `주문목록.csv`, `재고목록.csv`와 같은 데이터를 읽어 주문 정보와 교환 가능 여부를 돌려주고, 6장부터는 환불과 교환 발송 집행도 받는다. Python 표준 라이브러리만 쓰므로 이미지를 새로 만들지 않고 공식 Python 이미지로 실행한다.

### 6장에서 달라진 것

| 항목 | 4·5장 | 6장 |
|---|---|---|
| 메서드 | `GET`만 받는다 | `POST /orders/{id}/refund`, `POST /orders/{id}/exchange`를 더 받는다 |
| 키 | `MOCK_API_KEY` 하나 | 조회 키와 집행 키(`MOCK_EXEC_KEY`)로 나눈다. 조회 키로 집행을 부르면 403 |
| 상태 | 없다. 요청을 처리하고 잊는다 | 처리한 `request_id`와 집행 결과를 파일에 남긴다 |
| 시작 조건 | `MOCK_API_KEY`만 있으면 된다 | 집행 키가 비어 있거나 조회 키와 같으면 시작하지 않는다 |

| 파일 | 내용 |
|---|---|
| `server.py` | 서버 |
| `check_api.py` | 명세대로 응답하는지 점검하는 스크립트 |
| `data/orders.csv` | 주문 29건. 2장 `실습/02/템플릿_가이드/data/주문목록.csv`와 같다 |
| `data/stock.csv` | 옵션별 재고 9행. 2장 `실습/02/템플릿_가이드/data/재고목록.csv`와 같다 |
| `data/holidays.txt` | 영업일 계산에서 뺄 공휴일. 기준일 주변에 공휴일이 없어 비어 있다 |
| `state/executions.json` | 6장에서 더한 집행 기록. 서버가 만든다. 컨테이너에서는 `mock_state` 볼륨에 들어간다 |
| `state/` | 빈 폴더(`.gitkeep`만 들어 있다). 컨테이너에서는 `mock_state` 볼륨이 이 자리에 연결된다. `mock-api` 폴더는 읽기 전용으로 연결되므로, 이 폴더가 없으면 Docker가 연결할 자리를 만들지 못해 "read-only file system" 오류로 모의 API가 시작하지 않는다. 지우지 않는다 |

## 실행

4장 `compose.yml`에 `mock-api` 서비스로 들어 있다. 학생 환경에서는 `docker compose up -d`로 n8n과 함께 실행된다.

- n8n 안에서 부르는 주소: `http://mock-api:8000`
- 내 컴퓨터에서 부르는 주소: `http://localhost:8000`
- 조회 키: `.env`의 `MOCK_API_KEY`. 요청 헤더 `X-API-Key`로 보낸다
- 집행 키: `.env`의 `MOCK_EXEC_KEY`. 같은 헤더로 보내되 집행 요청에만 쓴다
- 집행 기록 폴더: `MOCK_STATE_DIR`(기본값 `/app/state`). `compose.yml`이 `mock_state` 볼륨을 이 경로에 연결한다

컨테이너 없이 서버만 실행하려면 이 폴더에서 다음을 실행한다.

```bash
MOCK_API_KEY=read-key MOCK_EXEC_KEY=exec-key MOCK_STATE_DIR=./state python server.py
```

PowerShell에서는 다음과 같이 실행한다.

```powershell
$env:MOCK_API_KEY = "read-key"; $env:MOCK_EXEC_KEY = "exec-key"; $env:MOCK_STATE_DIR = "./state"; python server.py
```

두 키를 같은 값으로 주면 서버가 메시지를 남기고 시작하지 않는다. 집행 키를 주지 않아도 마찬가지다. 조회 키와 집행 키가 같으면 6장의 권한 분리 실습이 성립하지 않기 때문이다.

## 점검

Python만 있으면 서버를 임시로 실행해 점검한다.

```bash
python check_api.py
```

컨테이너로 실행 중인 서버를 점검하려면 주소와 키를 넘긴다.

```bash
python check_api.py http://localhost:8000 <MOCK_API_KEY 값>
```

모든 항목이 통과해야 한다. 조회 항목 22개는 1·2장 사례의 결론(INQ-001 지연 조사, INQ-002 도착 예상일, INQ-101·102·104의 교환 판단 등)과 4장 실습의 시험 사례를 대조하고, 6장에서 더한 집행 항목 11개는 아래를 대조한다.

| 집행 점검 항목 | 기대 결과 |
|---|---|
| 조회 키로 환불 집행 | 403 `FORBIDDEN` |
| 키 없이 환불 집행 | 401 `INVALID_API_KEY` |
| 집행 키로 주문 조회 | 401 `INVALID_API_KEY` |
| 집행 키로 환불 집행 | 200, `execution_id`가 `RFD-`로 시작하고 `repeated`가 `false` |
| 같은 `request_id`로 한 번 더 | 200, 같은 `execution_id`에 `repeated`가 `true` |
| 같은 `request_id`로 다른 주문에 집행 | 409 `REQUEST_ID_CONFLICT` |
| 주문 금액보다 큰 환불 | 400 `AMOUNT_TOO_LARGE` |
| `request_id` 형식 위반 | 400 `INVALID_REQUEST_ID` |
| 집행 키로 교환 발송 | 200, `execution_id`가 `EXG-`로 시작 |
| 서버 재시작 뒤 같은 `request_id` | 200, `repeated`가 `true`. 기록이 파일에 남았다는 뜻이다 |

점검 뒤에는 `state/executions.json`을 지우고 실습을 시작한다. 컨테이너에서는 `docker compose down -v`가 아니라 `docker volume rm n8n-textbook_mock_state`로 집행 기록만 지운다. `down -v`는 업무 데이터베이스까지 지운다.

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

## 집행 기록과 기준일

집행 응답의 `executed_at`은 `MOCK_TODAY`가 아니라 **서버가 도는 컴퓨터의 실제 시각**이다. 날짜 계산(배송 일정, 기한)만 기준일을 쓰고, 집행 시각은 실제로 언제 집행했는지를 남기는 값이기 때문이다. 실습에서 요청 기록의 `executed_at`과 대조할 때 이 차이를 염두에 둔다.

## 이후 장에서 더할 것

8장의 장애 주입(429, 500, 시간 초과)은 이 서버에 더한다. 8장은 이 문서의 `request_id` 규칙을 그대로 쓰며, 재시도할 때 같은 식별자를 보내야 중복 집행이 막힌다는 것을 확인한다.
