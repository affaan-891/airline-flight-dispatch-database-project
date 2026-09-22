-- ============================================================================
-- AIRLINE FLIGHT DISPATCH & CREW ROSTERING DATABASE SYSTEM
-- Seed Data & Operational Population
-- Target Database: MySQL 8.0+ (InnoDB Engine)
-- Script: 05_seed_data.sql
-- ============================================================================

USE `airline_dispatch_db`;

-- Temporarily disable foreign key checks for clean truncation
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE `flight_operations_audit_logs`;
TRUNCATE TABLE `flight_dispatch_releases`;
TRUNCATE TABLE `crew_duty_rosters`;
TRUNCATE TABLE `crew_rest_periods`;
TRUNCATE TABLE `aircraft_type_ratings`;
TRUNCATE TABLE `crew_members`;
TRUNCATE TABLE `scheduled_flights`;
TRUNCATE TABLE `flight_routes`;
TRUNCATE TABLE `aircraft_fleet`;
TRUNCATE TABLE `aircraft_models`;
TRUNCATE TABLE `airports`;
SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 1. Populate Airports (6 Major Global Hubs)
-- ----------------------------------------------------------------------------
INSERT INTO `airports` (`airport_id`, `iata_code`, `icao_code`, `airport_name`, `city`, `country`, `latitude`, `longitude`, `timezone_offset`) VALUES
(1, 'DXB', 'OMDB', 'Dubai International Airport', 'Dubai', 'United Arab Emirates', 25.253200, 55.365700, 4.0),
(2, 'LHR', 'EGLL', 'London Heathrow Airport', 'London', 'United Kingdom', 51.470000, -0.454300, 0.0),
(3, 'JFK', 'KJFK', 'John F. Kennedy International Airport', 'New York', 'United States', 40.641300, -73.778100, -5.0),
(4, 'SIN', 'WSSS', 'Singapore Changi Airport', 'Singapore', 'Singapore', 1.364400, 103.991500, 8.0),
(5, 'DOH', 'OTHH', 'Hamad International Airport', 'Doha', 'Qatar', 25.273100, 51.608100, 3.0),
(6, 'KHI', 'OPKC', 'Jinnah International Airport', 'Karachi', 'Pakistan', 24.906500, 67.160800, 5.0);

-- ----------------------------------------------------------------------------
-- 2. Populate Aircraft Models (Commercial Jetliners)
-- ----------------------------------------------------------------------------
INSERT INTO `aircraft_models` (`model_id`, `model_name`, `manufacturer`, `seating_capacity`, `max_takeoff_weight_kg`, `fuel_capacity_kg`, `min_cockpit_crew`, `min_cabin_crew`, `min_turnaround_minutes`) VALUES
(1, 'Airbus A320neo', 'Airbus', 180, 79000.00, 19000.00, 2, 4, 45),
(2, 'Airbus A350-900', 'Airbus', 325, 280000.00, 110000.00, 2, 6, 60),
(3, 'Boeing 777-300ER', 'Boeing', 396, 351500.00, 145000.00, 2, 8, 75),
(4, 'Boeing 787-9 Dreamliner', 'Boeing', 290, 254000.00, 101000.00, 2, 6, 60);

-- ----------------------------------------------------------------------------
-- 3. Populate Aircraft Fleet (8 Physical Airframes)
-- ----------------------------------------------------------------------------
INSERT INTO `aircraft_fleet` (`aircraft_id`, `tail_number`, `model_id`, `manufacture_year`, `current_status`, `base_airport_id`, `total_flight_hours`, `last_maintenance_date`) VALUES
(1, 'A6-EPA', 3, 2018, 'On_Ground', 1, 14250.50, '2026-08-10'),
(2, 'A6-EPB', 3, 2020, 'Airborne',  1, 9820.25,  '2026-07-22'),
(3, 'A6-NEO', 1, 2021, 'On_Ground', 1, 6400.00,  '2026-09-01'),
(4, 'G-ZBKA', 4, 2019, 'On_Ground', 2, 11340.80, '2026-08-28'),
(5, '9V-SMA', 2, 2022, 'On_Ground', 4, 5100.20,  '2026-09-12'),
(6, 'A7-ALA', 2, 2021, 'On_Ground', 5, 7840.40,  '2026-08-15'),
(7, 'AP-BLA', 1, 2017, 'Maintenance', 6, 16800.00, '2026-09-18'),
(8, 'N801AN', 4, 2020, 'On_Ground', 3, 8950.60,  '2026-07-30');

