-- 7장 실습의 시험 요청과 실행 추적을 처음 상태로 되돌린다.
--
-- 실습 7-7에서 구성을 바꾸어 다시 잴 때마다 실행한다. 7-8에서도 쓴다.
-- 이 장의 시험 요청(REQ-7001~7006, REQ-7101~7105)과 그 요청의 실행 추적, 발송 기록만 지운다.
-- 1~6장의 요청과 기록은 건드리지 않는다.
-- 모의 API에 집행된 환불·교환 기록은 지우지 않는다. 필요하면 6장 실습 6-3의 되돌리기 절차를 따른다.

-- 1. 실행 추적(agent_steps는 agent_runs를 지우면 함께 지워진다)
DELETE FROM agent_runs WHERE request_id IN ('REQ-7001', 'REQ-7002', 'REQ-7003', 'REQ-7004', 'REQ-7005', 'REQ-7006', 'REQ-7101', 'REQ-7102', 'REQ-7103', 'REQ-7104', 'REQ-7105');

-- 2. 발송 기록
DELETE FROM notifications WHERE request_id IN ('REQ-7001', 'REQ-7002', 'REQ-7003', 'REQ-7004', 'REQ-7005', 'REQ-7006', 'REQ-7101', 'REQ-7102', 'REQ-7103', 'REQ-7104', 'REQ-7105');

-- 3. 문의와 요청(문의가 요청을 가리키므로 문의부터 지운다)
DELETE FROM inquiries WHERE request_id IN ('REQ-7001', 'REQ-7002', 'REQ-7003', 'REQ-7004', 'REQ-7005', 'REQ-7006', 'REQ-7101', 'REQ-7102', 'REQ-7103', 'REQ-7104', 'REQ-7105');
DELETE FROM requests  WHERE request_id IN ('REQ-7001', 'REQ-7002', 'REQ-7003', 'REQ-7004', 'REQ-7005', 'REQ-7006', 'REQ-7101', 'REQ-7102', 'REQ-7103', 'REQ-7104', 'REQ-7105');

-- 4. 처음 상태로 다시 넣는다(업무DB_7장변경.sql의 3절과 같다)

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

-- 5. 확인: 반품 여섯 줄, 교환 다섯 줄. REQ-7006만 pending_approval이다.
SELECT request_id, request_type, request_status, handover_reason, order_id, desired_option
FROM requests WHERE request_id IN ('REQ-7001', 'REQ-7002', 'REQ-7003', 'REQ-7004', 'REQ-7005', 'REQ-7006', 'REQ-7101', 'REQ-7102', 'REQ-7103', 'REQ-7104', 'REQ-7105') ORDER BY request_id;
