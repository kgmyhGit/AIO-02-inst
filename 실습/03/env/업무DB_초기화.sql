-- 3장 실습용 업무 데이터베이스 초기화 스크립트
--
-- 이 스크립트는 PostgreSQL 컨테이너를 '처음' 만들 때 한 번만 실행된다.
-- 이미 데이터가 들어 있는 볼륨에서는 다시 실행되지 않는다.
-- 처음부터 다시 만들려면 컨테이너와 db_data 볼륨을 함께 지운 뒤 다시 올린다.
--
-- 만드는 것
--   데이터베이스 harumarket  : 업무 데이터베이스
--   테이블 inquiries         : 문의 기록. 2장 문의 기록 계약을 그대로 옮겼다
--   테이블 requests          : 요청 기록. 2장 요청 기록 계약의 주요 필드를 옮겼다
--
-- 3장에서는 이 테이블을 읽기만 한다. 워크플로우가 값을 넣고 바꾸는 일은 4장 이후에 다룬다.

CREATE DATABASE harumarket;

\connect harumarket

-- 문의 기록: 고객이 보낸 메시지 한 통을 남긴다.
CREATE TABLE inquiries (
    inquiry_id     text PRIMARY KEY,
    received_at    timestamptz NOT NULL,
    channel        text        NOT NULL CHECK (channel IN ('web', 'email')),
    customer_name  text        NOT NULL,
    order_id       text,
    message        text        NOT NULL,
    request_id     text
);

COMMENT ON TABLE inquiries IS '문의 기록. 메시지 한 통마다 한 행';
COMMENT ON COLUMN inquiries.order_id IS '찾지 못했으면 NULL. 빈 문자열을 넣지 않는다';
COMMENT ON COLUMN inquiries.request_id IS '연결된 요청 기록. 요청을 만들지 않는 문의는 NULL';

-- 요청 기록: 주문 하나에 대한 반품 한 번 또는 교환 한 번을 남긴다.
CREATE TABLE requests (
    request_id       text PRIMARY KEY,
    request_type     text,
    request_status   text NOT NULL,
    customer_name    text NOT NULL,
    order_id         text,
    order_info       jsonb,
    flags            jsonb,
    info_request_count integer NOT NULL DEFAULT 0,
    evidence         jsonb,
    approval_status  text,
    approval_due_at  timestamptz,
    close_reason     text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE requests IS '요청 기록. 처리 한 건마다 한 행이며 상태가 바뀐다';
COMMENT ON COLUMN requests.order_info IS '주문 조회 결과. 계약의 order 필드에 해당한다';

ALTER TABLE inquiries
    ADD CONSTRAINT inquiries_request_fk
    FOREIGN KEY (request_id) REFERENCES requests (request_id);

-- 연결을 확인하기 위한 예시 행 두 건. 값은 2장 사례와 같다.
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id) VALUES
('INQ-004', '2026-09-10T10:31:00+09:00', 'web',   '최민지', 'O-1004',
 '셔츠 사이즈가 생각보다 커서 반품하고 싶어요. 입어 보지는 않았고 택도 그대로 있어요.', NULL),
('INQ-009', '2026-09-10T11:15:00+09:00', 'web',   '송하은', NULL,
 '사이즈가 안 맞아서 원피스를 반품하려고요. 주문번호는 못 찾겠어요.', NULL);
