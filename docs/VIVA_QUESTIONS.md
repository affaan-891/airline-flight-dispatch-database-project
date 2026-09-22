# Comprehensive Viva Voce Examination Guide
## Airline Flight Dispatch & Crew Rostering Database System

This document contains 10 rigorous technical viva questions and evaluator-grade model answers designed for defense before university DBMS professors, external examiners, and technical evaluators.

---

### Question 1: How does the schema guarantee Third Normal Form (3NF) and eliminate data redundancy across Flight Routes and Scheduled Flights?

#### Examiner's Focus:
Evaluation of candidate's grasp on Functional Dependencies, Transitive Dependencies, and separation between abstract schedules and physical operational instances.

#### Model Answer:
The architecture strictly separates the **abstract flight route definition** (`flight_routes`) from the **concrete, date-specific flight instance** (`scheduled_flights`):

1. **First Normal Form (1NF)**: Every table has a distinct primary key, all attributes are atomic, and there are no repeating groups or multi-valued columns.
2. **Second Normal Form (2NF)**: In `flight_routes`, the primary key is `route_id`. All non-key attributes (`flight_number`, `origin_airport_id`, `destination_airport_id`, `scheduled_departure_time`, `block_time_minutes`, `distance_nm`) are fully functionally dependent on the primary key:
   $$\{ \text{route\_id} \} \to \{ \text{flight\_number}, \text{origin}, \text{dest}, \text{block\_time}, \text{distance} \}$$
   There are no partial dependencies on any composite candidate keys.
3. **Third Normal Form (3NF)**: In `scheduled_flights`, the primary key is `flight_instance_id`. The table stores only operational variables unique to that execution (`departure_datetime`, `arrival_datetime`, `aircraft_id`, `actual_departure`, `actual_arrival`, `delay_minutes`, `flight_status`). It links to `route_id` via a foreign key.
   - If we stored the route's `origin_airport_id`, `destination_airport_id`, or `distance_nm` directly in `scheduled_flights`, there would be a transitive dependency:
     $$\text{flight\_instance\_id} \to \text{route\_id} \to \text{origin\_airport\_id}$$
   - By eliminating transitive dependencies and storing route data in `flight_routes`, any adjustment to the standard route or scheduled block time requires updating exactly **one** record, eliminating update, insertion, and deletion anomalies.

---

### Question 2: Explain how the trigger `trg_enforce_fdp_and_mandatory_rest` mathematically validates the rolling 24-hour Flight Duty Period (FDP). Why is this handled in a trigger rather than a CHECK constraint?

#### Examiner's Focus:
Understanding the operational limitations of ANSI SQL `CHECK` constraints vs procedural triggers, and temporal sliding-window calculations.

#### Model Answer:
1. **ANSI SQL CHECK Constraint Limitations**:
   - A standard SQL `CHECK` constraint evaluates an expression strictly within the scope of the **current row** being inserted or updated.
   - It cannot execute subqueries against other tables, nor can it aggregate historical rows across temporal intervals. Because calculating rolling duty hours requires scanning previously flown sectors by that same crew member across multiple tables (`crew_duty_rosters`, `scheduled_flights`, and `flight_routes`), a declarative `CHECK` constraint cannot perform this validation.
2. **Mathematical Rolling Window Calculation**:
   - The trigger defines a sliding window beginning 24 hours prior to the planned departure:
     $$T_{\text{window\_start}} = T_{\text{departure}} - 24\text{ hours}$$
   - It performs an aggregate summation of scheduled block times for all active flights where the crew member was rostered within that interval:
     $$\text{Total Duty Mins} = \sum (\text{block\_time\_minutes}) \quad \forall \text{ flights where } T_{\text{dept}} \in [T_{\text{window\_start}}, T_{\text{departure}})$$
   - It projects the new flight's block time:
     $$\text{Projected FDP Hours} = \frac{\text{Accumulated Mins} + \text{New Block Mins}}{60.0}$$
   - Under FAA Part 117 and DGCA CAR Section 7, if $\text{Projected FDP Hours} > 14.0$, the trigger raises `SIGNAL SQLSTATE '45000'`, preemptively aborting the DML transaction before any database write occurs.

