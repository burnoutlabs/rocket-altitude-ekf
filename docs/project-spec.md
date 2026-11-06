# PROJECT-SPEC (Locked Baseline)

> Status: Locked project specification baseline for implementation.
> Change only if scope is explicitly re-approved.
>
> **As-built note (2026-04-26):** The barometer bias augmentation ($b_b$ stretch state)
> was not implemented — intentional scope reduction after proposal approval.
> The `altitude_linear` measurement model (linear KF update, H = [1 0 0]) is implemented
> and selectable at runtime; a dedicated EKF-vs-linear-KF comparison section was not
> produced in the report. All other spec items are implemented as described.

# Project Proposal

**Course:** ECE 9203 / ECE 9023 — Random Signals, Winter 2026
**Title:** Offline Rocket Flight State Estimation from IMU and Barometric Data Using an Extended Kalman Filter
**Topic Area:** Kalman filter applications / nonlinear state estimation

---

## Objective

Design, implement, and evaluate an offline Extended Kalman Filter (EKF) that reconstructs the vertical flight state of a high-power rocket from logged onboard IMU and barometric sensor data. The project is framed as a stochastic estimation and reconstruction problem, not an embedded-avionics implementation.

---

## Scope and Justification

A narrowly scoped, well-justified EKF targeting the vertical channel is stronger than a shallow multi-filter comparison. The EKF is the standard production nonlinear estimator in flight-estimation stacks (e.g., PX4 EKF2) and directly applies course material on Kalman filtering, stochastic modeling, and sensor-noise treatment.

This project will be implemented fully in MATLAB to align with the instructor's MATLAB-only expectation for project implementation.

---

## State Vector and System Model

**Primary state vector:**

$$\mathbf{x} = \begin{bmatrix} z & v_z & b_a \end{bmatrix}^T$$

| Symbol | Description        |
| ------ | ------------------ |
| $z$    | Vertical altitude  |
| $v_z$  | Vertical velocity  |
| $b_a$  | Accelerometer bias |

**Stretch state:** augment with barometer bias $b_b$. *(Not implemented — see as-built note.)*

**Measurement input:** barometric altitude (converted from raw pressure).
**Inertial input:** accelerometer along the vertical axis (gravity-compensated, bias-corrected).

The system is nonlinear when orientation handling and gravity compensation are included inside the estimator model, motivating EKF over a plain linear KF. A linear KF baseline will be included for comparison if orientation is fully pre-processed externally. *(Not implemented — see as-built note.)*

---

## Technical Approach

### Architecture

| Layer                   | Environment | Responsibility                                                                                                                       |
| ----------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Data ingestion & replay | MATLAB      | Parse/normalize datasets, align timestamps, and feed time-ordered measurements to the estimator                                      |
| Estimation core         | MATLAB      | Pressure→altitude conversion, vertical acceleration extraction, EKF predict/update, bias estimation, covariance propagation, logging |
| Analysis & evaluation   | MATLAB      | Plotting, diagnostics, Q/R sensitivity analysis, and cross-dataset comparison                                                        |

### EKF Steps (MATLAB implementation)

1. **Predict** — propagate state and covariance using IMU measurements and process noise `Q`
2. **Update** — fuse barometric altitude measurement with noise `R`
3. **Output** — estimated `z`, `v_z`, `b_a`; innovation residuals; covariance traces

### Implementation and reproducibility requirements

- All core estimation logic is implemented in MATLAB (`.m` files).
- Dataset ingestion, replay, plotting, and diagnostics are scripted in MATLAB.
- Data preprocessing includes schema normalization, unit handling, and time-base synchronization.
- The workflow includes a one-script reproducible run path per dataset.

---

## Datasets

All data sourced from the DOFPro flight-data archive: <https://dofpro.org/RCK/fltdata/FlightData.html>

