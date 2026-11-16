# 하루마켓 주문 API 명세

> 교재 4장 실습용 모의 API의 명세다. 하루마켓 사내 주문 시스템을 흉내 낸 가상 서비스이며 실제 서비스가 아니다.
> 이 명세만 보고 n8n에서 호출할 수 있어야 한다. 읽는 순서는 [`API명세_읽기순서.md`](../guides/API명세_읽기순서.md)를 따른다.

## 1. 기본 정보

| 항목 | 내용 |
|---|---|
| **기본 주소** | n8n 안에서 부를 때 `http://mock-api:8000`, 내 컴퓨터의 터미널에서 부를 때 `http://localhost:8000` |
| **인증** | 모든 주문 요청에 `X-API-Key` **헤더**로 API 키를 보낸다. 키는 `.env` 파일의 `MOCK_API_KEY` 값이다 |
| **응답 형식** | JSON(UTF-8) |
| **기준일** | 실제 서비스라면 날짜를 호출한 날 기준으로 계산하고 `as_of`에도 그날 날짜가 들어간다. 이 모의 API는 수업을 언제 하든 교재의 결과와 같은 값이 나오도록 `2026-09-10`을 오늘로 보고 계산하며, 모든 응답의 `as_of`에 이 기준일을 적는다 |
| **메서드** | `GET` 방식. 이 명세의 요청은 모두 조회()다. 주문을 바꾸는 요청은 없다 |

n8n 컨테이너 안에서 `localhost`는 n8n 자기 자신을 가리킨다. 그래서 n8n에서는 서비스 이름인 `mock-api`로 부른다(3장 실습 3-1과 같은 이유).

## 2. 인증

모든 `/orders` 요청은 **다른 검사보다 인증을 먼저** 한다. 키가 없거나 틀리면 주문번호가 맞든 틀리든 401을 돌려준다. 키가 틀린 사람은 주문이 있는지조차 알 수 없어야 하기 때문이다.

```text
X-API-Key: <MOCK_API_KEY 값>
```

## 3. 오류 응답의 형식

주문 요청의 오류는 모두 같은 모양이다.

```json
{
  "error": {
    "code": "ORDER_NOT_FOUND",
    "message": "주문을 찾을 수 없습니다."
  }
}
```

| 상태 코드 | `error.code` | 뜻 | 요청한 쪽이 할 일 |
|---|---|---|---|
| 400 | `INVALID_ORDER_ID` | 주문번호가 `O-` 뒤 숫자 네 자리가 아니다 | 요청을 고친다. 같은 요청을 다시 보내도 결과는 같다 |
| 400 | `OPTION_REQUIRED` | 교환 가능 여부 조회에 `option`이 없거나 비어 있다 | 요청을 고친다 |
| 401 | `INVALID_API_KEY` | 인증키가 없거나 틀렸다 | 자격 증명을 고친다. 다시 시도해도 소용없다 |
| 404 | `ORDER_NOT_FOUND` | 그런 주문이 없다 | 주문번호를 다시 확인한다 |
| 404 | `NOT_FOUND` | 없는 요청 경로다 | 주소를 고친다 |

## 4. 주문 조회

```text
GET /orders/{order_id}
```

주문 한 건의 정보와 배송 일정을 돌려준다.

**요청**

| 위치 | 이름 | 필수 | 형식 | 설명 |
|---|---|---|---|---|
| 경로 | `order_id` | 예 | `O-` 뒤 숫자 네 자리 | 조회할 주문번호 |
| 헤더 | `X-API-Key` | 예 | 문자열 | API 키 |

**성공 응답의 필드**(200)

