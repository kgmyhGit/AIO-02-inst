# SQL 확인 문장

> 5장 실습에서 업무 데이터베이스의 테이블을 확인할 때 쓰는 SQL 문과 결과를 읽는 방법이다.
> n8n에서 새 워크플로우 `업무 DB 확인`을 만들고 `Manual Trigger` 뒤에 `Postgres` 노드 하나를 둔다. 자격 증명은 `하루마켓 업무 DB`, Operation은 Execute Query다. 아래 문장을 Query 칸에 하나씩 붙여 넣고 실행한다.
> 이 문서의 문장은 테이블을 **읽기만** 한다. 테이블을 바꾸는 문장은 변경 스크립트, 초기화 스크립트, 5절에만 있다.

## 0. SQL 문을 읽는 법

이 장에서 쓰는 SQL 문은 네 가지 동작과 조건 하나로 읽을 수 있다.

| 동작 | 뜻 | 예 |
|---|---|---|
| `SELECT 열 FROM 테이블` | 테이블에서 열을 골라 읽는다 | `SELECT inquiry_id, message FROM inquiries` |
| `INSERT INTO 테이블 (열) VALUES (값)` | 테이블에 행을 더한다 | 문의 기록 저장 |
| `UPDATE 테이블 SET 열 = 값` | 행의 값을 바꾼다 | 분류 결과 저장 |
| `DELETE FROM 테이블` | 행을 지운다 | 기존 청크 지우기 |
| `WHERE 조건` | 위 동작을 조건에 맞는 행에만 적용한다 | `WHERE order_id = 'O-1004'` |

`ORDER BY 열`은 결과를 그 열의 순서로 늘어놓고, `LIMIT 숫자`는 앞에서부터 그 수만큼만 보여 준다. `count(*)`는 행의 수를 세고, `GROUP BY 열`은 그 열의 값마다 묶어서 센다.

**`UPDATE`와 `DELETE`에서 `WHERE`를 빠뜨리면 테이블의 모든 행이 바뀌거나 지워진다.** 이 문서의 1~4절 문장은 모두 `SELECT`다.

## 1. 업무 기록(실습 5-4, 5-7(가))

### 1-1. 새로 더한 열과 번호 발급 확인

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name IN ('inquiries', 'requests')
ORDER BY table_name, ordinal_position;
```

`inquiries`에 `detected_type`, `flags`가, `requests`에 `handover_reason`, `desired_option`이 있어야 한다. `inquiry_id`와 `request_id`의 `column_default`에 `nextval(...)`이 보이면 번호 발급 규칙이 걸린 것이다.

### 1-2. 새 테이블 세 개 확인

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' ORDER BY table_name;
```

`chat_memory`, `chat_sessions`, `inquiries`, `policy_chunks`, `requests` 다섯 개가 나와야 한다.

### 1-3. 문의 기록

```sql
SELECT inquiry_id, channel, customer_name, order_id, detected_type, flags, request_id, received_at
FROM inquiries
ORDER BY received_at;
```

### 1-4. 요청 기록과 연결된 문의 수

```sql
SELECT r.request_id, r.request_type, r.request_status, r.handover_reason, r.order_id, r.desired_option,
       (SELECT count(*) FROM inquiries i WHERE i.request_id = r.request_id) AS linked_inquiries
FROM requests r
ORDER BY r.request_id;
```

`linked_inquiries`는 그 요청에 연결된 문의 기록의 수다. 처음 문의 한 건을 빼면 재문의 횟수다.

## 2. 정책 청크(실습 5-5, 5-7(나))

### 2-1. 문서별 청크 수

```sql
SELECT metadata->>'group' AS doc_group, metadata->>'doc_id' AS doc_id,
       metadata->>'version' AS version, count(*) AS chunks
FROM policy_chunks
GROUP BY 1, 2, 3
ORDER BY 1, 2;
```

`metadata->>'doc_id'`는 jsonb 열 `metadata` 안의 `doc_id` 값을 글자로 꺼낸다. `GROUP BY 1, 2, 3`은 앞의 세 열이 같은 행끼리 묶는다는 뜻이다. 같은 문서가 두 줄로 나오거나(버전이 다름) 청크 수가 예상의 두 배라면 옛 청크를 지우지 않고 다시 적재한 것이다.

