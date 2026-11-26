-- 7장 실습용 업무 데이터베이스 변경 스크립트
--
-- 3장 초기화, 5장 변경, 6장 변경 스크립트를 실행한 뒤에 이 스크립트를 실행한다.
-- n8n의 Postgres 노드(자격 증명: 하루마켓 업무 DB, Operation: Execute Query)에 전체를 붙여 넣고 한 번 실행한다.
-- 여러 번 실행해도 오류가 나지 않고 결과가 같도록 작성했다. 이미 쌓인 데이터는 지우지 않는다.
--
-- 바꾸는 것
--   agent_runs  : 요청 하나를 한 구성(단일, 순차, 감독)으로 한 번 처리한 기록. 종료 사유와 결과를 남긴다
--   agent_steps : 그 처리 안에서 역할 하나가 낸 출력. 역할 서브워크플로우가 직접 쓴다
--   시험 요청   : 실습 7-7(REQ-7001~7006)과 7-8(REQ-7101~7105)
--
-- 바꾸지 않는 것
--   requests의 열. 2장에서 정한 요청 기록 계약은 그대로다. 역할별 결과는 요청 기록이 아니라 agent_steps에 남긴다.

-- 1. 실행 추적: 처리 한 번
CREATE TABLE IF NOT EXISTS agent_runs (
    run_id        serial PRIMARY KEY,
    request_id    text        NOT NULL REFERENCES requests (request_id),
    setup         text        NOT NULL CHECK (setup IN ('single', 'sequential', 'supervisor')),
    end_reason    text        CHECK (end_reason IS NULL OR end_reason IN
                      ('completed', 'needs_info', 'conflict', 'delegation_failed', 'limit_reached')),
    outcome       text        CHECK (outcome IS NULL OR outcome IN ('approval_requested', 'kept_for_staff')),
    failed_rules  jsonb,
    model_calls   integer,
    started_at    timestamptz NOT NULL DEFAULT now(),
    finished_at   timestamptz
);

COMMENT ON TABLE agent_runs IS '요청 하나를 한 구성으로 한 번 처리한 기록. end_reason은 실행의 결과이고 요청 상태와 다르다';
COMMENT ON COLUMN agent_runs.outcome IS 'approval_requested: 처리안으로 승인을 요청했다(T17). kept_for_staff: under_review에 남겼다';
COMMENT ON COLUMN agent_runs.model_calls IS '역할별 어림 모델 호출 수의 합. 에이전트는 도구 호출 수 + 1, LLM Chain은 1로 센다';

