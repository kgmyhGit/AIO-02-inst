-- 5장 실습용 업무 데이터베이스 초기화 스크립트
--
-- 시험을 되풀이하기 전에 실행해 시험 데이터를 지우고 번호를 처음으로 되돌린다.
-- n8n의 Postgres 노드(자격 증명: 하루마켓 업무 DB, Operation: Execute Query)에 필요한 부분을 붙여 넣고 실행한다.
-- 3장 초기화 스크립트가 넣은 예시 행 두 건(INQ-004, INQ-009)은 남긴다.
-- 정책 문서의 청크(policy_chunks)는 지우지 않는다. 정책 문서를 다시 적재할 때는 5장 실습 5-5의 정책 적재를 실행한다.

-- [가] 업무 기록 초기화: 실습 5-4, 5-7(가)를 다시 시험하기 전에 실행한다
UPDATE inquiries SET request_id = NULL WHERE inquiry_id IN ('INQ-004', 'INQ-009');
DELETE FROM inquiries WHERE inquiry_id NOT IN ('INQ-004', 'INQ-009');
DELETE FROM requests;
ALTER SEQUENCE inquiry_no_seq RESTART WITH 201;
ALTER SEQUENCE request_no_seq RESTART WITH 1001;

-- [나] 대화 초기화: 실습 5-6, 5-7의 대화를 처음부터 다시 시험하기 전에 실행한다
--      세션 기록과 대화 메모리를 함께 지운다. 한쪽만 지우면 두 테이블이 서로 맞지 않게 된다.
DELETE FROM chat_memory;
DELETE FROM chat_sessions;