### 2-2. 청크의 글과 메타데이터 한 개씩 보기

```sql
SELECT metadata->>'doc_id' AS doc_id, left(text, 60) AS text_head, metadata
FROM policy_chunks
ORDER BY metadata->>'doc_id'
LIMIT 20;
```

`left(text, 60)`은 청크 글의 앞 60글자만 보여 준다.

### 2-3. 색인 버전과 임베딩 모델

```sql
SELECT metadata->>'group' AS doc_group, metadata->>'index_version' AS index_version,
       metadata->>'embedding_model' AS embedding_model, count(*) AS chunks
FROM policy_chunks
GROUP BY 1, 2, 3;
```

한 묶음에 색인 버전이 두 개 이상 나오면 서로 다른 때 적재한 청크가 섞여 있는 것이다.

### 2-4. 임베딩의 차원

```sql
SELECT metadata->>'doc_id' AS doc_id, vector_dims(embedding) AS dims
FROM policy_chunks
LIMIT 3;
```

`text-embedding-3-large`로 적재했다면 3072가 나온다.

## 3. 세션과 대화 메모리(실습 5-6, 5-7)

### 3-1. 세션 기록

```sql
SELECT session_id, topic, status, turn_count, needs_info_count, handoff_reason, started_at, last_message_at
FROM chat_sessions
ORDER BY last_message_at DESC;
```

### 3-2. 세션별 메모리 행 수

```sql
SELECT session_id, count(*) AS messages, min(created_at) AS first_at, max(created_at) AS last_at
FROM chat_memory
GROUP BY session_id
ORDER BY last_at DESC;
```

한 턴에 몇 행이 쌓이는지 보려면 한 턴을 보낸 뒤와 다음 턴을 보낸 뒤의 `messages`를 비교한다.

### 3-3. 한 세션의 메모리 내용

```sql
SELECT id, message->>'type' AS message_type, left(message::text, 120) AS message_head
FROM chat_memory
WHERE session_id = '여기에-세션-ID'
ORDER BY id;
```

`여기에-세션-ID`를 3-1이나 3-2에서 본 세션 ID로 바꾼다. `message_type`에서 사용자 메시지, 모델의 답, 도구 호출과 도구 결과가 각각 어떤 값으로 저장되는지 확인한다. 저장 모양은 버전에 따라 다를 수 있으므로 `message_head`를 함께 읽는다.

### 3-4. 두 세션에 같은 글이 있는지 찾기(실습 5-7(라))

```sql
SELECT session_id, id, left(message::text, 120) AS message_head
FROM chat_memory
WHERE message::text LIKE '%O-2001%'
ORDER BY session_id, id;
```

사용자 A가 말한 주문번호가 사용자 B의 세션에 나오면 기억이 섞인 것이다.

## 4. 결과를 읽을 때 주의할 점

- 시각은 `+09:00`이 아니라 다른 시간대로 보일 수 있다. 데이터베이스는 같은 시각을 저장하고, 보여 주는 표기만 다르다.
- 편집 화면에서 저장 노드만 따로 실행하면 번호가 하나 발급된다. 번호가 기대와 다르면 실행 목록에서 저장 노드가 몇 번 실행되었는지 먼저 본다.

## 5. 보관 기한이 지난 대화 지우기(참고)

이 장에서는 실행하지 않는다. 대화 메모리를 언제 지울지 정할 때 쓰는 문장의 예다. 자동으로 정해진 때마다 실행하는 방법은 8장에서 다룬다.

```sql
-- 마지막 메시지가 30일 전보다 오래된 세션의 메모리를 지운다. 30일은 예시 값이다.
DELETE FROM chat_memory
WHERE session_id IN (
  SELECT session_id FROM chat_sessions WHERE last_message_at < now() - interval '30 days'
);
```

세션 기록(`chat_sessions`)은 몇 번 물었는지, 누구에게 넘겼는지 같은 업무 상태이므로 메모리보다 오래 남길 수 있다. 무엇을 얼마나 남길지는 업무의 보관 기준이 정한다.

## 6. 처음 상태로 되돌리기

[`업무DB_실습초기화.sql`](../env/업무DB_실습초기화.sql)을 쓴다. [가]는 업무 기록, [나]는 세션과 대화 메모리를 지운다.
