-- 6장 실습용 업무 데이터베이스 변경 스크립트
--
-- 3장 초기화 스크립트와 5장 변경 스크립트를 실행한 뒤에 이 스크립트를 실행한다.
-- n8n의 Postgres 노드(자격 증명: 하루마켓 업무 DB, Operation: Execute Query)에 전체를 붙여 넣고 한 번 실행한다.
-- 여러 번 실행해도 오류가 나지 않고 결과가 같도록 작성했다. 이미 쌓인 데이터는 지우지 않는다.
--
-- 바꾸는 것
--   requests      : 승인 번호 발급, 승인 결과와 승인한 대상, 기한 알림 시각, 안내 초안, 집행 결과, 교환 사유
--   notifications : 고객과 담당자에게 보낸 것을 남기는 새 테이블
--
-- 2장 계약과의 대응
--   approval_status, approval_due_at, lead_notified_at, approval_decided_at, approval_note는 2장 표 2-40에서 정했다.
--   approved_refund_amount(반품)와 approved_option, approved_shipping_fee(교환)는 승인한 대상을 남기는 값이다.
--   approval_id는 6장에서 새로 정한 값이다. 승인 하나를 가리키며 집행 요청의 request_id로 그대로 쓴다.

-- 1. 승인 번호 발급
--    APV-1001부터 발급한다. 모의 API가 이 값으로 중복 집행을 막으므로 승인마다 하나씩만 나와야 한다.
CREATE SEQUENCE IF NOT EXISTS approval_no_seq START WITH 1001;

-- 2. 요청 기록: 승인과 집행에 필요한 열
ALTER TABLE requests ADD COLUMN IF NOT EXISTS approval_id             text;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS approval_decided_at     timestamptz;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS approval_note           text;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS lead_notified_at        timestamptz;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS last_info_request_at    timestamptz;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS reply_draft             text;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS approved_refund_amount  integer;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS approved_option         text;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS approved_shipping_fee   integer;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS execution_id            text;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS executed_at             timestamptz;

-- 교환 요청의 사유. 2장 표 2-58에서 정했고 교환 경로를 만드는 6장에서 더한다.
-- defect이면 사실 확인이 필요하므로 판단에서 담당자에게 넘긴다.
ALTER TABLE requests ADD COLUMN IF NOT EXISTS exchange_reason         text;
ALTER TABLE requests DROP CONSTRAINT IF EXISTS requests_exchange_reason_check;
ALTER TABLE requests ADD CONSTRAINT requests_exchange_reason_check CHECK (
    exchange_reason IS NULL OR exchange_reason IN ('change_of_mind', 'defect')
);

-- 승인 번호는 승인을 기록하는 순간 발급한다. 한 요청에 하나만 있어야 한다.
CREATE UNIQUE INDEX IF NOT EXISTS requests_approval_id_key ON requests (approval_id) WHERE approval_id IS NOT NULL;

ALTER TABLE requests DROP CONSTRAINT IF EXISTS requests_approval_status_check;
ALTER TABLE requests ADD CONSTRAINT requests_approval_status_check CHECK (
    approval_status IS NULL OR approval_status IN ('pending', 'approved', 'rejected', 'expired')
);

COMMENT ON COLUMN requests.approval_id IS '승인 하나를 가리키는 번호. 집행 요청의 request_id로 그대로 보내 중복 집행을 막는다';
COMMENT ON COLUMN requests.approved_refund_amount IS '승인한 환불 금액. 집행 직전에 evidence의 현재 금액과 대조한다';
COMMENT ON COLUMN requests.approved_option IS '승인한 교환 옵션. 집행 직전에 현재 옵션과 대조한다';
COMMENT ON COLUMN requests.lead_notified_at IS '기한 경과를 팀장에게 알린 시각. 같은 알림이 반복되지 않게 하는 값이다';
COMMENT ON COLUMN requests.execution_id IS '모의 API가 돌려준 집행 번호. 값이 있으면 이미 집행된 요청이다';
COMMENT ON COLUMN requests.exchange_reason IS '교환 사유. change_of_mind면 배송비를 고객이 내고 defect이면 판매자가 낸다';

-- 3. 발송 기록: 고객과 담당자에게 보낸 것을 남긴다
--    5장에서 "요청 기록이 없는 문의(배송·취소·기타)의 처리 결과를 어디에 남길지"를 6장으로 넘겼다. 여기에 남긴다.
CREATE TABLE IF NOT EXISTS notifications (
    notification_id serial PRIMARY KEY,
    inquiry_id      text        REFERENCES inquiries (inquiry_id),
    request_id      text        REFERENCES requests (request_id),
    channel         text        NOT NULL CHECK (channel IN ('email')),
    audience        text        NOT NULL CHECK (audience IN ('customer', 'staff', 'lead')),
    purpose         text        NOT NULL CHECK (purpose IN ('guide', 'approval_request', 'approval_reminder', 'result')),
    subject         text        NOT NULL,
    sent_at         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE notifications IS '보낸 메일의 기록. 본문은 남기지 않고 무엇을 언제 누구에게 보냈는지만 남긴다';
COMMENT ON COLUMN notifications.request_id IS '요청 기록이 없는 문의(배송·취소·기타)의 안내는 NULL이다';

CREATE INDEX IF NOT EXISTS notifications_request_idx ON notifications (request_id);
CREATE INDEX IF NOT EXISTS notifications_inquiry_idx ON notifications (inquiry_id);

-- 4. 넘긴 이유에 6장에서 더해지는 값
--    재검증 실패(revalidation_failed)는 6장에서 생긴 경로다. 2장 표 2-40의 허용 값 목록에 반영했다.
--    열은 text이므로 스키마 변경은 없고 값만 늘어난다.
COMMENT ON COLUMN requests.handover_reason IS
    '담당자에게 넘긴 이유. 허용 값은 2장 표 2-40, 교환의 stock_unavailable은 2장 표 2-58에 있다';

-- 5. 분류 표시
--    reason_unclear(반품 사유 불명확)는 2장 계약에 이미 있는 값인데 4장 분류 지시문에는 넣지 않았다.
--    반품 경로를 만드는 6장에서 지시문과 스키마에 더한다. flags는 jsonb이므로 데이터베이스 변경은 없다.
COMMENT ON COLUMN inquiries.flags IS
    '{"dispute_mentioned": 불리언, "repeat_mentioned": 불리언, "reason_unclear": 불리언}. 2장 표 2-39이 정한 세 가지다';
COMMENT ON COLUMN requests.flags IS
    '문의 기록의 flags를 옮겨 온 값. 하나라도 참이면 under_review로 넘긴다';