| 필드 | 데이터 타입 | 설명 |
|---|---|---|
| `order_id` | 문자열 | 주문번호 |
| `customer_name` | 문자열 | 주문자 이름 |
| `product_name` | 문자열 | 상품 이름 |
| `option` | 문자열 | 주문한 옵션 |
| `quantity` | 숫자(정수) | 수량 |
| `amount` | 숫자(정수) | 결제 금액(원) |
| `order_status` | 문자열 | `paid`, `preparing`, `shipped`, `delivered` 중 하나 |
| `ordered_at`, `shipped_at`, `delivered_at` | 문자열(날짜) 또는 `null` | 주문일, 출고일, 수령일. 아직 없으면 `null` |
| `shipping` | 객체 또는 `null` | 배송 일정. 주문 상태에 따라 담기는 값이 다르다(아래 표) |
| `as_of` | 문자열(날짜) | 계산 기준일 |

`shipping`에 **담기는 값**

| 주문 상태 | 필드 | 설명 |
|---|---|---|
| `paid`, `preparing` | `expected_ship_from`, `expected_ship_to` | 출고 예정 기간. 주문일 다음 영업일부터 1~2영업일 |
| | `ship_overdue` | 출고 예정 기간이 지났는데 아직 출고되지 않았으면 `true` |
| `shipped` | `business_days_since_shipped` | 출고일 다음 날부터 기준일까지의 영업일 수 |
| | `expected_delivery_from`, `expected_delivery_to` | 도착 예정 기간. 출고일 다음 영업일부터 1~3영업일 |
| | `delay_check_required` | 출고 후 5영업일이 지났으면 `true`. 배송 지연 조사 대상이다 |
| `delivered` | — | `shipping`이 `null`이다. 수령일은 `delivered_at`에 있다 |

영업일은 토요일, 일요일, 공휴일을 뺀 날이다.

**요청 예**

```bash
curl -H "X-API-Key: <MOCK_API_KEY 값>" http://localhost:8000/orders/O-2005
```

**성공 응답 예**

```json
{
  "order_id": "O-2005",
  "customer_name": "배현우",
  "product_name": "블루투스 스피커",
  "option": "블랙",
  "quantity": 1,
  "amount": 72000,
  "order_status": "preparing",
  "ordered_at": "2026-09-09",
  "shipped_at": null,
  "delivered_at": null,
  "shipping": {
    "expected_ship_from": "2026-09-10",
    "expected_ship_to": "2026-09-11",
    "ship_overdue": false
  },
  "as_of": "2026-09-10"
}
```

**이 API가 하지 않는 일**

- 주문자 이름이 문의한 고객과 같은지는 확인하지 않는다. 사내 시스템용 API라서 키만 맞으면 어떤 주문이든 돌려준다. 고객에게 안내해도 되는지는 호출한 쪽이 판단해야 한다.

## 5. 교환 가능 여부 조회

```text
GET /orders/{order_id}/exchange-eligibility?option={option}
```

주문한 상품을 원하는 옵션으로 교환할 수 있는지와 그 근거를 돌려준다.

**요청**

| 위치 | 이름 | 필수 | 형식 | 설명 |
|---|---|---|---|---|
| 경로 | `order_id` | 예 | `O-` 뒤 숫자 네 자리 | 조회할 주문번호 |
| 쿼리 파라미터 | `option` | 예 | 문자열 | 바꾸고 싶은 옵션. 재고 목록의 표기와 **글자까지 같아야** 한다(예: `그레이 L`, `250`) |
| 헤더 | `X-API-Key` | 예 | 문자열 | API 키 |

**성공 응답의 필드**(200)

| 필드 | 데이터 타입 | 설명 |
|---|---|---|
| `order_id`, `customer_name`, `product_name` | 문자열 | 주문 정보 |
| `current_option` | 문자열 | 지금 받은 옵션 |
| `requested_option` | 문자열 | 요청한 옵션 |
| `eligible` | 불리언 | 교환할 수 있으면 `true` |
| `reasons` | 문자열 배열 | 교환할 수 없는 이유. 교환할 수 있으면 빈 배열 |
| `checks` | 객체 | 판단에 쓴 사실(아래 표) |
| `available_options` | 객체 배열 | 이 상품의 옵션과 재고. 원소마다 `option`, `stock` |
| `as_of` | 문자열(날짜) | 계산 기준일 |

