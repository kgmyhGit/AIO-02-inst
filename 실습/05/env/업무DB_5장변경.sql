-- 5장 실습용 업무 데이터베이스 변경 스크립트
--
-- 3장 초기화 스크립트는 볼륨을 처음 만들 때만 실행되므로, 5장에서 바뀌는 것은 이 스크립트로 더한다.
-- n8n의 Postgres 노드(자격 증명: 하루마켓 업무 DB, Operation: Execute Query)에 전체를 붙여 넣고 한 번 실행한다.
-- 여러 번 실행해도 오류가 나지 않고 결과가 같도록 작성했다. 이미 쌓인 데이터는 지우지 않는다.
--
-- 바꾸는 것
--   확장 vector              : 청크의 임베딩을 저장하는 벡터 열에 필요하다(pgvector)
--   inquiries                : 문의 번호 자동 발급, 분류 결과 열(detected_type, flags)
--   requests                 : 요청 번호 자동 발급, 넘긴 이유(handover_reason), 원하는 옵션(desired_option), 상태 값 검사
--   chat_sessions (새 테이블)    : 세션 기록. 업무 상태다
--   chat_memory   (새 테이블)    : 대화 메모리. Postgres Chat Memory 노드가 읽고 쓴다
--   policy_chunks (새 테이블)    : 검색 지식. Postgres PGVector Store 노드가 읽고 쓴다

-- 1. 벡터 열을 쓰기 위한 확장
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. 번호 발급
--    INQ-201, REQ-1001부터 발급한다. 1·2장 사례 번호(INQ-001~INQ-016, INQ-101~INQ-115, REQ-0001~)와 겹치지 않는다.
--    시작 번호가 이미 세 자리(네 자리)이므로 앞에 0을 채우지 않는다. 번호가 커지면 자리 수가 저절로 늘어난다.
CREATE SEQUENCE IF NOT EXISTS inquiry_no_seq START WITH 201;
CREATE SEQUENCE IF NOT EXISTS request_no_seq START WITH 1001;

ALTER TABLE inquiries ALTER COLUMN inquiry_id SET DEFAULT ('INQ-' || nextval('inquiry_no_seq')::text);
ALTER TABLE requests  ALTER COLUMN request_id SET DEFAULT ('REQ-' || nextval('request_no_seq')::text);

-- 3. 문의 기록: 4장에서 정한 분류 결과를 저장할 열
ALTER TABLE inquiries ADD COLUMN IF NOT EXISTS detected_type text;
ALTER TABLE inquiries ADD COLUMN IF NOT EXISTS flags jsonb;

ALTER TABLE inquiries DROP CONSTRAINT IF EXISTS inquiries_detected_type_check;
ALTER TABLE inquiries ADD CONSTRAINT inquiries_detected_type_check CHECK (
    detected_type IS NULL OR detected_type IN (
        'shipping_status', 'return_change_of_mind', 'return_defect',
        'exchange_option', 'exchange_other_product',
        'cancel_full', 'cancel_partial', 'mixed', 'other'
    )
);

COMMENT ON COLUMN inquiries.detected_type IS '4장 분류 결과. 분류하지 않았거나 검사에 실패했으면 NULL';
COMMENT ON COLUMN inquiries.flags IS '{"dispute_mentioned": 불리언, "repeat_mentioned": 불리언}';

-- 4. 요청 기록: 넘긴 이유, 원하는 옵션, 상태 값 검사
ALTER TABLE requests ADD COLUMN IF NOT EXISTS handover_reason text;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS desired_option text;

ALTER TABLE requests DROP CONSTRAINT IF EXISTS requests_status_check;
ALTER TABLE requests ADD CONSTRAINT requests_status_check CHECK (
    request_status IN (
        'received', 'info_requested', 'under_review', 'pending_approval',
        'pickup_requested', 'inspecting', 'closed'
    )
);

COMMENT ON COLUMN requests.desired_option IS '교환 요청에서 고객이 적은 옵션 표현. 고치지 않고 그대로 둔다';

-- 5. 세션 기록: 채팅 세션 하나의 업무 상태
CREATE TABLE IF NOT EXISTS chat_sessions (
    session_id        text PRIMARY KEY,
    topic             text        NOT NULL CHECK (topic IN ('shipping_return', 'exchange_cancel')),
    started_at        timestamptz NOT NULL DEFAULT now(),
    last_message_at   timestamptz NOT NULL DEFAULT now(),
    turn_count        integer     NOT NULL DEFAULT 0,
    needs_info_count  integer     NOT NULL DEFAULT 0,
    status            text        NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'handed_off')),
    handoff_reason    text,
    handed_off_at     timestamptz
);

COMMENT ON TABLE chat_sessions IS '세션 기록. 규칙이 읽고 쓰는 업무 상태이며 대화 내용은 담지 않는다';

-- 6. 대화 메모리: Postgres Chat Memory 노드가 만드는 열(id, session_id, message)에 created_at을 더해 미리 만든다
--    노드는 테이블이 이미 있으면 새로 만들지 않고 이 테이블을 쓴다. created_at은 보관 기한을 판단할 때 쓴다.
CREATE TABLE IF NOT EXISTS chat_memory (
    id          serial PRIMARY KEY,
    session_id  varchar(255) NOT NULL,
    message     jsonb        NOT NULL,
    created_at  timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chat_memory_session_idx ON chat_memory (session_id);

-- 7. 검색 지식: Postgres PGVector Store 노드가 만드는 열(id, text, metadata, embedding)과 같게 미리 만든다
--    embedding의 차원 3072는 임베딩 모델 text-embedding-3-large의 기본 차원이다.
--    다른 차원의 벡터를 넣으면 오류가 나므로, 적재와 검색에 다른 모델을 연결한 실수를 데이터베이스가 막아 준다.
CREATE TABLE IF NOT EXISTS policy_chunks (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    text       text,
    metadata   jsonb,
    embedding  vector(3072)
);

COMMENT ON TABLE policy_chunks IS '정책 문서의 청크와 임베딩. 문서가 바뀌면 같은 group의 행을 지우고 다시 적재한다';
