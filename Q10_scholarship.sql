-- QUESTION 10: SCHOLARSHIP APPLICATION ASSESSMENT
DROP SCHEMA IF EXISTS q10_scholarship CASCADE;
CREATE SCHEMA q10_scholarship;
SET search_path TO q10_scholarship,public;

CREATE TABLE students(
 student_id SERIAL PRIMARY KEY,student_number VARCHAR(30) UNIQUE NOT NULL,full_name VARCHAR(120) NOT NULL
);
CREATE TABLE applications(
 application_id SERIAL PRIMARY KEY,student_id INTEGER NOT NULL REFERENCES students(student_id),
 age_at_application INTEGER NOT NULL CHECK(age_at_application>0),
 monthly_income NUMERIC(12,2) NOT NULL CHECK(monthly_income>=0),
 average_mark NUMERIC(5,2) NOT NULL CHECK(average_mark BETWEEN 0 AND 100),
 submitted_on DATE NOT NULL,
 status VARCHAR(10) NOT NULL DEFAULT 'PENDING' CHECK(status IN('PENDING','APPROVED','REJECTED'))
);
CREATE TABLE decision_audit(
 audit_id SERIAL PRIMARY KEY,application_id INTEGER NOT NULL REFERENCES applications(application_id),
 old_status VARCHAR(10) NOT NULL,new_status VARCHAR(10) NOT NULL,
 changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INTEGER,p_income NUMERIC,p_mark NUMERIC)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
 IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN RAISE EXCEPTION 'Eligibility inputs cannot be NULL'; END IF;
 IF p_age<=0 OR p_income<0 OR p_mark<0 OR p_mark>100 THEN RAISE EXCEPTION 'Invalid eligibility input'; END IF;
 RETURN p_age BETWEEN 18 AND 25 AND p_income<=3000 AND p_mark>=70;
END $$;

CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE a RECORD;v_status VARCHAR(10);
BEGIN
 SELECT * INTO a FROM applications WHERE application_id=p_application_id AND status='PENDING' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown application or application already assessed'; END IF;
 IF fn_scholarship_eligible(a.age_at_application,a.monthly_income,a.average_mark) THEN
  v_status:='APPROVED';
 ELSE v_status:='REJECTED'; END IF;
 UPDATE applications SET status=v_status WHERE application_id=p_application_id;
END $$;

CREATE OR REPLACE FUNCTION trg_decision_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.status IS DISTINCT FROM NEW.status THEN
  INSERT INTO decision_audit(application_id,old_status,new_status)
  VALUES(NEW.application_id,OLD.status,NEW.status);
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER applications_status_audit AFTER UPDATE ON applications
FOR EACH ROW EXECUTE FUNCTION trg_decision_audit();

CREATE VIEW v_approved_applicants AS
SELECT s.student_number,s.full_name,a.average_mark,a.status
FROM applications a JOIN students s USING(student_id)
WHERE a.status='APPROVED';

CREATE INDEX idx_applications_status_submitted ON applications(status,submitted_on);
EXPLAIN SELECT * FROM applications WHERE status='PENDING'
AND submitted_on BETWEEN DATE '2026-01-01' AND DATE '2026-12-31';

CREATE OR REPLACE PROCEDURE pr_assess_pending()
LANGUAGE plpgsql AS $$
DECLARE a RECORD;
BEGIN
 FOR a IN SELECT application_id FROM applications WHERE status='PENDING' ORDER BY application_id LOOP
  CALL pr_assess_application(a.application_id);
 END LOOP;
END $$;

INSERT INTO students(student_number,full_name) VALUES
('MU2024001','Applicant One'),('MU2024002','Applicant Two'),('MU2024003','Applicant Three');
INSERT INTO applications(student_id,age_at_application,monthly_income,average_mark,submitted_on) VALUES
(1,18,3000,70,CURRENT_DATE),(1,25,2500,85,CURRENT_DATE),(2,17,2000,90,CURRENT_DATE),
(2,22,3001,80,CURRENT_DATE),(3,24,2800,69.99,CURRENT_DATE),(3,26,1000,95,CURRENT_DATE);
CALL pr_assess_pending();
SELECT * FROM applications;
SELECT * FROM v_approved_applicants;
SELECT * FROM decision_audit;

-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule('q10-weekly-assessment','0 8 * * 1','CALL q10_scholarship.pr_assess_pending()');