`reasons`의 **값**

| 값 | 뜻 |
|---|---|
| `not_delivered` | 아직 받지 않은 주문이다 |
| `period_expired` | 수령 후 7일이 지났다 |
| `same_option` | 지금 받은 옵션과 같은 옵션을 요청했다 |
| `option_not_offered` | 이 상품에 없는 옵션이다. 표기가 달라도 여기에 해당한다 |
| `out_of_stock` | 있는 옵션이지만 재고가 없다 |

`checks`의 **필드**

| 필드 | 설명 |
|---|---|
| `order_status`, `delivered_at` | 주문 상태와 수령일 |
| `days_since_delivery` | 수령일 다음 날부터 기준일까지의 날짜 수. 받기 전이면 `null` |
| `exchange_deadline` | 교환 신청 기한(수령일 + 7일). 받기 전이면 `null` |
| `within_period` | 기한 안이면 `true` |
| `same_product_option` | 요청한 옵션이 이 상품의 옵션 목록에 있으면 `true` |
| `stock` | 요청한 옵션의 재고. 목록에 없는 옵션이면 `null` |
| `stock_checked_at` | 재고를 확인한 시각 |

같은 상품의 다른 옵션으로만 교환할 수 있다. 다른 상품으로 바꾸는 요청은 이 API로 확인하지 않는다(정책상 반품 후 새로 주문해야 한다).

**요청 예**

```bash
curl -G -H "X-API-Key: <MOCK_API_KEY 값>" --data-urlencode "option=네이비 M" http://localhost:8000/orders/O-2002/exchange-eligibility
```

**성공 응답 예**

```json
{
  "order_id": "O-2002",
  "customer_name": "서유나",
  "product_name": "후드 집업",
  "current_option": "그레이 M",
  "requested_option": "네이비 M",
  "eligible": false,
  "reasons": ["out_of_stock"],
  "checks": {
    "order_status": "delivered",
    "delivered_at": "2026-09-08",
    "days_since_delivery": 2,
    "exchange_deadline": "2026-09-15",
    "within_period": true,
    "same_product_option": true,
    "stock": 0,
    "stock_checked_at": "2026-09-10T09:00:00+09:00"
  },
  "available_options": [
    { "option": "그레이 M", "stock": 5 },
    { "option": "그레이 L", "stock": 3 },
    { "option": "네이비 M", "stock": 0 },
    { "option": "네이비 L", "stock": 4 }
  ],
  "as_of": "2026-09-10"
}
```

**이 API가 하지 않는 일**

- 주문자 이름을 확인하지 않는다(주문 조회와 같다).
- 착용·사용 흔적은 확인하지 않는다. 회수한 뒤 검수에서 확인한다.
- 교환을 신청하거나 재고를 잡아 두지 않는다. 조회만 한다.

## 6. 상태 확인과 대체 경로

| 요청 | 인증 | 용도 |
|---|---|---|
| `GET /health` | 없음 | 서버가 실행 중인지와 기준일을 확인한다 |
| `GET /practice/geocoding/v1/search` | 없음 | 외부망이 막혔을 때 Open-Meteo 지명 검색 대신 쓴다(실습 4-4) |
| `GET /practice/forecast/v1/forecast` | 없음 | 외부망이 막혔을 때 Open-Meteo 예보 대신 쓴다(실습 4-1, 4-4) |
| `GET /practice/frankfurter/v2/rate/{base}/{quote}` | 없음 | 외부망이 막혔을 때 Frankfurter 환율 대신 쓴다(실습 4-4) |

대체 경로는 실제 서비스와 같은 모양의 응답을 고정된 값으로 돌려준다. 지명은 서울, 도쿄, 오사카만, 환율은 원화에서 엔화, 달러, 유로로 바꾸는 경우만 준비되어 있다.
