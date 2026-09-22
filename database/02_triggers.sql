-- ============================================================================
-- AIRLINE FLIGHT DISPATCH & CREW ROSTERING DATABASE SYSTEM
-- Business Logic Triggers (FAA/DGCA Regulatory Compliance)
-- Target Database: MySQL 8.0+ (InnoDB Engine)
-- Script: 02_triggers.sql
-- ============================================================================

USE `airline_dispatch_db`;

DROP TRIGGER IF EXISTS `trg_enforce_fdp_and_mandatory_rest`;
DROP TRIGGER IF EXISTS `trg_prevent_aircraft_turnaround_conflict`;
DROP TRIGGER IF EXISTS `trg_verify_pilot_type_rating`;

DELIMITER //

-- ----------------------------------------------------------------------------
-- Trigger 1: trg_enforce_fdp_and_mandatory_rest
-- Enforces mandatory crew rest and caps cumulative 24-hour duty hours <= 14 hours
-- ----------------------------------------------------------------------------
CREATE TRIGGER `trg_enforce_fdp_and_mandatory_rest`
BEFORE INSERT ON `crew_duty_rosters`
FOR EACH ROW
BEGIN
    DECLARE v_flight_dept DATETIME;
    DECLARE v_flight_arr DATETIME;
    DECLARE v_flight_block_mins INT;
    DECLARE v_latest_rest_until DATETIME;
    DECLARE v_window_start DATETIME;
    DECLARE v_accumulated_duty_mins INT DEFAULT 0;
    DECLARE v_total_projected_duty_hours DECIMAL(5, 2);

    -- 1. Fetch flight instance departure, arrival, and planned block time
    SELECT sf.departure_datetime, sf.arrival_datetime, fr.block_time_minutes
    INTO v_flight_dept, v_flight_arr, v_flight_block_mins
    FROM `scheduled_flights` sf
    INNER JOIN `flight_routes` fr ON sf.route_id = fr.route_id
    WHERE sf.flight_instance_id = NEW.flight_instance_id;

    -- 2. Verify mandatory rest period expiration
    SELECT MAX(mandatory_rest_until)
    INTO v_latest_rest_until
    FROM `crew_rest_periods`
    WHERE crew_id = NEW.crew_id
      AND last_duty_ended_at <= v_flight_dept;

    IF v_latest_rest_until IS NOT NULL AND v_latest_rest_until > v_flight_dept THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'FDP Safety Violation: Crew member has insufficient rest or exceeds rolling 24h duty limits. Mandatory rest period has not expired prior to departure.';
    END IF;

    -- 3. Calculate rolling 24-hour Flight Duty Period (FDP)
    -- Look back 24 hours from the flight departure time
    SET v_window_start = DATE_SUB(v_flight_dept, INTERVAL 24 HOUR);

    SELECT COALESCE(SUM(fr2.block_time_minutes), 0)
    INTO v_accumulated_duty_mins
    FROM `crew_duty_rosters` cdr2
    INNER JOIN `scheduled_flights` sf2 ON cdr2.flight_instance_id = sf2.flight_instance_id
    INNER JOIN `flight_routes` fr2 ON sf2.route_id = fr2.route_id
    WHERE cdr2.crew_id = NEW.crew_id
      AND cdr2.assignment_status IN ('Assigned', 'Checked_In')
      AND sf2.flight_status NOT IN ('Cancelled')
      AND sf2.departure_datetime >= v_window_start
      AND sf2.departure_datetime < v_flight_dept;

    -- Projected duty includes previous flights in rolling window + current flight
    SET v_total_projected_duty_hours = (v_accumulated_duty_mins + v_flight_block_mins) / 60.0;

    -- FAA Part 117 / DGCA Rule: Single-pilot/two-pilot unaugmented crew FDP limit is capped at 14 hours
    IF v_total_projected_duty_hours > 14.0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'FDP Safety Violation: Crew member has insufficient rest or exceeds rolling 24h duty limits. Total projected duty exceeds 14.0 hours.';
    END IF;
END //

-- ----------------------------------------------------------------------------
-- Trigger 2: trg_prevent_aircraft_turnaround_conflict
-- Guarantees minimum ground turnaround buffer time for refueling & inspection
-- ----------------------------------------------------------------------------
CREATE TRIGGER `trg_prevent_aircraft_turnaround_conflict`
BEFORE INSERT ON `scheduled_flights`
FOR EACH ROW
BEGIN
    DECLARE v_min_turnaround INT DEFAULT 45;
    DECLARE v_prev_arrival DATETIME;
    DECLARE v_buffer_minutes INT;

    -- Fetch aircraft model minimum turnaround requirement
    SELECT am.min_turnaround_minutes
    INTO v_min_turnaround
    FROM `aircraft_fleet` af
    INNER JOIN `aircraft_models` am ON af.model_id = am.model_id
    WHERE af.aircraft_id = NEW.aircraft_id;

    -- Retrieve the latest arrival of this physical aircraft prior to NEW.departure_datetime
    SELECT MAX(arrival_datetime)
    INTO v_prev_arrival
    FROM `scheduled_flights`
    WHERE aircraft_id = NEW.aircraft_id
      AND flight_status NOT IN ('Cancelled')
      AND arrival_datetime <= NEW.departure_datetime;

    IF v_prev_arrival IS NOT NULL THEN
        SET v_buffer_minutes = TIMESTAMPDIFF(MINUTE, v_prev_arrival, NEW.departure_datetime);
        IF v_buffer_minutes < v_min_turnaround THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Turnaround Buffer Conflict: Aircraft requires minimum buffer time for deboarding, refueling, and inspection.';
        END IF;
    END IF;
END //

-- ----------------------------------------------------------------------------
-- Trigger 3: trg_verify_pilot_type_rating
-- Validates that operating flight deck crew hold active, unexpired endorsements
-- ----------------------------------------------------------------------------
CREATE TRIGGER `trg_verify_pilot_type_rating`
BEFORE INSERT ON `crew_duty_rosters`
FOR EACH ROW
BEGIN
    DECLARE v_model_id INT;
    DECLARE v_flight_dept DATETIME;
    DECLARE v_valid_rating_count INT DEFAULT 0;

    -- Only flight deck roles (Commander and Co-Pilot) require aircraft type certification
    IF NEW.roster_role IN ('Operating_Commander', 'Operating_CoPilot') THEN
        -- Determine aircraft model and flight departure timestamp
        SELECT af.model_id, sf.departure_datetime
        INTO v_model_id, v_flight_dept
        FROM `scheduled_flights` sf
        INNER JOIN `aircraft_fleet` af ON sf.aircraft_id = af.aircraft_id
        WHERE sf.flight_instance_id = NEW.flight_instance_id;

        -- Count valid, unexpired type ratings for this crew member on this specific model
        SELECT COUNT(*)
        INTO v_valid_rating_count
        FROM `aircraft_type_ratings`
        WHERE crew_id = NEW.crew_id
          AND model_id = v_model_id
          AND endorsement_date <= DATE(v_flight_dept)
          AND expiry_date >= DATE(v_flight_dept);

        IF v_valid_rating_count = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Type Rating Safety Violation: Pilot does not hold an active, unexpired type rating for this aircraft model.';
        END IF;
    END IF;
END //

DELIMITER ;