| Role                | Rocket                                 | Logger Types                    | Purpose                               |
| ------------------- | -------------------------------------- | ------------------------------- | ------------------------------------- |
| Primary development | 38 mm Prototype (J510W / J570W / J150) | Raven, XTRA, onboard, emulation | Core implementation and main results  |
| Validation          | Madcow Adventurer                      | Raven + GPS                     | Cross-rocket generalization           |
| Robustness          | LOC Precision Vulcanite                | Trimmed logs + GPS              | Estimator stability on imperfect data |

---

## Evaluation Plan

| Level   | Approach                                                                                                          |
| ------- | ----------------------------------------------------------------------------------------------------------------- |
| Minimum | Filtered altitude vs. raw baro; filtered velocity vs. numerical derivative; innovation residuals; Q/R sensitivity |
| Better  | Multi-flight comparison across motors/profiles; robustness on noisy/missing segments                              |
| Stretch | EKF vs. linear KF baseline                                                                                        |

Key diagnostics: innovation sequence consistency, covariance bounds, bias convergence, behavior across boost / coast / descent phases.

### Reference signals and concrete outputs

No onboard system is treated as ground truth. Comparisons use only imperfect references:

- raw barometric altitude
- vendor-reported altitude/velocity (baseline estimator)
- GPS altitude (when available)

Primary MATLAB outputs for report figures and consistency checks:

- `z_hat` vs raw barometric altitude
- `v_z_hat` vs finite-difference velocity proxy
- innovation sequence and normalized innovation squared (NIS)
- bias estimate convergence (`b_a`, optional `b_b`)
- covariance trend plots across boost / coast / descent

---

## Deliverables

- MATLAB EKF implementation (`.m` functions/scripts) for state propagation and measurement updates
- MATLAB scripts for dataset parsing, replay, plotting, and diagnostics
- Final report covering: stochastic model derivation, observability analysis, noise covariance justification, results figures, literature review
- Key figures: raw baro vs. filtered altitude, estimated velocity, accelerometer bias, innovation/residual behavior, covariance trends

---

## Constraints

- Offline-only, dataset-driven workflow — no live hardware or real-time implementation
- Vertical channel only — no full 6-DOF navigation
- Heterogeneous public datasets — varying logger formats, sensor completeness, and data quality expected
- MATLAB-only implementation path for all project code and analysis outputs

---

## Key References

| Reference                                                                                                             | Notes                                      |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| Kalman (1960) — [doi:10.1115/1.3662552](https://doi.org/10.1115/1.3662552)                                            | Foundational                               |
| Brown & Hwang — _Introduction to Random Signals and Applied Kalman Filtering_                                         | Primary course-aligned text                |
| Särkkä — _Bayesian Filtering and Smoothing_ ([PDF](https://users.aalto.fi/~ssarkka/pub/cup_book_online_20131111.pdf)) | Theoretical foundation                     |
| Groves — _Principles of GNSS, Inertial, and Multisensor Integrated Navigation Systems_                                | Inertial navigation and bias modeling      |
| PX4 EKF2 documentation — [px4.io](https://docs.px4.io/main/en/advanced_config/tuning_the_ecl_ekf.html)                | Production EKF reference                   |
| NASA NTRS 20240001235 — trajectory reconstruction                                                                     | Offline sigma-point filtering in aerospace |
| Noise covariance identification — [PMC8638515](https://pmc.ncbi.nlm.nih.gov/articles/PMC8638515/)                     | Adaptive Q/R selection                     |

### Practical implementation links

Core Kalman / rocket references:

- https://kalmanfilter.net/multiExamples.html#ex10
- https://davesrocketworks.com/rockets/rnd/2004/KalmanApogeeII.pdf
- https://repository.rice.edu/server/api/core/bitstreams/0fbefe49-d831-4891-b83f-d8c2f05ce2f9/content
- https://ntrs.nasa.gov/api/citations/20240001235/downloads/NASA-TM-20240001235.pdf

MATLAB documentation used in implementation:

- https://www.mathworks.com/help/matlab/ref/readtable.html
- https://www.mathworks.com/help/matlab/ref/timetable.html
- https://www.mathworks.com/help/control/ref/kalman.html
- https://www.mathworks.com/help/matlab/creating_plots/create-line-plot.html
