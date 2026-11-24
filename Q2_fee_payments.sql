-- QUESTION 2: UNIVERSITY FEE PAYMENTS
DROP SCHEMA IF EXISTS q2_fees CASCADE;
CREATE SCHEMA q2_fees;
SET search_path TO q2_fees,public;

CREATE TABLE students(
 student_id SERIAL PRIMARY KEY, student_number VARCHAR(30) UNIQUE NOT NULL,
 full_name VARCHAR(120) NOT NULL, fee_due NUMERIC(12,2) NOT NULL CHECK(fee_due>=0)
);
CREATE TABLE payments(
 payment_id SERIAL PRIMARY KEY, student_id INTEGER NOT NULL REFERENCES students(student_id),
 amount NUMERIC(12,2) NOT NULL CHECK(amount>0), paid_on TIMESTAMP NOT NULL
);
CREATE TABLE payment_audit(
 audit_id SERIAL PRIMARY KEY, payment_id INTEGER NOT NULL REFERENCES payments(payment_id),
 student_id INTEGER NOT NULL REFERENCES students(student_id), amount NUMERIC(12,2) NOT NULL,
 logged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE daily_collections(
 collection_date DATE PRIMARY KEY,payment_count BIGINT NOT NULL,total_amount NUMERIC(14,2) NOT NULL
);

CREATE OR REPLACE FUNCTION fn_fee_balance(p_student_id INTEGER)
RETURNS NUMERIC(12,2) LANGUAGE plpgsql AS $$
DECLARE v_due NUMERIC(12,2);
BEGIN
 SELECT fee_due INTO v_due FROM students WHERE student_id=p_student_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown student %',p_student_id; END IF;
 RETURN v_due-COALESCE((SELECT SUM(amount) FROM payments WHERE student_id=p_student_id),0);
END $$;

CREATE OR REPLACE PROCEDURE pr_receive_payment(p_student_id INTEGER,p_amount NUMERIC,p_paid_on TIMESTAMP)
LANGUAGE plpgsql AS $$
DECLARE v_balance NUMERIC(12,2);
BEGIN
 IF p_amount IS NULL OR p_amount<=0 OR p_paid_on IS NULL THEN RAISE EXCEPTION 'Invalid payment'; END IF;
 PERFORM 1 FROM students WHERE student_id=p_student_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown student'; END IF;
 v_balance:=fn_fee_balance(p_student_id);
 IF p_amount>v_balance THEN RAISE EXCEPTION 'Payment exceeds outstanding balance'; END IF;
 INSERT INTO payments(student_id,amount,paid_on) VALUES(p_student_id,p_amount,p_paid_on);
END $$;

CREATE OR REPLACE FUNCTION trg_payment_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO payment_audit(payment_id,student_id,amount) VALUES(NEW.payment_id,NEW.student_id,NEW.amount);
 RETURN NEW;
END $$;
CREATE TRIGGER payments_audit AFTER INSERT ON payments
FOR EACH ROW EXECUTE FUNCTION trg_payment_audit();

CREATE VIEW v_fee_balances AS
SELECT s.student_number,s.full_name,fn_fee_balance(s.student_id) AS outstanding_balance
FROM students s WHERE fn_fee_balance(s.student_id)>0;

CREATE INDEX idx_payments_student_paid_on ON payments(student_id,paid_on);
EXPLAIN SELECT * FROM payments WHERE student_id=1
AND paid_on>=TIMESTAMP '2026-01-01' AND paid_on<TIMESTAMP '2026-02-01';

CREATE OR REPLACE PROCEDURE pr_refresh_collections(p_day DATE)
LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO daily_collections(collection_date,payment_count,total_amount)
 SELECT p_day,COUNT(*),COALESCE(SUM(amount),0) FROM payments WHERE paid_on::date=p_day
 ON CONFLICT(collection_date) DO UPDATE
 SET payment_count=EXCLUDED.payment_count,total_amount=EXCLUDED.total_amount;
END $$;

INSERT INTO students(student_number,full_name,fee_due) VALUES
('MU001','Student One',5000),('MU002','Student Two',4200),('MU003','Student Three',3000);
CALL pr_receive_payment(1,1000,'2026-11-20 09:00');
CALL pr_receive_payment(1,500,'2026-11-21 09:00');
CALL pr_receive_payment(2,700,'2026-11-20 10:00');
CALL pr_receive_payment(2,800,'2026-11-21 10:00');
CALL pr_receive_payment(2,600,'2026-11-22 10:00');
CALL pr_receive_payment(1,300,'2026-11-22 09:00');
CALL pr_refresh_collections('2026-11-20');
CALL pr_refresh_collections('2026-11-21');
SELECT * FROM v_fee_balances;
SELECT * FROM payment_audit;

-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule('q2-daily-collections','0 1 * * *',
--   $$CALL q2_fees.pr_refresh_collections(CURRENT_DATE-1)$$);