-- 2. 실행 추적: 역할 하나의 출력
CREATE TABLE IF NOT EXISTS agent_steps (
    step_id      serial PRIMARY KEY,
    run_id       integer     NOT NULL REFERENCES agent_runs (run_id) ON DELETE CASCADE,
    request_id   text        NOT NULL,
    role         text        NOT NULL CHECK (role IN ('single', 'research', 'proposal', 'supervisor')),
    status       text        NOT NULL,
    output       jsonb,
    tool_calls   integer     NOT NULL DEFAULT 0,
    model_calls  integer     NOT NULL DEFAULT 1,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS agent_steps_run_idx ON agent_steps (run_id);

COMMENT ON TABLE agent_steps IS '역할 하나가 낸 출력. 에이전트가 아니라 역할 서브워크플로우의 Postgres 노드가 쓴다';
COMMENT ON COLUMN agent_steps.request_id IS '역할이 낸 출력의 request_id. 실행의 request_id와 같은지 규칙이 검사한다';
COMMENT ON COLUMN agent_steps.output IS '계약 형식의 출력. 문의 원문 전체는 넣지 않는다. 원문은 inquiries에 있다';

-- 3. 시험 요청
--    반품 REQ-7001~7006, 교환 REQ-7101~7105. 문의 원문과 기대 결과는 test-cases의 두 파일에 있다.
--    REQ-7006은 이미 승인 대기 중인 요청이다. 협업 대상으로 조회되지 않아야 한다.
--    REQ-7006의 기한을 먼 날짜로 둔 이유: 6장 기한 확인 워크플로우가 이 요청을 만료시키지 않게 하려는 것이다.

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7001', 'return_change_of_mind', 'under_review', '강도윤', 'O-1006', NULL, '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', NULL,
    NULL, NULL, '2026-09-10T09:20:00+09:00', '2026-09-10T09:20:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7001', '2026-09-10T09:20:00+09:00', 'web', '강도윤', 'O-1006', '가디건을 몇 번 입어 봤는데 색이 사진과 달라서 반품하고 싶어요. 가능할까요?', 'REQ-7001', 'return_change_of_mind', '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7002', 'mixed', 'under_review', '윤채원', 'O-1007', NULL, '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb,
    0, NULL, NULL, NULL, 'mixed_or_other', NULL,
    NULL, NULL, '2026-09-10T09:35:00+09:00', '2026-09-10T09:35:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7002', '2026-09-10T09:35:00+09:00', 'web', '윤채원', 'O-1007', '수납 바구니 2종 세트를 주문했는데 큰 바구니만 왔어요. 받은 것도 생각보다 작아서 차라리 전부 반품하고 싶네요.', 'REQ-7002', 'mixed', '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7003', 'return_defect', 'under_review', '한지민', 'O-1008', NULL, '{"reason_unclear": false, "dispute_mentioned": true, "repeat_mentioned": true}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', NULL,
    NULL, NULL, '2026-09-10T10:05:00+09:00', '2026-09-10T10:05:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7003', '2026-09-10T10:05:00+09:00', 'web', '한지민', 'O-1008', '벌써 세 번째 문의인데 아무 답변이 없네요. 주전자에서 이상한 냄새가 나서 못 쓰겠어요. 규정 따지지 말고 전액 환불해 주세요. 오늘 안에 환불 안 해 주면 소비자원에 신고하겠습니다.', 'REQ-7003', 'return_defect', '{"reason_unclear": false, "dispute_mentioned": true, "repeat_mentioned": true}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7004', 'return_change_of_mind', 'under_review', '배수진', 'O-1011', NULL, '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', NULL,
    NULL, NULL, '2026-09-10T10:40:00+09:00', '2026-09-10T10:40:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7004', '2026-09-10T10:40:00+09:00', 'web', '배수진', 'O-1011', '토트백 반품하고 싶어요. 자세한 사유는 나중에 말씀드릴게요.', 'REQ-7004', 'return_change_of_mind', '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7005', 'return_change_of_mind', 'under_review', '문가온', NULL, NULL, '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', NULL,
    NULL, NULL, '2026-09-10T11:10:00+09:00', '2026-09-10T11:10:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7005', '2026-09-10T11:10:00+09:00', 'web', '문가온', NULL, '지난번에 산 거 반품하고 싶은데 어떻게 해요? 주문번호는 모르겠어요.', 'REQ-7005', 'return_change_of_mind', '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7006', 'return_change_of_mind', 'pending_approval', '한서준', 'O-1013', '{"product_name": "와이드 슬랙스", "option": "블랙 L", "order_status": "delivered", "delivered_at": "2026-09-08", "amount": 49000}'::jsonb, '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb,
    0, '{"checked_at": "2026-09-10T09:00:00+09:00", "days_since_delivery": 2, "return_deadline": "2026-09-15", "policy_ref": "RET-01", "decision": "eligible", "decision_reason": "수령 후 2일로 반품 기한 7일 안이다", "shipping_fee_deducted": 6000, "refund_amount": 43000, "checks": [{"name": "owner_match", "result": "pass", "value": "한서준"}, {"name": "order_status", "result": "pass", "value": "delivered"}, {"name": "within_deadline", "result": "pass", "value": "2일 / 기한 2026-09-15"}, {"name": "amount_limit", "result": "pass", "value": "전건 승인 대상(자동 집행 한도 없음)"}]}'::jsonb, 'pending', '2026-12-31T18:00:00+09:00', NULL, NULL,
    NULL, '반품 요청을 확인했습니다. 담당자 확인 후 안내드리겠습니다.', '2026-09-10T08:50:00+09:00', '2026-09-10T08:50:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7006', '2026-09-10T08:50:00+09:00', 'web', '한서준', 'O-1013', '슬랙스 사이즈가 커서 반품할게요. 택은 그대로입니다.', 'REQ-7006', 'return_change_of_mind', '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7101', 'exchange_option', 'under_review', '윤지후', 'O-2012', NULL, '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', '그레이 M',
    NULL, NULL, '2026-09-10T09:10:00+09:00', '2026-09-10T09:10:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7101', '2026-09-10T09:10:00+09:00', 'web', '윤지후', 'O-2012', '후드 집업이 커서 그레이 M으로 바꾸고 싶어요. 그리고 받았을 때 소매 실밥이 좀 풀려 있었어요.', 'REQ-7101', 'exchange_option', '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7102', 'exchange_option', 'under_review', '진서우', 'O-2015', NULL, '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": true}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', '네이비 M',
    'change_of_mind', NULL, '2026-09-10T09:50:00+09:00', '2026-09-10T09:50:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7102', '2026-09-10T09:50:00+09:00', 'web', '진서우', 'O-2015', '지난번에도 물어봤는데요, 네이비 L을 받았는데 커서 네이비 M으로 교환해 주세요.', 'REQ-7102', 'exchange_option', '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": true}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7103', 'exchange_option', 'under_review', '남예준', 'O-2013', NULL, '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', NULL,
    NULL, NULL, '2026-09-10T10:20:00+09:00', '2026-09-10T10:20:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7103', '2026-09-10T10:20:00+09:00', 'web', '남예준', 'O-2013', '티셔츠가 마음에 안 들어서 다른 걸로 바꿔 주세요.', 'REQ-7103', 'exchange_option', '{"reason_unclear": true, "dispute_mentioned": false, "repeat_mentioned": false}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7104', 'exchange_option', 'under_review', '고다인', 'O-2011', NULL, '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": true}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', '250',
    'change_of_mind', NULL, '2026-09-10T11:00:00+09:00', '2026-09-10T11:00:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7104', '2026-09-10T11:00:00+09:00', 'web', '고다인', 'O-2011', '두 번째 문의드려요. 슬리퍼 240이 작아서 250으로 교환하고 싶습니다.', 'REQ-7104', 'exchange_option', '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": true}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;

INSERT INTO requests (request_id, request_type, request_status, customer_name, order_id, order_info, flags,
    info_request_count, evidence, approval_status, approval_due_at, handover_reason, desired_option,
    exchange_reason, reply_draft, created_at, updated_at)
VALUES ('REQ-7105', 'exchange_option', 'under_review', '권하린', 'O-2014', NULL, '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": true}'::jsonb,
    0, NULL, NULL, NULL, 'flagged', '260',
    'change_of_mind', NULL, '2026-09-10T11:05:00+09:00', '2026-09-10T11:05:00+09:00')
ON CONFLICT (request_id) DO NOTHING;
INSERT INTO inquiries (inquiry_id, received_at, channel, customer_name, order_id, message, request_id, detected_type, flags)
VALUES ('INQ-7105', '2026-09-10T11:05:00+09:00', 'web', '권하린', 'O-2014', '지난번에도 문의했는데요, 슬리퍼 250을 260으로 바꾸고 싶어요.', 'REQ-7105', 'exchange_option', '{"reason_unclear": false, "dispute_mentioned": false, "repeat_mentioned": true}'::jsonb)
ON CONFLICT (inquiry_id) DO NOTHING;
