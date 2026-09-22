-- ============================================================================
-- AIRLINE FLIGHT DISPATCH & CREW ROSTERING DATABASE SYSTEM
-- DDL Schema Definition (3NF Normalized)
-- Target Database: MySQL 8.0+ (InnoDB Engine)
-- Script: 01_schema.sql
-- ============================================================================

DROP DATABASE IF EXISTS `airline_dispatch_db`;
CREATE DATABASE `airline_dispatch_db`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `airline_dispatch_db`;

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- Table 1: airports
-- Stores commercial airport locations, IATA/ICAO identifiers, and time offsets
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `airports`;
CREATE TABLE `airports` (
    `airport_id` INT AUTO_INCREMENT PRIMARY KEY,
    `iata_code` CHAR(3) NOT NULL,
    `icao_code` CHAR(4) NOT NULL,
    `airport_name` VARCHAR(120) NOT NULL,
    `city` VARCHAR(80) NOT NULL,
    `country` VARCHAR(80) NOT NULL,
    `latitude` DECIMAL(9, 6) NOT NULL,
    `longitude` DECIMAL(9, 6) NOT NULL,
    `timezone_offset` DECIMAL(3, 1) NOT NULL DEFAULT 0.0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_airports_iata` UNIQUE (`iata_code`),
    CONSTRAINT `uq_airports_icao` UNIQUE (`icao_code`),
    CONSTRAINT `chk_timezone_offset` CHECK (`timezone_offset` BETWEEN -12.0 AND 14.0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 2: aircraft_models
-- Standardized aircraft performance and minimum operational crew specifications
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `aircraft_models`;
CREATE TABLE `aircraft_models` (
    `model_id` INT AUTO_INCREMENT PRIMARY KEY,
    `model_name` VARCHAR(50) NOT NULL,
    `manufacturer` ENUM('Boeing', 'Airbus', 'Embraer', 'Bombardier') NOT NULL,
    `seating_capacity` INT NOT NULL,
    `max_takeoff_weight_kg` DECIMAL(10, 2) NOT NULL,
    `fuel_capacity_kg` DECIMAL(10, 2) NOT NULL,
    `min_cockpit_crew` INT NOT NULL DEFAULT 2,
    `min_cabin_crew` INT NOT NULL,
    `min_turnaround_minutes` INT NOT NULL DEFAULT 45,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_aircraft_models_name` UNIQUE (`model_name`),
    CONSTRAINT `chk_seating_capacity` CHECK (`seating_capacity` > 0),
    CONSTRAINT `chk_min_cockpit_crew` CHECK (`min_cockpit_crew` >= 2),
    CONSTRAINT `chk_min_cabin_crew` CHECK (`min_cabin_crew` >= 2),
    CONSTRAINT `chk_min_turnaround` CHECK (`min_turnaround_minutes` >= 30)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 3: aircraft_fleet
-- Physical tail numbers and operational statuses in the airline's active fleet
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `aircraft_fleet`;
CREATE TABLE `aircraft_fleet` (
    `aircraft_id` INT AUTO_INCREMENT PRIMARY KEY,
    `tail_number` VARCHAR(10) NOT NULL,
    `model_id` INT NOT NULL,
    `manufacture_year` INT NOT NULL,
    `current_status` ENUM('Airborne', 'On_Ground', 'Maintenance', 'AOG') NOT NULL DEFAULT 'On_Ground',
    `base_airport_id` INT NOT NULL,
    `total_flight_hours` DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    `last_maintenance_date` DATE NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_fleet_tail_number` UNIQUE (`tail_number`),
    CONSTRAINT `chk_manufacture_year` CHECK (`manufacture_year` BETWEEN 1990 AND 2026),
    CONSTRAINT `fk_fleet_model` FOREIGN KEY (`model_id`)
        REFERENCES `aircraft_models` (`model_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_fleet_base_airport` FOREIGN KEY (`base_airport_id`)
        REFERENCES `airports` (`airport_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 4: flight_routes
-- City-pair commercial flight schedules, block time, and nautical miles
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `flight_routes`;
CREATE TABLE `flight_routes` (
    `route_id` INT AUTO_INCREMENT PRIMARY KEY,
    `flight_number` VARCHAR(10) NOT NULL,
    `origin_airport_id` INT NOT NULL,
    `destination_airport_id` INT NOT NULL,
    `scheduled_departure_time` TIME NOT NULL,
    `scheduled_arrival_time` TIME NOT NULL,
    `block_time_minutes` INT NOT NULL,
    `distance_nm` INT NOT NULL,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_flight_route_schedule` UNIQUE (`flight_number`, `scheduled_departure_time`),
    CONSTRAINT `chk_block_time` CHECK (`block_time_minutes` > 0),
    CONSTRAINT `chk_distance` CHECK (`distance_nm` > 0),
    CONSTRAINT `chk_origin_dest_diff` CHECK (`origin_airport_id` <> `destination_airport_id`),
    CONSTRAINT `fk_routes_origin` FOREIGN KEY (`origin_airport_id`)
        REFERENCES `airports` (`airport_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_routes_destination` FOREIGN KEY (`destination_airport_id`)
        REFERENCES `airports` (`airport_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 5: scheduled_flights
-- Concrete, date-specific flight instances assigned to physical airframes
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `scheduled_flights`;
CREATE TABLE `scheduled_flights` (
    `flight_instance_id` INT AUTO_INCREMENT PRIMARY KEY,
    `route_id` INT NOT NULL,
    `aircraft_id` INT NOT NULL,
    `departure_datetime` DATETIME NOT NULL,
    `arrival_datetime` DATETIME NOT NULL,
    `flight_status` ENUM('Scheduled', 'Boarding', 'Departed', 'Arrived', 'Delayed', 'Cancelled') NOT NULL DEFAULT 'Scheduled',
    `actual_departure` DATETIME NULL,
    `actual_arrival` DATETIME NULL,
    `delay_minutes` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_aircraft_departure` UNIQUE (`aircraft_id`, `departure_datetime`),
    CONSTRAINT `chk_arrival_after_departure` CHECK (`arrival_datetime` > `departure_datetime`),
    CONSTRAINT `chk_delay_minutes` CHECK (`delay_minutes` >= 0),
    CONSTRAINT `fk_flights_route` FOREIGN KEY (`route_id`)
        REFERENCES `flight_routes` (`route_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_flights_aircraft` FOREIGN KEY (`aircraft_id`)
        REFERENCES `aircraft_fleet` (`aircraft_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 6: crew_members
-- Licensed flight and cabin crew personnel profiles and operational statuses
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `crew_members`;
CREATE TABLE `crew_members` (
    `crew_id` INT AUTO_INCREMENT PRIMARY KEY,
    `staff_code` VARCHAR(15) NOT NULL,
    `first_name` VARCHAR(50) NOT NULL,
    `last_name` VARCHAR(50) NOT NULL,
    `crew_role` ENUM('Captain', 'First_Officer', 'Purser', 'Flight_Attendant') NOT NULL,
    `passport_number` VARCHAR(30) NOT NULL,
    `license_number` VARCHAR(40) NOT NULL,
    `base_airport_id` INT NOT NULL,
    `status` ENUM('Active', 'Standby', 'On_Leave', 'Suspended') NOT NULL DEFAULT 'Active',
    `total_flight_hours` DECIMAL(7, 2) NOT NULL DEFAULT 0.00,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_crew_staff_code` UNIQUE (`staff_code`),
    CONSTRAINT `uq_crew_passport` UNIQUE (`passport_number`),
    CONSTRAINT `uq_crew_license` UNIQUE (`license_number`),
    CONSTRAINT `fk_crew_base_airport` FOREIGN KEY (`base_airport_id`)
        REFERENCES `airports` (`airport_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 7: aircraft_type_ratings
-- Certification endorsements qualifying pilots to fly specific aircraft models
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `aircraft_type_ratings`;
CREATE TABLE `aircraft_type_ratings` (
    `crew_id` INT NOT NULL,
    `model_id` INT NOT NULL,
    `endorsement_date` DATE NOT NULL,
    `expiry_date` DATE NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`crew_id`, `model_id`),
    CONSTRAINT `chk_rating_expiry` CHECK (`expiry_date` > `endorsement_date`),
    CONSTRAINT `fk_ratings_crew` FOREIGN KEY (`crew_id`)
        REFERENCES `crew_members` (`crew_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_ratings_model` FOREIGN KEY (`model_id`)
        REFERENCES `aircraft_models` (`model_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 8: crew_duty_rosters
-- Duty assignments pairing crew members with specific scheduled flights
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `crew_duty_rosters`;
CREATE TABLE `crew_duty_rosters` (
    `roster_id` INT AUTO_INCREMENT PRIMARY KEY,
    `flight_instance_id` INT NOT NULL,
    `crew_id` INT NOT NULL,
    `roster_role` ENUM('Operating_Commander', 'Operating_CoPilot', 'Lead_Purser', 'Cabin_Crew') NOT NULL,
    `assignment_status` ENUM('Assigned', 'Checked_In', 'Standby_Swapped', 'Removed') NOT NULL DEFAULT 'Assigned',
    `checkin_time` DATETIME NULL,
    `assigned_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_flight_crew_assignment` UNIQUE (`flight_instance_id`, `crew_id`),
    CONSTRAINT `fk_roster_flight` FOREIGN KEY (`flight_instance_id`)
        REFERENCES `scheduled_flights` (`flight_instance_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_roster_crew` FOREIGN KEY (`crew_id`)
        REFERENCES `crew_members` (`crew_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 9: flight_dispatch_releases
-- Legal dispatch releases certifying fuel, weight, and weather authorization
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `flight_dispatch_releases`;
CREATE TABLE `flight_dispatch_releases` (
    `release_id` INT AUTO_INCREMENT PRIMARY KEY,
    `flight_instance_id` INT NOT NULL,
    `dispatcher_name` VARCHAR(100) NOT NULL,
    `planned_fuel_kg` DECIMAL(8, 2) NOT NULL,
    `alternate_airport_id` INT NOT NULL,
    `takeoff_weight_kg` DECIMAL(8, 2) NOT NULL,
    `dispatch_clearance` ENUM('Approved', 'Pending_Weather', 'Rejected') NOT NULL DEFAULT 'Approved',
    `released_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_dispatch_flight_instance` UNIQUE (`flight_instance_id`),
    CONSTRAINT `chk_planned_fuel` CHECK (`planned_fuel_kg` > 0),
    CONSTRAINT `chk_takeoff_weight` CHECK (`takeoff_weight_kg` > 0),
    CONSTRAINT `fk_dispatch_flight` FOREIGN KEY (`flight_instance_id`)
        REFERENCES `scheduled_flights` (`flight_instance_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_dispatch_alternate` FOREIGN KEY (`alternate_airport_id`)
        REFERENCES `airports` (`airport_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 10: crew_rest_periods
-- Regulatory rest period history and mandatory lockouts before subsequent duty
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `crew_rest_periods`;
CREATE TABLE `crew_rest_periods` (
    `rest_id` INT AUTO_INCREMENT PRIMARY KEY,
    `crew_id` INT NOT NULL,
    `last_duty_ended_at` DATETIME NOT NULL,
    `mandatory_rest_until` DATETIME NOT NULL,
    `rest_type` ENUM('Pre_Flight', 'Post_Flight', 'Weekly_Rest') NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_crew_rest_record` UNIQUE (`crew_id`, `last_duty_ended_at`),
    CONSTRAINT `chk_rest_interval` CHECK (`mandatory_rest_until` > `last_duty_ended_at`),
    CONSTRAINT `fk_rest_crew` FOREIGN KEY (`crew_id`)
        REFERENCES `crew_members` (`crew_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- Table 11: flight_operations_audit_logs
-- Immutable transactional audit trail for critical flight & safety events
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `flight_operations_audit_logs`;
CREATE TABLE `flight_operations_audit_logs` (
    `log_id` INT AUTO_INCREMENT PRIMARY KEY,
    `flight_instance_id` INT NULL,
    `crew_id` INT NULL,
    `event_type` ENUM('CREW_SWAPPED', 'DUTY_VIOLATION_BLOCKED', 'TURNAROUND_CLASH', 'FLIGHT_DELAYED', 'DISPATCH_APPROVED') NOT NULL,
    `remarks` TEXT NOT NULL,
    `logged_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_audit_flight` FOREIGN KEY (`flight_instance_id`)
        REFERENCES `scheduled_flights` (`flight_instance_id`)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT `fk_audit_crew` FOREIGN KEY (`crew_id`)
        REFERENCES `crew_members` (`crew_id`)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- High-Performance Composite and Operational Indexes
-- ----------------------------------------------------------------------------
CREATE INDEX `idx_flights_aircraft_dept` ON `scheduled_flights` (`aircraft_id`, `departure_datetime`);
CREATE INDEX `idx_flights_status_dept` ON `scheduled_flights` (`flight_status`, `departure_datetime`);
CREATE INDEX `idx_rosters_flight_role` ON `crew_duty_rosters` (`flight_instance_id`, `roster_role`);
CREATE INDEX `idx_rosters_crew_status` ON `crew_duty_rosters` (`crew_id`, `assignment_status`);
CREATE INDEX `idx_rest_crew_until` ON `crew_rest_periods` (`crew_id`, `mandatory_rest_until`);
CREATE INDEX `idx_routes_origin_dest` ON `flight_routes` (`origin_airport_id`, `destination_airport_id`);

SET FOREIGN_KEY_CHECKS = 1;