-- ----------------------------------------------------------------------------
-- 4. Populate Flight Routes (10 International City-Pairs)
-- ----------------------------------------------------------------------------
INSERT INTO `flight_routes` (`route_id`, `flight_number`, `origin_airport_id`, `destination_airport_id`, `scheduled_departure_time`, `scheduled_arrival_time`, `block_time_minutes`, `distance_nm`, `is_active`) VALUES
(1,  'EK001', 1, 2, '07:45:00', '12:15:00', 450, 2999, 1), -- DXB -> LHR
(2,  'EK002', 2, 1, '14:20:00', '00:05:00', 405, 2999, 1), -- LHR -> DXB
(3,  'EK201', 1, 3, '08:30:00', '14:25:00', 835, 5970, 1), -- DXB -> JFK
(4,  'BA107', 2, 1, '12:40:00', '23:05:00', 445, 2999, 1), -- LHR -> DXB
(5,  'SQ322', 4, 2, '23:30:00', '05:55:00', 805, 5885, 1), -- SIN -> LHR
(6,  'QR003', 5, 2, '07:55:00', '13:15:00', 440, 2840, 1), -- DOH -> LHR
(7,  'PK213', 6, 1, '02:00:00', '03:30:00', 150, 642,  1), -- KHI -> DXB
(8,  'EK605', 1, 6, '21:50:00', '01:00:00', 130, 642,  1), -- DXB -> KHI
(9,  'AA100', 3, 2, '18:15:00', '06:20:00', 425, 3000, 1), -- JFK -> LHR
(10, 'SQ402', 4, 1, '09:00:00', '12:30:00', 450, 3160, 1); -- SIN -> DXB

-- ----------------------------------------------------------------------------
-- 5. Populate Scheduled Flight Instances (16 Specific Flights)
-- Note: Spaced beyond aircraft min turnaround buffer to respect turnaround trigger
-- ----------------------------------------------------------------------------
INSERT INTO `scheduled_flights` (`flight_instance_id`, `route_id`, `aircraft_id`, `departure_datetime`, `arrival_datetime`, `flight_status`, `actual_departure`, `actual_arrival`, `delay_minutes`) VALUES
-- Aircraft 1 (B777-300ER: A6-EPA)
(1,  1, 1, '2026-10-10 07:45:00', '2026-10-10 15:15:00', 'Arrived',   '2026-10-10 07:50:00', '2026-10-10 15:20:00', 5),
(2,  2, 1, '2026-10-10 17:30:00', '2026-10-11 00:15:00', 'Arrived',   '2026-10-10 17:30:00', '2026-10-11 00:15:00', 0),
(3,  3, 1, '2026-10-11 08:30:00', '2026-10-11 22:25:00', 'Departed',  '2026-10-11 09:15:00', NULL,                  45),

-- Aircraft 2 (B777-300ER: A6-EPB)
(4,  1, 2, '2026-10-12 07:45:00', '2026-10-12 15:15:00', 'Scheduled', NULL, NULL, 0),
(5,  2, 2, '2026-10-12 18:00:00', '2026-10-13 00:45:00', 'Scheduled', NULL, NULL, 0),

-- Aircraft 3 (A320neo: A6-NEO)
(6,  8, 3, '2026-10-10 21:50:00', '2026-10-11 00:00:00', 'Arrived',   '2026-10-10 21:50:00', '2026-10-11 00:00:00', 0),
(7,  7, 3, '2026-10-11 02:00:00', '2026-10-11 04:30:00', 'Arrived',   '2026-10-11 02:35:00', '2026-10-11 05:05:00', 35),
(8,  8, 3, '2026-10-12 21:50:00', '2026-10-13 00:00:00', 'Scheduled', NULL, NULL, 0),

-- Aircraft 4 (B787-9: G-ZBKA)
(9,  4, 4, '2026-10-10 12:40:00', '2026-10-10 20:05:00', 'Arrived',   '2026-10-10 13:40:00', '2026-10-10 21:05:00', 60),
(10, 2, 4, '2026-10-11 14:20:00', '2026-10-11 21:05:00', 'Scheduled', NULL, NULL, 0),

