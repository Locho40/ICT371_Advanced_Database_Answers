-- QUESTION 7: WATER METER READINGS AND BILLING
DROP SCHEMA IF EXISTS q7_water CASCADE;
CREATE SCHEMA q7_water;
SET search_path TO q7_water,public;

CREATE TABLE customers(customer_id SERIAL PRIMARY KEY,full_name VARCHAR(120) NOT NULL);
CREATE TABLE readings(
 reading_id SERIAL PRIMARY KEY,customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
 reading_month DATE NOT NULL CHECK(EXTRACT(DAY FROM reading_month)=1),
 previous_reading NUMERIC(12,2) NOT NULL CHECK(previous_reading>=0),
 current_reading NUMERIC(12,2) NOT NULL CHECK(current_reading>=0),
 UNIQUE(customer_id,reading_month)
);
CREATE TABLE bills(
 bill_id SERIAL PRIMARY KEY,reading_id INTEGER UNIQUE NOT NULL REFERENCES readings(reading_id),
 charge NUMERIC(12,2) NOT NULL CHECK(charge>=0),
 amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(amount_paid>=0 AND amount_paid<=charge),
 due_on DATE NOT NULL
);
CREATE TABLE receivable_snapshot(snapshot_date DATE PRIMARY KEY,total_due NUMERIC(14,2) NOT NULL);

CREATE OR REPLACE FUNCTION fn_water_charge(p_units NUMERIC)
RETURNS NUMERIC(12,2) LANGUAGE plpgsql AS $$
BEGIN
 IF p_units IS NULL OR p_units<0 THEN RAISE EXCEPTION 'Consumption cannot be NULL or negative'; END IF;
 RETURN ROUND(LEAST(p_units,10)*5+GREATEST(p_units-10,0)*8,2);
END $$;

CREATE OR REPLACE PROCEDURE pr_generate_bill(p_reading_id INTEGER,p_due_on DATE)
LANGUAGE plpgsql AS $$
DECLARE v_units NUMERIC;v_charge NUMERIC(12,2);
BEGIN
 SELECT current_reading-previous_reading INTO v_units FROM readings WHERE reading_id=p_reading_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown reading'; END IF;
 IF EXISTS(SELECT 1 FROM bills WHERE reading_id=p_reading_id) THEN RAISE EXCEPTION 'Bill already exists'; END IF;
 v_charge:=fn_water_charge(v_units);
 INSERT INTO bills(reading_id,charge,amount_paid,due_on) VALUES(p_reading_id,v_charge,0,p_due_on);
END $$;

CREATE OR REPLACE FUNCTION trg_reading_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.current_reading<NEW.previous_reading THEN RAISE EXCEPTION 'Current reading cannot be below previous reading'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER readings_validate BEFORE INSERT OR UPDATE ON readings
FOR EACH ROW EXECUTE FUNCTION trg_reading_check();

CREATE VIEW v_overdue_bills AS
SELECT c.full_name,b.due_on,(b.charge-b.amount_paid) AS outstanding_amount
FROM bills b JOIN readings r USING(reading_id) JOIN customers c USING(customer_id)
WHERE b.due_on<CURRENT_DATE AND b.amount_paid<b.charge;

CREATE INDEX idx_bills_due_unpaid ON bills(due_on) WHERE amount_paid<charge;
EXPLAIN SELECT * FROM bills WHERE due_on<CURRENT_DATE AND amount_paid<charge;

CREATE OR REPLACE PROCEDURE pr_refresh_receivables()
LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO receivable_snapshot(snapshot_date,total_due)
 SELECT CURRENT_DATE,COALESCE(SUM(charge-amount_paid),0) FROM bills WHERE amount_paid<charge
 ON CONFLICT(snapshot_date) DO UPDATE SET total_due=EXCLUDED.total_due;
END $$;

INSERT INTO customers(full_name) VALUES('Customer One'),('Customer Two'),('Customer Three');
INSERT INTO readings(customer_id,reading_month,previous_reading,current_reading) VALUES
(1,'2026-09-01',0,0),(1,'2026-10-01',0,10),(2,'2026-09-01',20,35),
(2,'2026-10-01',35,50),(3,'2026-09-01',100,110),(3,'2026-10-01',110,130);
CALL pr_generate_bill(1,CURRENT_DATE+10);
CALL pr_generate_bill(2,CURRENT_DATE+10);
CALL pr_generate_bill(3,CURRENT_DATE+10);
CALL pr_generate_bill(4,CURRENT_DATE+10);
CALL pr_generate_bill(5,CURRENT_DATE-2);
CALL pr_generate_bill(6,CURRENT_DATE-2);
UPDATE bills SET amount_paid=5 WHERE bill_id=5;
CALL pr_refresh_receivables();
SELECT * FROM v_overdue_bills;

-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule('q7-receivables','30 0 * * *','CALL q7_water.pr_refresh_receivables()');
