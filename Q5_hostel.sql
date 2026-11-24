-- QUESTION 5: HOSTEL ROOM ALLOCATION
DROP SCHEMA IF EXISTS q5_hostel CASCADE;
CREATE SCHEMA q5_hostel;
SET search_path TO q5_hostel,public;

CREATE TABLE students(student_id SERIAL PRIMARY KEY,student_number VARCHAR(30) UNIQUE NOT NULL,full_name VARCHAR(120) NOT NULL);
CREATE TABLE rooms(room_id SERIAL PRIMARY KEY,room_number VARCHAR(20) UNIQUE NOT NULL,capacity INTEGER NOT NULL CHECK(capacity>0));
CREATE TABLE allocations(
 allocation_id SERIAL PRIMARY KEY,student_id INTEGER NOT NULL REFERENCES students(student_id),
 room_id INTEGER NOT NULL REFERENCES rooms(room_id),allocated_on DATE NOT NULL,
 released_on DATE,status VARCHAR(10) NOT NULL CHECK(status IN('ACTIVE','ENDED')),
 CHECK((status='ACTIVE' AND released_on IS NULL) OR (status='ENDED' AND released_on IS NOT NULL))
);
CREATE TABLE occupancy_snapshot(
 snapshot_date DATE NOT NULL,room_id INTEGER NOT NULL REFERENCES rooms(room_id),
 occupied_beds INTEGER NOT NULL,free_beds INTEGER NOT NULL,
 PRIMARY KEY(snapshot_date,room_id)
);

CREATE OR REPLACE FUNCTION fn_free_beds(p_room_id INTEGER)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_capacity INTEGER; v_used INTEGER;
BEGIN
 SELECT capacity INTO v_capacity FROM rooms WHERE room_id=p_room_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown room'; END IF;
 SELECT COUNT(*) INTO v_used FROM allocations WHERE room_id=p_room_id AND status='ACTIVE';
 RETURN v_capacity-v_used;
END $$;

CREATE OR REPLACE PROCEDURE pr_allocate_room(p_student_id INTEGER,p_room_id INTEGER,p_allocated_on DATE)
LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM students WHERE student_id=p_student_id) THEN RAISE EXCEPTION 'Unknown student'; END IF;
 PERFORM 1 FROM rooms WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown room'; END IF;
 IF EXISTS(SELECT 1 FROM allocations WHERE student_id=p_student_id AND status='ACTIVE') THEN RAISE EXCEPTION 'Student already has an active allocation'; END IF;
 IF fn_free_beds(p_room_id)<=0 THEN RAISE EXCEPTION 'Room is full'; END IF;
 INSERT INTO allocations(student_id,room_id,allocated_on,status) VALUES(p_student_id,p_room_id,p_allocated_on,'ACTIVE');
END $$;

CREATE OR REPLACE FUNCTION trg_allocation_rules()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_capacity INTEGER; v_used INTEGER;
BEGIN
 IF NEW.status='ACTIVE' THEN
  SELECT capacity INTO v_capacity FROM rooms WHERE room_id=NEW.room_id;
  SELECT COUNT(*) INTO v_used FROM allocations a WHERE a.room_id=NEW.room_id
   AND a.status='ACTIVE' AND a.allocation_id<>COALESCE(NEW.allocation_id,-1);
  IF v_used>=v_capacity THEN RAISE EXCEPTION 'Room capacity exceeded'; END IF;
  IF EXISTS(SELECT 1 FROM allocations a WHERE a.student_id=NEW.student_id
    AND a.status='ACTIVE' AND a.allocation_id<>COALESCE(NEW.allocation_id,-1)) THEN
    RAISE EXCEPTION 'Student already has an active allocation';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER allocations_rules BEFORE INSERT OR UPDATE ON allocations
FOR EACH ROW EXECUTE FUNCTION trg_allocation_rules();
CREATE UNIQUE INDEX uq_one_active_allocation ON allocations(student_id) WHERE status='ACTIVE';

CREATE VIEW v_room_occupancy AS
SELECT r.room_id,r.room_number,r.capacity,COUNT(a.allocation_id) FILTER(WHERE a.status='ACTIVE')::INTEGER AS occupied_beds,
r.capacity-COUNT(a.allocation_id) FILTER(WHERE a.status='ACTIVE')::INTEGER AS free_beds
FROM rooms r LEFT JOIN allocations a USING(room_id) GROUP BY r.room_id;

CREATE INDEX idx_allocations_active_room ON allocations(room_id) WHERE status='ACTIVE';
EXPLAIN SELECT * FROM allocations WHERE room_id=1 AND status='ACTIVE';

CREATE OR REPLACE PROCEDURE pr_refresh_occupancy()
LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO occupancy_snapshot(snapshot_date,room_id,occupied_beds,free_beds)
 SELECT CURRENT_DATE,r.room_id,COUNT(a.allocation_id) FILTER(WHERE a.status='ACTIVE')::INTEGER,
 r.capacity-COUNT(a.allocation_id) FILTER(WHERE a.status='ACTIVE')::INTEGER
 FROM rooms r LEFT JOIN allocations a USING(room_id) GROUP BY r.room_id,r.capacity
 ON CONFLICT(snapshot_date,room_id) DO UPDATE SET
 occupied_beds=EXCLUDED.occupied_beds,free_beds=EXCLUDED.free_beds;
END $$;

INSERT INTO students(student_number,full_name) VALUES('ST001','Student One'),('ST002','Student Two'),('ST003','Student Three'),('ST004','Student Four'),('ST005','Student Five');
INSERT INTO rooms(room_number,capacity) VALUES('A01',2),('A02',3),('A03',1);
CALL pr_allocate_room(1,1,CURRENT_DATE);
CALL pr_allocate_room(2,1,CURRENT_DATE);
CALL pr_allocate_room(3,2,CURRENT_DATE);
CALL pr_allocate_room(4,2,CURRENT_DATE);
UPDATE allocations SET status='ENDED',released_on=CURRENT_DATE WHERE allocation_id=4;
CALL pr_allocate_room(4,3,CURRENT_DATE);
CALL pr_refresh_occupancy();
SELECT * FROM v_room_occupancy;

-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule('q5-occupancy','55 23 * * *','CALL q5_hostel.pr_refresh_occupancy()');