-- Aircraft 5 (A350-900: 9V-SMA)
(11, 5, 5, '2026-10-10 23:30:00', '2026-10-11 12:55:00', 'Arrived',   '2026-10-10 23:30:00', '2026-10-11 12:55:00', 0),
(12, 10, 5, '2026-10-12 09:00:00', '2026-10-12 16:30:00', 'Scheduled', NULL, NULL, 0),

-- Aircraft 6 (A350-900: A7-ALA)
(13, 6, 6, '2026-10-10 07:55:00', '2026-10-10 15:15:00', 'Arrived',   '2026-10-10 08:00:00', '2026-10-10 15:20:00', 5),
(14, 6, 6, '2026-10-12 07:55:00', '2026-10-12 15:15:00', 'Scheduled', NULL, NULL, 0),

-- Aircraft 8 (B787-9: N801AN)
(15, 9, 8, '2026-10-10 18:15:00', '2026-10-11 01:20:00', 'Arrived',   '2026-10-10 18:45:00', '2026-10-11 01:50:00', 30),
(16, 9, 8, '2026-10-12 18:15:00', '2026-10-13 01:20:00', 'Delayed',   NULL, NULL, 50);

-- ----------------------------------------------------------------------------
-- 6. Populate Flight Crew Members (20 Licensed Professionals)
-- ----------------------------------------------------------------------------
INSERT INTO `crew_members` (`crew_id`, `staff_code`, `first_name`, `last_name`, `crew_role`, `passport_number`, `license_number`, `base_airport_id`, `status`, `total_flight_hours`) VALUES
-- Captains
(1,  'PLT-1001', 'Tariq',    'Al-Mansoor', 'Captain',         'P9823411', 'ATPL-UAE-77701', 1, 'Active',  9540.00),
(2,  'PLT-1002', 'James',    'Wilson',     'Captain',         'P4412098', 'ATPL-UK-78702',  2, 'Active',  11200.50),
(3,  'PLT-1003', 'Wei',      'Chen',       'Captain',         'P7712390', 'ATPL-SG-35003',  4, 'Active',  8700.25),
(4,  'PLT-1004', 'Salman',   'Baig',       'Captain',         'P6655123', 'ATPL-PK-32004',  6, 'Active',  6950.00),
(5,  'PLT-1005', 'Hamad',    'Al-Thani',   'Captain',         'P3399001', 'ATPL-QA-35005',  5, 'Active',  7800.00),
(6,  'PLT-1006', 'Robert',   'Miller',     'Captain',         'P1122334', 'ATPL-US-77706',  1, 'Standby', 8120.00), -- Standby Captain in DXB

-- First Officers
(7,  'PLT-2001', 'Zaid',     'Qureshi',    'First_Officer',   'P8877112', 'CPL-UAE-77711',  1, 'Active',  4100.00),
(8,  'PLT-2002', 'Oliver',   'Davies',     'First_Officer',   'P5566223', 'CPL-UK-78712',   2, 'Active',  3850.50),
(9,  'PLT-2003', 'Fahad',    'Khan',       'First_Officer',   'P9900112', 'CPL-PK-32013',   6, 'Active',  2900.00),
(10, 'PLT-2004', 'Siddharth','Pillai',     'First_Officer',   'P2233445', 'CPL-SG-35014',   4, 'Active',  3400.00),
(11, 'PLT-2005', 'Arthur',   'Harris',     'First_Officer',   'P6677889', 'CPL-US-77715',   1, 'Standby', 3150.00), -- Standby FO in DXB

-- Pursers (Cabin Leadership)
(12, 'CAB-3001', 'Fatima',   'Hassan',     'Purser',          'P4488331', 'CC-UAE-5501',    1, 'Active',  5200.00),
(13, 'CAB-3002', 'Emma',     'Taylor',     'Purser',          'P7722119', 'CC-UK-5502',     2, 'Active',  6100.00),
(14, 'CAB-3003', 'Hui',      'Ling',       'Purser',          'P9911442', 'CC-SG-5503',     4, 'Active',  4800.00),
(15, 'CAB-3004', 'Nour',     'El-Din',     'Purser',          'P3366992', 'CC-QA-5504',     5, 'Active',  5450.00),
(16, 'CAB-3005', 'Samina',   'Rashid',     'Purser',          'P1239874', 'CC-PK-5505',     1, 'Standby', 4300.00), -- Standby Purser in DXB

