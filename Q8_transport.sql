-- QUESTION 8: TRANSPORT FLEET MAINTENANCE
DROP SCHEMA IF EXISTS q8_transport CASCADE;
CREATE SCHEMA q8_transport;
SET search_path TO q8_transport,public;

CREATE TABLE vehicles(
 vehicle_id SERIAL PRIMARY KEY,registration VARCHAR(20) UNIQUE NOT NULL,
 current_odometer NUMERIC(12,2) NOT NULL CHECK(current_odometer>=0),
 last_service_odometer NUMERIC(12,2) NOT NULL CHECK(last_service_odometer>=0 AND last_service_odometer<=current_odometer)
);
CREATE TABLE trips(
 trip_id SERIAL PRIMARY KEY,vehicle_id INTEGER NOT NULL REFERENCES vehicles(vehicle_id),
 trip_on DATE NOT NULL,start_odometer NUMERIC(12,2) NOT NULL CHECK(start_odometer>=0),
 end_odometer NUMERIC(12,2) NOT NULL CHECK(end_odometer>start_odometer)
);
CREATE TABLE service_alerts(
 vehicle_id INTEGER PRIMARY KEY REFERENCES vehicles(vehicle_id),
 km_since_service NUMERIC(12,2) NOT NULL,flagged_on DATE NOT NULL
);

CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id INTEGER)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_current NUMERIC;v_service NUMERIC;
BEGIN
 SELECT current_odometer,last_service_odometer INTO v_current,v_service FROM vehicles WHERE vehicle_id=p_vehicle_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
 RETURN v_current-v_service>=5000;
END $$;

CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id INTEGER,p_trip_on DATE,p_start NUMERIC,p_end NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM vehicles WHERE vehicle_id=p_vehicle_id) THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
 IF p_trip_on IS NULL OR p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid trip mileage/date'; END IF;
 INSERT INTO trips(vehicle_id,trip_on,start_odometer,end_odometer) VALUES(p_vehicle_id,p_trip_on,p_start,p_end);
END $$;

CREATE OR REPLACE FUNCTION trg_trip_update_odometer()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_current NUMERIC;
BEGIN
 SELECT current_odometer INTO v_current FROM vehicles WHERE vehicle_id=NEW.vehicle_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
 IF NEW.start_odometer<>v_current THEN RAISE EXCEPTION 'Trip must start at current odometer %',v_current; END IF;
 IF NEW.end_odometer<=NEW.start_odometer THEN RAISE EXCEPTION 'End odometer must exceed start'; END IF;
 UPDATE vehicles SET current_odometer=NEW.end_odometer WHERE vehicle_id=NEW.vehicle_id;
 RETURN NEW;
END $$;
CREATE TRIGGER trips_update_vehicle BEFORE INSERT ON trips
FOR EACH ROW EXECUTE FUNCTION trg_trip_update_odometer();

CREATE VIEW v_service_due AS
SELECT registration,current_odometer-last_service_odometer AS km_since_service
FROM vehicles WHERE current_odometer-last_service_odometer>=5000;

CREATE INDEX idx_trips_vehicle_date ON trips(vehicle_id,trip_on);
EXPLAIN SELECT * FROM trips WHERE vehicle_id=1 AND trip_on BETWEEN DATE '2026-01-01' AND DATE '2026-12-31';

CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts()
LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO service_alerts(vehicle_id,km_since_service,flagged_on)
 SELECT vehicle_id,current_odometer-last_service_odometer,CURRENT_DATE
 FROM vehicles WHERE current_odometer-last_service_odometer>=5000
 ON CONFLICT(vehicle_id) DO UPDATE SET
 km_since_service=EXCLUDED.km_since_service,flagged_on=EXCLUDED.flagged_on;
 DELETE FROM service_alerts a USING vehicles v
 WHERE a.vehicle_id=v.vehicle_id AND v.current_odometer-v.last_service_odometer<5000;
END $$;

INSERT INTO vehicles(registration,current_odometer,last_service_odometer) VALUES
('ABC001',10000,5000),('ABC002',7000,4000),('ABC003',3000,1000);
-- Trigger is installed before trips are inserted. Each start matches current odometer.
CALL pr_record_trip(1,CURRENT_DATE,10000,11000);
CALL pr_record_trip(1,CURRENT_DATE,11000,12000);
CALL pr_record_trip(2,CURRENT_DATE,7000,8000);
CALL pr_record_trip(2,CURRENT_DATE,8000,9000);
CALL pr_record_trip(3,CURRENT_DATE,3000,4000);
CALL pr_record_trip(3,CURRENT_DATE,4000,5000);
CALL pr_refresh_service_alerts();
SELECT * FROM v_service_due;
SELECT * FROM service_alerts;

-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule('q8-service-alerts','0 6 * * 1','CALL q8_transport.pr_refresh_service_alerts()');