---

### Question 3: In `sp_swap_unfit_crew_with_standby`, why is Pessimistic Concurrency Control (`SELECT ... FOR UPDATE`) mandatory? What race condition would emerge under Optimistic Locking?

#### Examiner's Focus:
Transaction isolation levels, race conditions, phantom reads, and ACID compliance in high-concurrency crew dispatch environments.

#### Model Answer:
1. **The Concurrency Problem (The Double-Allocation Race Condition)**:
   - Imagine two different flight dispatchers simultaneously discover that pilots have taken sick leave on Flight A (DXB-LHR) and Flight B (DXB-JFK), both departing within 45 minutes from Dubai (DXB).
   - If both dispatchers query for an available standby Captain simultaneously without row-level locks, both transactions read the same standby Captain (e.g., Captain Robert Miller, `crew_id = 6`, status = `'Standby'`).
   - Both transactions determine Captain Miller is eligible, both assign Captain Miller to their respective flights, and both commit.
   - **Result**: A physical human pilot is rostered on two distinct flights departing at the same time—a catastrophic operational failure.
2. **Pessimistic Locking Solution**:
   - By executing:
     ```sql
     SELECT cm.crew_id INTO v_selected_standby_id
     FROM crew_members cm ...
     FOR UPDATE;
     ```
     MySQL's InnoDB storage engine sets an **exclusive record lock (`X lock`)** on that specific standby crew member's row.
   - The second transaction attempting to read or assign Captain Miller will block immediately at the lock acquisition stage until Transaction 1 completes (`COMMIT` or `ROLLBACK`).
   - By the time Transaction 2 acquires the lock, Transaction 1 has already updated Captain Miller's status to `'Active'`, causing Transaction 2's query to automatically bypass Captain Miller and assign the next qualified standby candidate.

---

### Question 4: How does the system enforce referential integrity between `scheduled_flights` and `flight_dispatch_releases` as a strict 1-to-1 relationship rather than 1-to-Many?

#### Examiner's Focus:
Candidate's understanding of modeling 1:1 relationships using unique constraints on foreign keys.

#### Model Answer:
In relational databases, a Foreign Key without additional constraints naturally models a **1-to-Many (1:N)** relationship (one scheduled flight could theoretically reference many dispatch releases).

To enforce an **exact 1-to-1 (1:1)** relationship:
1. In `flight_dispatch_releases`, `flight_instance_id` is defined as a Foreign Key referencing `scheduled_flights(flight_instance_id)`.
2. A `UNIQUE` constraint is explicitly placed on `flight_instance_id`:
   ```sql
   CONSTRAINT `uq_dispatch_flight_instance` UNIQUE (`flight_instance_id`)
   ```
3. **Operational Result**: An airframe and sector can only ever possess a single official legal Operational Flight Plan (OFP). Any attempt by a dispatcher to insert a second dispatch release record for the same flight instance will be rejected immediately with a duplicate key violation (`ER_DUP_ENTRY`).

---

### Question 5: Why are foreign keys on critical transactional tables configured with `ON DELETE RESTRICT` instead of `ON DELETE CASCADE`?

#### Examiner's Focus:
Aviation compliance regulations, data governance, accidental data destruction prevention, and referential actions.

#### Model Answer:
1. **Accidental Cascading Destruction**:
   - If `aircraft_models` or `aircraft_fleet` had `ON DELETE CASCADE`, accidentally deleting a model (e.g., Airbus A320neo) would cascade down and automatically delete all aircraft in the fleet, all historical scheduled flights, all crew rosters, and all safety audit logs associated with that model.
2. **Regulatory Non-Repudiation (FAA/ICAO Mandates)**:
   - Civil aviation regulations require airlines to maintain historical flight logs, crew duty records, and dispatch records for at least 5 to 7 years.
   - Using `ON DELETE RESTRICT` guarantees that no user or administrative script can delete an airport, aircraft, or crew member if they have ever participated in an active or historical flight.
3. **Audit Log Preservation**:
   - In `flight_operations_audit_logs`, the foreign keys use `ON DELETE SET NULL`. If an operational record is ever archived or purged, the audit log entry remains permanently intact with timestamps and textual event descriptions, preserving legal liability records.