-- Flight Attendants
(17, 'CAB-4001', 'Elena',    'Rostova',    'Flight_Attendant','P5511778', 'CC-UAE-9001',    1, 'Active',  3100.00),
(18, 'CAB-4002', 'Liam',     'Johnson',    'Flight_Attendant','P4499221', 'CC-UK-9002',     2, 'Active',  2750.00),
(19, 'CAB-4003', 'Ayesha',   'Malik',      'Flight_Attendant','P6622883', 'CC-PK-9003',     6, 'Active',  1950.00),
(20, 'CAB-4004', 'Carlos',   'Gomez',      'Flight_Attendant','P8844332', 'CC-US-9004',     1, 'Standby', 2400.00); -- Standby Attendant in DXB

-- ----------------------------------------------------------------------------
-- 7. Populate Aircraft Type Ratings (Pilot Certifications)
-- Required BEFORE inserting flight crew rosters to satisfy type rating trigger
-- ----------------------------------------------------------------------------
INSERT INTO `aircraft_type_ratings` (`crew_id`, `model_id`, `endorsement_date`, `expiry_date`) VALUES
-- Captains
(1, 3, '2023-01-15', '2027-01-15'), -- Tariq: B777-300ER
(1, 4, '2023-06-10', '2027-06-10'), -- Tariq: B787-9
(2, 4, '2022-04-20', '2026-12-31'), -- James: B787-9
(3, 2, '2023-09-01', '2027-09-01'), -- Wei: A350-900
(4, 1, '2021-11-15', '2026-11-15'), -- Salman: A320neo
(5, 2, '2022-08-10', '2026-12-31'), -- Hamad: A350-900
(6, 3, '2023-03-01', '2027-03-01'), -- Robert (Standby): B777-300ER
(6, 1, '2022-05-15', '2026-12-31'), -- Robert (Standby): A320neo

-- First Officers
(7, 3, '2023-02-10', '2027-02-10'), -- Zaid: B777-300ER
(8, 4, '2023-05-18', '2027-05-18'), -- Oliver: B787-9
(9, 1, '2022-10-01', '2026-12-31'), -- Fahad: A320neo
(10, 2, '2023-07-25', '2027-07-25'), -- Siddharth: A350-900
(11, 3, '2023-04-12', '2027-04-12'); -- Arthur (Standby): B777-300ER

-- ----------------------------------------------------------------------------
-- 8. Populate Crew Rest Periods (Regulatory Rest Logs)
-- Ensures rest periods expired well before assigned flight departures
-- ----------------------------------------------------------------------------
INSERT INTO `crew_rest_periods` (`rest_id`, `crew_id`, `last_duty_ended_at`, `mandatory_rest_until`, `rest_type`) VALUES
(1, 1,  '2026-10-08 18:00:00', '2026-10-09 06:00:00', 'Post_Flight'),
(2, 7,  '2026-10-08 19:00:00', '2026-10-09 07:00:00', 'Post_Flight'),
(3, 12, '2026-10-08 20:00:00', '2026-10-09 08:00:00', 'Post_Flight'),
(4, 17, '2026-10-08 20:00:00', '2026-10-09 08:00:00', 'Post_Flight'),
(5, 6,  '2026-10-07 12:00:00', '2026-10-08 00:00:00', 'Weekly_Rest'),  -- Standby Captain
(6, 11, '2026-10-07 14:00:00', '2026-10-08 02:00:00', 'Weekly_Rest'),  -- Standby FO
(7, 2,  '2026-10-08 10:00:00', '2026-10-08 22:00:00', 'Post_Flight'),
(8, 8,  '2026-10-08 11:00:00', '2026-10-08 23:00:00', 'Post_Flight'),
(9, 3,  '2026-10-08 15:00:00', '2026-10-09 03:00:00', 'Post_Flight'),
(10, 4, '2026-10-09 10:00:00', '2026-10-09 22:00:00', 'Post_Flight');

-- ----------------------------------------------------------------------------
-- 9. Populate Crew Duty Rosters (Flight Crew Pairings)
-- ----------------------------------------------------------------------------
INSERT INTO `crew_duty_rosters` (`roster_id`, `flight_instance_id`, `crew_id`, `roster_role`, `assignment_status`, `checkin_time`) VALUES
-- Flight 1 (DXB -> LHR, B777-300ER: A6-EPA, Departed 2026-10-10 07:45:00)
(1,  1, 1,  'Operating_Commander', 'Checked_In', '2026-10-10 06:15:00'),
(2,  1, 7,  'Operating_CoPilot',   'Checked_In', '2026-10-10 06:15:00'),
(3,  1, 12, 'Lead_Purser',         'Checked_In', '2026-10-10 06:00:00'),
(4,  1, 17, 'Cabin_Crew',          'Checked_In', '2026-10-10 06:00:00'),

