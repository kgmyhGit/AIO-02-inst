-- 예제용 데이터베이스 초기화 스크립트
--
-- PostgreSQL 컨테이너를 처음 만들 때(db_data 볼륨이 비어 있을 때) 한 번만 실행된다.
-- 업무DB_초기화.sql(10-harumarket.sql) 다음 순서로 실행된다.
--
--   데이터베이스 n8n_exam : n8n 워크플로우 예제에서 DB 연동을 연습하는 데이터베이스
--                           하루마켓 업무 데이터와 섞지 않기 위해 따로 둔다. 테이블은 예제에서 만든다.
--
-- 이미 환경을 설치했다면 이 스크립트는 다시 실행되지 않는다.
-- 그때는 compose.yml이 있는 폴더에서 아래 명령을 한 번 실행한다(<사용자>는 .env의 POSTGRES_USER 값).
--   docker compose exec db psql -U <사용자> -d n8n -c "CREATE DATABASE n8n_exam;"

CREATE DATABASE n8n_exam;