---

### Question 6: Walk through the Execution Plan generated by `EXPLAIN ANALYZE` on Query 5. How does MySQL utilize the composite index `(flight_instance_id, crew_id, assignment_status)`?

#### Examiner's Focus:
Query optimization, B-Tree index traversal, covering indexes, and performance metrics.

#### Model Answer:
1. **Composite Index Structure**:
   - The index `idx_rosters_flight_role` and composite index on `(flight_instance_id, assignment_status)` organize data in a multi-level B-Tree sorted first by `flight_instance_id`, then by `assignment_status`.
2. **Access Method (`ref` vs `ALL`)**:
   - Without an index, the database engine must execute a **Full Table Scan (`type: ALL`)**, reading every page of `crew_duty_rosters` into the buffer pool and testing the predicate row by row. With millions of roster records, this causes severe I/O bottlenecks.
   - With the index present, the optimizer uses the access type **`ref`** or **`range`**. It seeks directly to the first index entry matching `flight_instance_id = 1` and `assignment_status = 'Assigned'`.
3. **Execution Plan Metrics**:
   - In MySQL 8.0 `EXPLAIN ANALYZE`, the output displays:
     - **Estimated cost vs Actual cost**: The CPU and memory units required.
     - **Actual time to first row and all rows**: Quantified in milliseconds (e.g., `0.024..0.041 ms`).
     - **Rows examined vs Rows returned**: In an optimized index seek, rows examined equals rows returned (e.g., `4 rows examined, 4 rows returned`), demonstrating $O(\log N)$ tree depth search rather than $O(N)$ linear scans.

---

### Question 7: How does `trg_prevent_aircraft_turnaround_conflict` ensure physical aircraft safety, and what happens if two flights are scheduled across midnight?

#### Examiner's Focus:
Temporal edge cases, turnaround ground time buffer calculations, and handling date-time boundaries across calendar days.

#### Model Answer:
1. **Turnaround Safety Guardrail**:
   - Modern commercial airliners require certified ground time (turnaround buffer) between successive flights for passenger deplaning, cabin cleaning, safety inspections, fueling, and passenger boarding.
   - For widebody aircraft like the Boeing 777-300ER, minimum turnaround is typically 60 to 75 minutes; for narrowbodies like the A320neo, it is 45 minutes.
2. **Handling Midnight Crossovers (`DATETIME` vs `TIME`)**:
   - If the system only used the `TIME` data type, a flight arriving at `23:45:00` and departing at `00:30:00` would cause arithmetic errors (as `00:30 < 23:45`).
   - By using full `DATETIME` (`YYYY-MM-DD HH:MM:SS`), the trigger calculates:
     ```sql
     TIMESTAMPDIFF(MINUTE, v_prev_arrival, NEW.departure_datetime)
     ```
   - `TIMESTAMPDIFF` automatically handles day, month, and leap-year boundaries correctly. If the calculated difference is less than `aircraft_models.min_turnaround_minutes`, the trigger raises `SIGNAL SQLSTATE '45000'`, preventing physical overlap in airframe scheduling.

---

### Question 8: Explain the difference between `vw_live_ops_dispatch_board` and `vw_crew_utilization_fatigue_index` in terms of evaluation and underlying join mechanisms.

#### Examiner's Focus:
Views, query re-writing, aggregation pipelines, and computational overhead.

#### Model Answer:
1. **`vw_live_ops_dispatch_board` (Row-Preserving Relational Projection)**:
   - This view performs deterministic joins across 1-to-1 and Many-to-1 relationships (`scheduled_flights` $\to$ `flight_routes` $\to$ `airports`, `aircraft_fleet`, `aircraft_models`).
   - It uses `LEFT JOIN` on `crew_duty_rosters` filtered specifically to `roster_role = 'Operating_Commander'` to extract the single Pilot-in-Command without multiplying row cardinality.
   - Because it contains no `GROUP BY` clause, the MySQL optimizer can merge view definitions directly into outer queries (View Algorithm: `MERGE`), allowing outer `WHERE` clauses to push down into index lookups.