-- Flight 4 (DXB -> LHR, B777-300ER: A6-EPB, Scheduled 2026-10-12 07:45:00)
(5,  4, 1,  'Operating_Commander', 'Assigned',   NULL),
(6,  4, 7,  'Operating_CoPilot',   'Assigned',   NULL),
(7,  4, 12, 'Lead_Purser',         'Assigned',   NULL),
(8,  4, 17, 'Cabin_Crew',          'Assigned',   NULL),

-- Flight 9 (LHR -> DXB, B787-9: G-ZBKA, Departed 2026-10-10 12:40:00)
(9,  9, 2,  'Operating_Commander', 'Checked_In', '2026-10-10 11:10:00'),
(10, 9, 8,  'Operating_CoPilot',   'Checked_In', '2026-10-10 11:10:00'),
(11, 9, 13, 'Lead_Purser',         'Checked_In', '2026-10-10 11:00:00'),
(12, 9, 18, 'Cabin_Crew',          'Checked_In', '2026-10-10 11:00:00'),

-- Flight 11 (SIN -> LHR, A350-900: 9V-SMA, Departed 2026-10-10 23:30:00)
(13, 11, 3,  'Operating_Commander', 'Checked_In', '2026-10-10 22:00:00'),
(14, 11, 10, 'Operating_CoPilot',   'Checked_In', '2026-10-10 22:00:00'),
(15, 11, 14, 'Lead_Purser',         'Checked_In', '2026-10-10 21:45:00'),

-- Flight 7 (KHI -> DXB, A320neo: A6-NEO, Arrived 2026-10-11 02:00:00)
(16, 7, 4,  'Operating_Commander', 'Checked_In', '2026-10-11 00:30:00'),
(17, 7, 9,  'Operating_CoPilot',   'Checked_In', '2026-10-11 00:30:00'),
(18, 7, 19, 'Cabin_Crew',          'Checked_In', '2026-10-11 00:30:00');

-- ----------------------------------------------------------------------------
-- 10. Populate Flight Dispatch Releases
-- ----------------------------------------------------------------------------
INSERT INTO `flight_dispatch_releases` (`release_id`, `flight_instance_id`, `dispatcher_name`, `planned_fuel_kg`, `alternate_airport_id`, `takeoff_weight_kg`, `dispatch_clearance`, `released_at`) VALUES
(1, 1,  'Marcus Vance (DXB-DISP-01)', 88500.00, 2, 335000.00, 'Approved', '2026-10-10 05:45:00'),
(2, 4,  'Marcus Vance (DXB-DISP-01)', 89200.00, 2, 336500.00, 'Approved', '2026-10-12 05:30:00'),
(3, 9,  'Sarah Jenkins (LHR-DISP-04)', 64000.00, 1, 238000.00, 'Approved', '2026-10-10 10:30:00'),
(4, 11, 'Tan Boon Keat (SIN-DISP-02)', 98000.00, 2, 272000.00, 'Approved', '2026-10-10 21:00:00'),
(5, 7,  'Rashid Mehmood (KHI-DISP-01)', 9500.00,  1, 68500.00,  'Approved', '2026-10-11 00:15:00');

-- ----------------------------------------------------------------------------
-- 11. Populate Flight Operations Audit Logs
-- ----------------------------------------------------------------------------
INSERT INTO `flight_operations_audit_logs` (`log_id`, `flight_instance_id`, `crew_id`, `event_type`, `remarks`, `logged_at`) VALUES
(1, 1,  NULL, 'DISPATCH_APPROVED', 'OFP signed by Marcus Vance. Weather minima checked at LHR and alternates.', '2026-10-10 05:45:10'),
(2, 9,  NULL, 'FLIGHT_DELAYED',    'Air Traffic Control slot restriction over European airspace. Departure revised +60m.', '2026-10-10 12:15:00'),
(3, 7,  NULL, 'FLIGHT_DELAYED',    'Ground handling baggage conveyor failure at Jinnah International. Delay +35m.', '2026-10-11 01:45:00'),
(4, 4,  NULL, 'DISPATCH_APPROVED', 'Dispatch package prepared for DXB-LHR sector. Aircraft A6-EPB cleared.', '2026-10-12 05:30:00');
