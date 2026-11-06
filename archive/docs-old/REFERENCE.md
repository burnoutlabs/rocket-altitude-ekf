# Vertical Flight EKF Reference

Status: active  
Last updated: 2026-04-23  
Scope: `project/matlab` implementation

## 1) Purpose

This document is the technical reference for the estimator itself: the theory, modeling assumptions, and exactly how the EKF is implemented in this project.

It is written to support walkthroughs of [main.m](../../matlab/main.m), code review, and final reporting.

## 2) Project Framing

We estimate rocket vertical motion from asynchronous onboard sensors.

Available streams after preprocessing:

1. IMU vertical acceleration (`accel_z_mps2`)
2. barometer pressure (`pressure_pa`)

The estimator reconstructs latent vertical state:

1. altitude \(z\)
2. vertical velocity \(v_z\)
3. accelerometer bias \(b_a\)

## 3) Brief Note on Data Pipeline

Raw heterogeneous source files are normalized into a common schema, then cleaned into EKF-ready per-flight files in `_data_clean/flights/<flight_id>/`.  
Those stages enforce column consistency and basic quality checks, but the estimator details are the focus of this document.

## 4) Stochastic State-Space Model

We model the system as:

$$
x_{k+1} = f(x_k, u_k, \Delta t_k) + w_k,\quad w_k \sim \mathcal{N}(0, Q_k)
$$
$$
y_k = h(x_k) + v_k,\quad v_k \sim \mathcal{N}(0, R_k)
$$

with state:

$$
x = \begin{bmatrix} z & v_z & b_a \end{bmatrix}^\top
$$

### 4.1 Continuous-Time Dynamics Assumed

$$
\dot{z} = v_z
$$
$$
\dot{v}_z = u_z - b_a + w_v
$$
$$
\dot{b}_a = w_b
$$

where:

1. \(u_z\) is acceleration input used by the model
2. \(w_v\) is process disturbance on velocity dynamics
3. \(w_b\) is bias random walk

## 5) Discrete-Time Predict Step (Implemented)

Implemented in [ekf_predict.m](../../matlab/ekf/ekf_predict.m).

Given event step \(\Delta t\):

$$
z_{k+1} = z_k + v_{z,k}\Delta t + \frac{1}{2}(u_k - b_{a,k})\Delta t^2
$$
$$
v_{z,k+1} = v_{z,k} + (u_k - b_{a,k})\Delta t
$$
$$
b_{a,k+1} = b_{a,k}
$$

State Jacobian used in covariance prediction:

$$
F_k =
\begin{bmatrix}
1 & \Delta t & -\frac{1}{2}\Delta t^2\\
0 & 1 & -\Delta t\\
0 & 0 & 1
\end{bmatrix}
$$

Covariance prediction:

$$
P_k^- = F_k P_{k-1}^+ F_k^\top + Q_d(\Delta t)
$$

### 5.1 Process Noise Discretization Used

The code composes \(Q_d\) from two PSD terms:

1. `q_vz_psd` for velocity disturbance
2. `q_ba_psd` for bias random walk contribution

with explicit \(\Delta t\)-polynomial terms (up to \(\Delta t^5\)) in [ekf_predict.m](../../matlab/ekf/ekf_predict.m).

This is important because replay intervals are variable, so fixed-\(Q\) assumptions are avoided.

## 6) Measurement Models

Runtime-selectable via `ekf_config.measurement_model` in [main.m](../../matlab/main.m).

### 6.1 Linear Altitude Model (`altitude_linear`)

Implemented in [ekf_update_baro.m](../../matlab/ekf/ekf_update_baro.m):

$$
y_z = z + v,\quad H = \begin{bmatrix} 1 & 0 & 0 \end{bmatrix}
$$

This is standard linear KF measurement update.

### 6.2 Nonlinear Pressure Model (`pressure_nonlinear`) — True EKF Path

Implemented in [ekf_update_baro_pressure.m](../../matlab/ekf/ekf_update_baro_pressure.m).

Measurement:

$$
y_p = p_{meas}
$$
$$
h(z) = p_0 \left(1 - \frac{z_{abs}}{H}\right)^\beta,\quad
z_{abs}=z+z_{ref}
$$

with ISA troposphere constants in code:

1. \(H = T_0/L \approx 44330.77\ \text{m}\)
2. \(\beta = g_0/(RL) \approx 5.25588\)

EKF linearization term:

$$
H_k = \begin{bmatrix} \frac{\partial h}{\partial z} & 0 & 0 \end{bmatrix}
$$

Code maps altitude-domain variance (`r_baro_var`, m\(^2\)) to pressure-domain effective variance:

$$
R_{eff} = \left(\frac{\partial h}{\partial z}\right)^2 r_{baro}
$$

This keeps tunable noise interpretable in altitude units while updating in pressure domain.

## 7) Update Equations and Numerical Form

For either measurement model, the code uses:

$$
\nu_k = y_k - h(x_k^-)
$$
$$
S_k = H_k P_k^- H_k^\top + R_k
$$
$$
K_k = P_k^- H_k^\top S_k^{-1}
$$
$$
x_k^+ = x_k^- + K_k \nu_k
$$

Covariance update uses Joseph form:

$$
P_k^+ = (I-K_kH_k)P_k^-(I-K_kH_k)^\top + K_kR_kK_k^\top
$$

Numerical safeguards used across predict/update:

1. optional symmetry enforcement \(P \leftarrow (P + P^\top)/2\)
2. per-state variance floor (`min_variance_floor`)
3. non-finite/invalid measurement rejection with no state update

## 8) Innovation Gating

Implemented in both update functions with normalized innovation squared (NIS):

$$
\text{NIS} = \frac{\nu_k^2}{S_k}
$$

Measurement accepted if:

1. gate disabled, or
2. \(\text{NIS} \le n_\sigma^2\)

Current default in [main.m](../../matlab/main.m): gate is **off** for robust all-flight behavior.

## 9) Asynchronous Replay and Input Holding

Replay construction is in [build_replay_events.m](../../matlab/ekf/pipeline/build_replay_events.m):

1. IMU + baro rows merged by time into one event stream
2. deterministic tie-break: IMU first when timestamps equal
3. event-wise `dt_sec = diff(t)` and guarded nonnegative

Estimator loop in [run_vertical_ekf_replay.m](../../matlab/ekf/run_vertical_ekf_replay.m):

1. predict step runs at every event using held \(u_z\)
2. IMU events update held input for subsequent steps
3. baro events perform measurement update

This supports naturally asynchronous sensor rates without forced resampling.

## 10) Measurement Preparation and Conventions

Pre-update preparation is in [prepare_measurements_for_ekf.m](../../matlab/ekf/pipeline/prepare_measurements_for_ekf.m).

### 10.1 Acceleration Convention

Default assumption: IMU signal is specific force.

$$
u_z = a_{imu} - g
$$

controlled by `accel_is_specific_force` and `gravity_mps2`.

### 10.2 Launch-Relative Baro Convention

Absolute barometric altitude is computed from pressure, then optionally shifted:

$$
z_{baro} = z_{abs,baro} - z_{ref}
$$

where \(z_{ref}\) is estimated from earliest baro samples (median by default).

For nonlinear pressure update, \(z_{ref}\) is carried so the measurement model evaluates pressure at \(z_{abs}=z+z_{ref}\).

## 11) Initialization and Runtime Configuration

Configured in [main.m](../../matlab/main.m).

Default initialization:

1. \(x_0=[z_0,\ v_{z0},\ b_{a0}]^\top\) from explicit parameters
2. if launch-relative baro is on, \(z_0\) is aligned to first finite baro-relative sample
3. \(P_0=\text{diag}(\sigma_z^2,\sigma_{v_z}^2,\sigma_{b_a}^2)\)

Important defaults:

1. `measurement_model = "pressure_nonlinear"`
2. `enable_innovation_gate = false`

## 12) Validation and Audit Approach

Replay validation: [validate_replay_events.m](../../matlab/ekf/pipeline/validate_replay_events.m) checks time monotonicity, finite signals, and event accounting.

All-flight EKF audit: [run_full_ekf_audit.m](../../matlab/debug/run_full_ekf_audit.m) compares mode/gate combinations and writes debug artifacts.

Current audit recommendation (from `debug_artifacts`):

1. `measurement_model = pressure_nonlinear`
2. gate off for global robustness
3. main pressure nonlinear gate-off combo passes all 18 cleaned flights under audit criteria

## 14) Report Artifact Generation

Implemented in [generate_report_artifacts.m](../../matlab/ekf/pipeline/generate_report_artifacts.m).

Behavior:

1. tables regenerate across all cleaned flights
2. figures regenerate only for explicit `report_figure_flight_ids`
3. output tables include runtime health, gating stats, diagnostics, and aggregate metrics

## 15) What Makes This an EKF Here

In this phase, process dynamics are linear in state, but measurement can be nonlinear.

When `measurement_model = pressure_nonlinear`, the filter uses:

1. nonlinear \(h(x)\) in pressure domain
2. Jacobian \(H_k=\partial h/\partial x\) evaluated at current prediction

That is the defining EKF step.

## 16) Assumptions and Known Limits

1. vertical-channel-only model (no full attitude/drag state)
2. no RTS smoothing in mainline path
3. data quality still affects outcomes despite validation
4. global gate thresholds can starve updates on some flight families

These are intentional scope choices to keep the estimator interpretable and robust for the course project deliverable.

## 17) Reproducibility

Primary entrypoint:

1. run [main.m](../../matlab/main.m)

Deep diagnostic entrypoint:

1. run [run_full_ekf_audit.m](../../matlab/debug/run_full_ekf_audit.m)

Core implementation files:

1. [ekf_predict.m](../../matlab/ekf/ekf_predict.m)
2. [ekf_update_baro.m](../../matlab/ekf/ekf_update_baro.m)
3. [ekf_update_baro_pressure.m](../../matlab/ekf/ekf_update_baro_pressure.m)
4. [run_vertical_ekf_replay.m](../../matlab/ekf/run_vertical_ekf_replay.m)
5. [prepare_measurements_for_ekf.m](../../matlab/ekf/pipeline/prepare_measurements_for_ekf.m)
6. [build_replay_events.m](../../matlab/ekf/pipeline/build_replay_events.m)

