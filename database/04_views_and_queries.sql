-- ============================================================================
-- AIRLINE FLIGHT DISPATCH & CREW ROSTERING DATABASE SYSTEM
-- Analytical Views & Viva-Ready Complex Queries
-- Target Database: MySQL 8.0+ (InnoDB Engine)
-- Script: 04_views_and_queries.sql
-- ============================================================================

USE `airline_dispatch_db`;

-- ----------------------------------------------------------------------------
-- VIEW 1: vw_live_ops_dispatch_board
-- Real-time operational dispatch board uniting route, airframe, PIC, and status
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS `vw_live_ops_dispatch_board`;
CREATE VIEW `vw_live_ops_dispatch_board` AS
SELECT
    sf.flight_instance_id,
    fr.flight_number,
    af.tail_number,
    am.model_name AS aircraft_model,
    CONCAT(orig.iata_code, ' - ', dest.iata_code) AS route_sector,
    orig.city AS origin_city,
    dest.city AS destination_city,
    sf.departure_datetime AS scheduled_departure,
    sf.arrival_datetime AS scheduled_arrival,
    sf.flight_status,
    sf.delay_minutes,
    COALESCE(CONCAT(cm.first_name, ' ', cm.last_name, ' (', cm.staff_code, ')'), 'UNASSIGNED') AS pilot_in_command,
    COALESCE(fdr.dispatch_clearance, 'Pending_Release') AS dispatch_status,
    COALESCE(fdr.planned_fuel_kg, 0.00) AS planned_fuel_kg,
    alt.iata_code AS alternate_airport
FROM `scheduled_flights` sf
INNER JOIN `flight_routes` fr ON sf.route_id = fr.route_id
INNER JOIN `airports` orig ON fr.origin_airport_id = orig.airport_id
INNER JOIN `airports` dest ON fr.destination_airport_id = dest.airport_id
INNER JOIN `aircraft_fleet` af ON sf.aircraft_id = af.aircraft_id
INNER JOIN `aircraft_models` am ON af.model_id = am.model_id
LEFT JOIN `crew_duty_rosters` cdr ON sf.flight_instance_id = cdr.flight_instance_id
    AND cdr.roster_role = 'Operating_Commander'
    AND cdr.assignment_status IN ('Assigned', 'Checked_In')
LEFT JOIN `crew_members` cm ON cdr.crew_id = cm.crew_id
LEFT JOIN `flight_dispatch_releases` fdr ON sf.flight_instance_id = fdr.flight_instance_id
LEFT JOIN `airports` alt ON fdr.alternate_airport_id = alt.airport_id;

-- ----------------------------------------------------------------------------
-- VIEW 2: vw_crew_utilization_fatigue_index
-- Tracks rolling 7-day workload, future assigned legs, and monthly limit exhaustion
-- (FAA/EASA Part 117 dictates a 100-hour cumulative flight duty limit per 28 days)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS `vw_crew_utilization_fatigue_index`;
CREATE VIEW `vw_crew_utilization_fatigue_index` AS
SELECT
    cm.crew_id,
    cm.staff_code,
    CONCAT(cm.first_name, ' ', cm.last_name) AS full_name,
    cm.crew_role,
    base.iata_code AS base_airport,
    cm.status AS current_crew_status,
    COALESCE(SUM(CASE
        WHEN sf.departure_datetime >= DATE_SUB(NOW(), INTERVAL 7 DAY)
         AND sf.departure_datetime <= NOW()
         AND cdr.assignment_status IN ('Assigned', 'Checked_In')
         AND sf.flight_status NOT IN ('Cancelled')
        THEN fr.block_time_minutes ELSE 0 END), 0) / 60.0 AS past_7day_block_hours,
    COUNT(DISTINCT CASE
        WHEN sf.departure_datetime > NOW()
         AND cdr.assignment_status = 'Assigned'
         AND sf.flight_status NOT IN ('Cancelled')
        THEN sf.flight_instance_id ELSE NULL END) AS upcoming_assigned_legs,
    ROUND(
        (COALESCE(SUM(CASE
            WHEN sf.departure_datetime >= DATE_SUB(NOW(), INTERVAL 28 DAY)
             AND sf.departure_datetime <= NOW()
             AND cdr.assignment_status IN ('Assigned', 'Checked_In')
             AND sf.flight_status NOT IN ('Cancelled')
            THEN fr.block_time_minutes ELSE 0 END), 0) / 60.0 / 100.0) * 100, 2
    ) AS monthly_duty_cap_utilization_pct
FROM `crew_members` cm
INNER JOIN `airports` base ON cm.base_airport_id = base.airport_id
LEFT JOIN `crew_duty_rosters` cdr ON cm.crew_id = cdr.crew_id
LEFT JOIN `scheduled_flights` sf ON cdr.flight_instance_id = sf.flight_instance_id
LEFT JOIN `flight_routes` fr ON sf.route_id = fr.route_id
GROUP BY
    cm.crew_id,
    cm.staff_code,
    cm.first_name,
    cm.last_name,
    cm.crew_role,
    base.iata_code,
    cm.status;

-- ============================================================================
-- 5 VIVA-READY COMPLEX ANALYTICAL QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- QUERY 1: Multi-Table Aggregation with HAVING Filter
-- Objective: Identify airports where outbound flights suffer average delays > 30 mins
-- Concepts Demonstrated: INNER JOIN, LEFT JOIN, Aggregation, HAVING filter
-- ----------------------------------------------------------------------------
SELECT
    orig.airport_id,
    orig.iata_code,
    orig.airport_name,
    orig.city,
    COUNT(sf.flight_instance_id) AS total_outbound_flights,
    COUNT(CASE WHEN sf.delay_minutes > 0 THEN 1 END) AS delayed_flights_count,
    ROUND(AVG(sf.delay_minutes), 2) AS avg_delay_minutes,
    MAX(sf.delay_minutes) AS max_single_delay_minutes
