-- ============================================================================
-- AIRLINE FLIGHT DISPATCH & CREW ROSTERING DATABASE SYSTEM
-- Stored Procedures & Functions (ACID Transactions & Operations)
-- Target Database: MySQL 8.0+ (InnoDB Engine)
-- Script: 03_procedures.sql
-- ============================================================================

USE `airline_dispatch_db`;

DROP PROCEDURE IF EXISTS `sp_swap_unfit_crew_with_standby`;
DROP PROCEDURE IF EXISTS `sp_generate_flight_dispatch_release`;
DROP FUNCTION IF EXISTS `fn_calculate_crew_rolling_duty_hours`;

DELIMITER //

-- ----------------------------------------------------------------------------
-- Stored Procedure: sp_swap_unfit_crew_with_standby
-- Atomically swaps an unfit crew member with an eligible standby crew candidate.
-- Demonstrates Pessimistic Locking (SELECT ... FOR UPDATE) & ACID Rollback.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE `sp_swap_unfit_crew_with_standby` (
    IN  p_flight_instance_id INT,
    IN  p_unfit_crew_id      INT,
    OUT p_replacement_crew_id INT,
    OUT p_status_message     VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_model_id INT;
    DECLARE v_origin_airport_id INT;
    DECLARE v_flight_dept DATETIME;
    DECLARE v_roster_role ENUM('Operating_Commander', 'Operating_CoPilot', 'Lead_Purser', 'Cabin_Crew');
    DECLARE v_crew_general_role ENUM('Captain', 'First_Officer', 'Purser', 'Flight_Attendant');
    DECLARE v_selected_standby_id INT DEFAULT NULL;

    -- Declare handler for any SQL exception to maintain ACID atomicity
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_replacement_crew_id = NULL;
        SET p_status_message = 'ERROR: Transaction aborted. Rollback executed due to SQL execution failure.';
    END;

    START TRANSACTION;

    -- 1. Validate the flight instance exists and acquire row lock
    SELECT sf.departure_datetime, fr.origin_airport_id, af.model_id
    INTO v_flight_dept, v_origin_airport_id, v_model_id
    FROM `scheduled_flights` sf
    INNER JOIN `flight_routes` fr ON sf.route_id = fr.route_id
    INNER JOIN `aircraft_fleet` af ON sf.aircraft_id = af.aircraft_id
    WHERE sf.flight_instance_id = p_flight_instance_id
    FOR UPDATE;

    IF v_flight_dept IS NULL THEN
        ROLLBACK;
        SET p_replacement_crew_id = NULL;
        SET p_status_message = 'ERROR: Scheduled flight instance not found.';
        LEAVE proc_label;
    END IF;

    -- 2. Verify that the unfit crew is currently assigned to this flight
    SELECT roster_role
    INTO v_roster_role
    FROM `crew_duty_rosters`
    WHERE flight_instance_id = p_flight_instance_id
      AND crew_id = p_unfit_crew_id
      AND assignment_status IN ('Assigned', 'Checked_In')
    FOR UPDATE;

    IF v_roster_role IS NULL THEN
        ROLLBACK;
        SET p_replacement_crew_id = NULL;
        SET p_status_message = 'ERROR: Unfit crew member is not assigned or active on this flight instance.';
        LEAVE proc_label;
    END IF;

    -- Map roster role to general crew qualification role
    CASE v_roster_role
        WHEN 'Operating_Commander' THEN SET v_crew_general_role = 'Captain';
        WHEN 'Operating_CoPilot'   THEN SET v_crew_general_role = 'First_Officer';
        WHEN 'Lead_Purser'         THEN SET v_crew_general_role = 'Purser';
        WHEN 'Cabin_Crew'          THEN SET v_crew_general_role = 'Flight_Attendant';
    END CASE;

    -- 3. Search and lock an eligible standby crew candidate
    -- Criteria:
    -- - Status is 'Standby'
    -- - Base airport matches departure airport
    -- - General role matches required roster role
    -- - For pilots: Holds an active, unexpired type rating for this aircraft model
    -- - Meets mandatory rest period clearance (no unexpired rest lockout)
    SELECT cm.crew_id
    INTO v_selected_standby_id
    FROM `crew_members` cm
    WHERE cm.status = 'Standby'
      AND cm.base_airport_id = v_origin_airport_id
      AND cm.crew_role = v_crew_general_role
      AND (
          v_roster_role NOT IN ('Operating_Commander', 'Operating_CoPilot')
          OR EXISTS (
              SELECT 1 FROM `aircraft_type_ratings` atr
              WHERE atr.crew_id = cm.crew_id
                AND atr.model_id = v_model_id
                AND atr.endorsement_date <= DATE(v_flight_dept)
                AND atr.expiry_date >= DATE(v_flight_dept)
          )
      )
      AND NOT EXISTS (
          SELECT 1 FROM `crew_rest_periods` crp
          WHERE crp.crew_id = cm.crew_id
            AND crp.last_duty_ended_at <= v_flight_dept
            AND crp.mandatory_rest_until > v_flight_dept
      )
    ORDER BY cm.total_flight_hours ASC
    LIMIT 1
    FOR UPDATE;

    IF v_selected_standby_id IS NULL THEN
        ROLLBACK;
        SET p_replacement_crew_id = NULL;
        SET p_status_message = 'ERROR: No qualified, rested standby crew member available at origin airport.';
        LEAVE proc_label;
    END IF;

    -- 4. Update the unfit crew roster record to 'Standby_Swapped'
    UPDATE `crew_duty_rosters`
    SET assignment_status = 'Standby_Swapped'
    WHERE flight_instance_id = p_flight_instance_id
      AND crew_id = p_unfit_crew_id;

    -- Mark unfit crew status as Suspended pending review
    UPDATE `crew_members`
    SET status = 'Suspended'
    WHERE crew_id = p_unfit_crew_id;

    -- 5. Insert new assignment for replacement standby crew
    INSERT INTO `crew_duty_rosters` (
        flight_instance_id,
        crew_id,
        roster_role,
        assignment_status,
        checkin_time
    ) VALUES (
        p_flight_instance_id,
        v_selected_standby_id,
        v_roster_role,
        'Assigned',
        NOW()
    );

    -- 6. Transition standby crew status to 'Active'
    UPDATE `crew_members`
    SET status = 'Active'
    WHERE crew_id = v_selected_standby_id;

    -- 7. Record immutable audit log
    INSERT INTO `flight_operations_audit_logs` (
        flight_instance_id,
        crew_id,
        event_type,
        remarks
    ) VALUES (
        p_flight_instance_id,
        v_selected_standby_id,
        'CREW_SWAPPED',
        CONCAT('Crew ID ', p_unfit_crew_id, ' marked unfit. Successfully substituted with Standby Crew ID ', v_selected_standby_id, ' for role ', v_roster_role, '.')
    );

    COMMIT;

    SET p_replacement_crew_id = v_selected_standby_id;
    SET p_status_message = CONCAT('SUCCESS: Crew member swapped successfully. New assigned crew ID is ', v_selected_standby_id);
END //

-- ----------------------------------------------------------------------------
-- Stored Procedure: sp_generate_flight_dispatch_release
-- Legal dispatch flight release validation and generation.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE `sp_generate_flight_dispatch_release` (
    IN  p_flight_instance_id INT,
    IN  p_dispatcher_name    VARCHAR(100),
    IN  p_planned_fuel_kg    DECIMAL(8, 2),
    IN  p_alternate_airport_id INT,
    IN  p_takeoff_weight_kg  DECIMAL(8, 2),
    OUT p_release_id         INT,
    OUT p_clearance_status   VARCHAR(50)
)
release_proc: BEGIN
    DECLARE v_max_tow DECIMAL(10, 2);
    DECLARE v_fuel_cap DECIMAL(10, 2);
    DECLARE v_min_cockpit INT;
    DECLARE v_min_cabin INT;
    DECLARE v_assigned_cockpit INT DEFAULT 0;
    DECLARE v_assigned_cabin INT DEFAULT 0;
    DECLARE v_flight_status ENUM('Scheduled', 'Boarding', 'Departed', 'Arrived', 'Delayed', 'Cancelled');
    DECLARE v_origin_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_release_id = NULL;
        SET p_clearance_status = 'REJECTED: Transaction error during dispatch release generation.';
    END;

    START TRANSACTION;

    -- 1. Inspect physical aircraft limitations and flight route
    SELECT am.max_takeoff_weight_kg, am.fuel_capacity_kg, am.min_cockpit_crew, am.min_cabin_crew,
           sf.flight_status, fr.origin_airport_id
    INTO v_max_tow, v_fuel_cap, v_min_cockpit, v_min_cabin, v_flight_status, v_origin_id
    FROM `scheduled_flights` sf
    INNER JOIN `aircraft_fleet` af ON sf.aircraft_id = af.aircraft_id
    INNER JOIN `aircraft_models` am ON af.model_id = am.model_id
    INNER JOIN `flight_routes` fr ON sf.route_id = fr.route_id
    WHERE sf.flight_instance_id = p_flight_instance_id
    FOR UPDATE;

    -- Check flight existence
    IF v_max_tow IS NULL THEN
        ROLLBACK;
        SET p_release_id = NULL;
        SET p_clearance_status = 'REJECTED: Scheduled flight instance does not exist.';
        LEAVE release_proc;
    END IF;

    -- Verify alternate airport is different from origin airport
    IF p_alternate_airport_id = v_origin_id THEN
        ROLLBACK;
        SET p_release_id = NULL;
        SET p_clearance_status = 'REJECTED: Alternate airport cannot be identical to origin airport.';
        LEAVE release_proc;
    END IF;

    -- 2. Validate Takeoff Weight Envelope
    IF p_takeoff_weight_kg > v_max_tow THEN
        ROLLBACK;
        SET p_release_id = NULL;
        SET p_clearance_status = CONCAT('REJECTED: Takeoff weight exceeds MTOW limit of ', v_max_tow, ' kg.');
        LEAVE release_proc;
    END IF;

    -- 3. Validate Planned Fuel Envelope
    IF p_planned_fuel_kg > v_fuel_cap THEN
        ROLLBACK;
        SET p_release_id = NULL;
        SET p_clearance_status = CONCAT('REJECTED: Planned fuel exceeds tank capacity of ', v_fuel_cap, ' kg.');
        LEAVE release_proc;
    END IF;

    -- 4. Validate Minimum Crew Quorum (Cockpit and Cabin)
    SELECT
        COALESCE(SUM(CASE WHEN roster_role IN ('Operating_Commander', 'Operating_CoPilot') THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN roster_role IN ('Lead_Purser', 'Cabin_Crew') THEN 1 ELSE 0 END), 0)
    INTO v_assigned_cockpit, v_assigned_cabin
    FROM `crew_duty_rosters`
    WHERE flight_instance_id = p_flight_instance_id
      AND assignment_status IN ('Assigned', 'Checked_In');

    IF v_assigned_cockpit < v_min_cockpit THEN
        ROLLBACK;
        SET p_release_id = NULL;
        SET p_clearance_status = CONCAT('REJECTED: Inadequate flight deck crew. Required: ', v_min_cockpit, ', Assigned: ', v_assigned_cockpit);
        LEAVE release_proc;
    END IF;

    IF v_assigned_cabin < v_min_cabin THEN
        ROLLBACK;
        SET p_release_id = NULL;
        SET p_clearance_status = CONCAT('REJECTED: Inadequate cabin crew. Required: ', v_min_cabin, ', Assigned: ', v_assigned_cabin);
        LEAVE release_proc;
    END IF;

    -- 5. Insert Dispatch Release
    INSERT INTO `flight_dispatch_releases` (
        flight_instance_id,
        dispatcher_name,
        planned_fuel_kg,
        alternate_airport_id,
        takeoff_weight_kg,
        dispatch_clearance
    ) VALUES (
        p_flight_instance_id,
        p_dispatcher_name,
        p_planned_fuel_kg,
        p_alternate_airport_id,
        p_takeoff_weight_kg,
        'Approved'
    )
    ON DUPLICATE KEY UPDATE
        dispatcher_name = VALUES(dispatcher_name),
        planned_fuel_kg = VALUES(planned_fuel_kg),
        alternate_airport_id = VALUES(alternate_airport_id),
        takeoff_weight_kg = VALUES(takeoff_weight_kg),
        dispatch_clearance = 'Approved',
        released_at = CURRENT_TIMESTAMP;

    SET p_release_id = LAST_INSERT_ID();

    -- 6. Log Audit Event
    INSERT INTO `flight_operations_audit_logs` (
        flight_instance_id,
        crew_id,
        event_type,
        remarks
    ) VALUES (
        p_flight_instance_id,
        NULL,
        'DISPATCH_APPROVED',
        CONCAT('Flight dispatch released by ', p_dispatcher_name, '. Fuel: ', p_planned_fuel_kg, ' kg, TOW: ', p_takeoff_weight_kg, ' kg.')
    );

    COMMIT;

    SET p_clearance_status = 'APPROVED';
END //

-- ----------------------------------------------------------------------------
-- Stored Function: fn_calculate_crew_rolling_duty_hours
-- Returns accumulated block hours for a crew member over the preceding 7 days
-- ----------------------------------------------------------------------------
CREATE FUNCTION `fn_calculate_crew_rolling_duty_hours` (
    p_crew_id INT,
    p_reference_datetime DATETIME
)
RETURNS DECIMAL(6, 2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total_minutes INT DEFAULT 0;
    DECLARE v_window_start DATETIME;

    SET v_window_start = DATE_SUB(p_reference_datetime, INTERVAL 7 DAY);

    SELECT COALESCE(SUM(fr.block_time_minutes), 0)
    INTO v_total_minutes
    FROM `crew_duty_rosters` cdr
    INNER JOIN `scheduled_flights` sf ON cdr.flight_instance_id = sf.flight_instance_id
    INNER JOIN `flight_routes` fr ON sf.route_id = fr.route_id
    WHERE cdr.crew_id = p_crew_id
      AND cdr.assignment_status IN ('Assigned', 'Checked_In')
      AND sf.flight_status NOT IN ('Cancelled')
      AND sf.departure_datetime >= v_window_start
      AND sf.departure_datetime <= p_reference_datetime;

    RETURN ROUND(v_total_minutes / 60.0, 2);
END //

DELIMITER ;