2. **`vw_crew_utilization_fatigue_index` (Aggregated Group-By Pipeline)**:
   - This view performs multi-table aggregation across `crew_members`, `crew_duty_rosters`, and `scheduled_flights`.
   - It computes conditional sums over rolling date intervals (past 7 days and past 28 days) and groups by `crew_id`.
   - Because it performs grouping and aggregate calculations, MySQL treats it with the `TEMPTABLE` algorithm, instantiating an intermediate temporary table during execution to project pilot fatigue metrics.

---

### Question 9: What is the significance of the Anti-Join query (Query 2) using `NOT EXISTS` instead of `NOT IN`? What bug occurs with `NOT IN` when NULL values exist?

#### Examiner's Focus:
Three-valued logic (3VL: TRUE, FALSE, UNKNOWN), SQL anti-join semantics, and NULL hazards.

#### Model Answer:
1. **The NULL Hazard with `NOT IN`**:
   - In SQL standard three-valued logic, if the subquery in a `NOT IN` clause evaluates to a set containing even a single `NULL` value, the entire `NOT IN` predicate evaluates to `UNKNOWN` for all outer rows.
   - Example:
     ```sql
     WHERE crew_id NOT IN (SELECT crew_id FROM crew_duty_rosters)
     ```
     If any single row in `crew_duty_rosters` has `crew_id IS NULL`, the condition evaluates as:
     $$\text{crew\_id} \neq 1 \text{ AND } \text{crew\_id} \neq 2 \text{ AND } \text{crew\_id} \neq \text{NULL}$$
     Since any comparison with `NULL` yields `UNKNOWN`, the entire boolean conjunction collapses to `UNKNOWN` or `FALSE`. The query returns **zero rows**, concealing critical operational data!
2. **The Robustness of `NOT EXISTS`**:
   - `NOT EXISTS` relies on **existential quantification**. It tests whether the correlated subquery returns an empty or non-empty set of rows.
   - It checks whether matching records exist and is completely immune to the presence of `NULL` values in subquery attributes.
   - Furthermore, the MySQL query optimizer translates correlated `NOT EXISTS` into a high-performance **Anti-Semi-Join**, halting the subquery scan as soon as the first matching record is discovered.

---

### Question 10: How does the database design ensure ACID compliance during a mid-flight delay propagation or an emergency standby crew swap?

#### Examiner's Focus:
Deep evaluation of ACID properties (Atomicity, Consistency, Isolation, Durability) applied to aviation flight operations.

#### Model Answer:
The system enforces ACID guarantees through engine architecture and procedural design:

1. **Atomicity**:
   - In `sp_swap_unfit_crew_with_standby`, operations must occur as a single indivisible unit:
     1. Unfit crew roster status set to `'Standby_Swapped'`
     2. Unfit crew member status marked `'Suspended'`
     3. Standby crew assigned to roster
     4. Standby crew status changed from `'Standby'` to `'Active'`
     5. Audit log record appended
   - The procedure wraps these five updates within `START TRANSACTION`. An `EXIT HANDLER FOR SQLEXCEPTION` executes an immediate `ROLLBACK` if any step fails, preventing partial updates.
2. **Consistency**:
   - Database state moves strictly from one valid legal state to another.
   - Active database triggers validate that the new crew member has unexpired aircraft type ratings (`trg_verify_pilot_type_rating`) and has met mandatory rest requirements (`trg_enforce_fdp_and_mandatory_rest`). If constraints fail, consistency is preserved by rolling back.
3. **Isolation**:
   - InnoDB utilizes **Multi-Version Concurrency Control (MVCC)** alongside pessimistic row locking (`SELECT ... FOR UPDATE`).
   - Concurrent queries read non-blocking snapshot reads, while concurrent standby allocation attempts are serialized at the row level, preventing double allocation.
4. **Durability**:
   - Once `COMMIT` executes, all transactional changes are permanently written to InnoDB's Write-Ahead Log (**redo log / WAL**) and flushed to disk according to `innodb_flush_log_at_trx_commit = 1`. Even in the event of an abrupt server power outage, all flight dispatch records are fully recoverable upon restart.