FROM `airports` orig
INNER JOIN `flight_routes` fr ON orig.airport_id = fr.origin_airport_id
INNER JOIN `scheduled_flights` sf ON fr.route_id = sf.route_id
WHERE sf.flight_status IN ('Departed', 'Arrived', 'Delayed')
GROUP BY
    orig.airport_id,
    orig.iata_code,
    orig.airport_name,
    orig.city
HAVING AVG(sf.delay_minutes) > 30.00
ORDER BY avg_delay_minutes DESC;

-- ----------------------------------------------------------------------------
-- QUERY 2: Anti-Join Pattern with NOT EXISTS
-- Objective: Detect certified standby Captains with 0 scheduled assignments in 14 days
-- Concepts Demonstrated: Subquery Anti-Join (NOT EXISTS), Date Arithmetics
-- ----------------------------------------------------------------------------
SELECT
    cm.crew_id,
    cm.staff_code,
    CONCAT(cm.first_name, ' ', cm.last_name) AS captain_name,
    base.iata_code AS home_base,
    cm.license_number,
    cm.total_flight_hours
FROM `crew_members` cm
INNER JOIN `airports` base ON cm.base_airport_id = base.airport_id
WHERE cm.crew_role = 'Captain'
  AND cm.status = 'Standby'
  AND NOT EXISTS (
      SELECT 1
      FROM `crew_duty_rosters` cdr
      INNER JOIN `scheduled_flights` sf ON cdr.flight_instance_id = sf.flight_instance_id
      WHERE cdr.crew_id = cm.crew_id
        AND cdr.assignment_status IN ('Assigned', 'Checked_In')
        AND sf.departure_datetime BETWEEN DATE_SUB(NOW(), INTERVAL 14 DAY) AND NOW()
  )
ORDER BY cm.total_flight_hours ASC;

-- ----------------------------------------------------------------------------
-- QUERY 3: Correlated Subquery
-- Objective: Detect flights where planned block time is longer than route median/average
-- Concepts Demonstrated: Correlated Subquery, Domain-Level Mathematical Comparison
-- ----------------------------------------------------------------------------
SELECT
    sf.flight_instance_id,
    fr.flight_number,
    CONCAT(orig.iata_code, ' -> ', dest.iata_code) AS sector,
    fr.block_time_minutes AS planned_block_minutes,
    sf.flight_status,
    ROUND((
        SELECT AVG(fr_inner.block_time_minutes)
        FROM `flight_routes` fr_inner
        WHERE fr_inner.origin_airport_id = fr.origin_airport_id
          AND fr_inner.destination_airport_id = fr.destination_airport_id
    ), 1) AS route_average_block_minutes
FROM `scheduled_flights` sf
INNER JOIN `flight_routes` fr ON sf.route_id = fr.route_id
INNER JOIN `airports` orig ON fr.origin_airport_id = orig.airport_id
INNER JOIN `airports` dest ON fr.destination_airport_id = dest.airport_id
WHERE fr.block_time_minutes >= (
    SELECT AVG(fr_sub.block_time_minutes)
    FROM `flight_routes` fr_sub
    WHERE fr_sub.origin_airport_id = fr.origin_airport_id
      AND fr_sub.destination_airport_id = fr.destination_airport_id
)
ORDER BY fr.block_time_minutes DESC;

-- ----------------------------------------------------------------------------
-- QUERY 4: Analytical Window Function (DENSE_RANK)
-- Objective: Rank individual fleet aircraft by cumulative hours partitioned by manufacturer
-- Concepts Demonstrated: Window Functions, PARTITION BY, DENSE_RANK()
-- ----------------------------------------------------------------------------
SELECT
    am.manufacturer,
    af.tail_number,
    am.model_name,
    af.manufacture_year,
    af.total_flight_hours,
    DENSE_RANK() OVER (
        PARTITION BY am.manufacturer
        ORDER BY af.total_flight_hours DESC
    ) AS utilization_rank_in_mfg,
    ROUND(AVG(af.total_flight_hours) OVER (
        PARTITION BY am.manufacturer
    ), 2) AS mfg_fleet_avg_hours
FROM `aircraft_fleet` af
INNER JOIN `aircraft_models` am ON af.model_id = am.model_id
ORDER BY am.manufacturer, utilization_rank_in_mfg;

-- ----------------------------------------------------------------------------
-- QUERY 5: Query Execution Plan & Optimizer Analysis (EXPLAIN ANALYZE)
-- Objective: Validate composite index usage on crew duty roster lookups
-- Concepts Demonstrated: EXPLAIN ANALYZE, Index Scan vs Table Scan, Cost Metrics
-- ----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    cdr.roster_id,
    cdr.flight_instance_id,
    cdr.crew_id,
    cdr.roster_role,
    cm.first_name,
    cm.last_name,
    sf.departure_datetime
FROM `crew_duty_rosters` cdr
INNER JOIN `crew_members` cm ON cdr.crew_id = cm.crew_id
INNER JOIN `scheduled_flights` sf ON cdr.flight_instance_id = sf.flight_instance_id
WHERE cdr.flight_instance_id = 1
  AND cdr.assignment_status = 'Assigned';
