# Vertical Flight EKF Reference

Status: active  
Last updated: 2026-04-26  
Scope: `project/matlab` implementation

---

## 1. Purpose

Single-source reference for:

1. EKF theory, modeling assumptions, and implementation details
2. run controls in `data.m` and `main.m`
3. artifact-generation behaviour and outputs
4. practical workflow for selecting report figure flight IDs

---

## 2. Project Framing

We estimate rocket vertical motion from asynchronous onboard sensors.

Available streams after preprocessing:

1. IMU vertical acceleration (`accel_z_mps2`)
2. barometer pressure (`pressure_pa`)

The estimator reconstructs latent vertical state:

1. altitude $z$
2. vertical velocity $v_z$
3. accelerometer bias $b_a$

---

## 3. End-to-End Pipeline Flow

From [data.m](../matlab/data.m) and [main.m](../matlab/main.m):

1. `data.m`: fetch source data (`_data_raw/`)
2. `data.m`: normalize + validate (`_data_normalized/`)
3. `data.m`: clean + validate (`_data_clean/`)
4. `main.m`: run replay build + single-flight EKF diagnostics
5. `main.m`: optionally regenerate report artifacts (all-flight tables + selected figures)

Core modules:

1. EKF core: `ekf/`
2. replay/data pipeline helpers: `ekf/pipeline/`
3. plotting functions: `plotting/`

---

## 4. Stochastic State-Space Model

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

1. $u_z$ is acceleration input used by the model (specific force minus gravity)
2. $w_v$ is process disturbance on velocity dynamics
3. $w_b$ is bias random walk

Process dynamics are linear in state. The nonlinearity enters only in the measurement model when `pressure_nonlinear` is selected — that is the defining EKF step: $h(x)$ is evaluated in the pressure domain and linearized via $H_k = \partial h / \partial x$ at each update.

---

## 5. Discrete-Time Predict Step

Implemented in [ekf_predict.m](../matlab/ekf/ekf_predict.m).

Given event step $\Delta t$:

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

### 5.1 Process Noise Discretization

$Q_d$ is composed from two PSD terms:

1. `q_vz_psd` — velocity disturbance PSD
2. `q_ba_psd` — bias random walk PSD

with explicit $\Delta t$-polynomial terms (up to $\Delta t^5$) in [ekf_predict.m](../matlab/ekf/ekf_predict.m) (`discretize_process_noise`).

With $Q_c = \mathrm{diag}(0, q_{v_z}, q_{b_a})$ and $\Phi(\tau) = F(\tau)$ above, exact integration gives

$$
Q_d(\Delta t) = \int_0^{\Delta t} \Phi(\tau)\, Q_c\, \Phi(\tau)^\top \, d\tau
= q_{v_z}
\begin{bmatrix}
\frac{\Delta t^3}{3} & \frac{\Delta t^2}{2} & 0\\
\frac{\Delta t^2}{2} & \Delta t & 0\\
0 & 0 & 0
\end{bmatrix}
+ q_{b_a}
\begin{bmatrix}
\frac{\Delta t^5}{20} & \frac{\Delta t^4}{8} & -\frac{\Delta t^3}{6}\\
\frac{\Delta t^4}{8} & \frac{\Delta t^3}{3} & -\frac{\Delta t^2}{2}\\
-\frac{\Delta t^3}{6} & -\frac{\Delta t^2}{2} & \Delta t
\end{bmatrix}
$$

The bias term is not diagonal: bias noise reaches $z$ and $v_z$ through $\Phi(\tau)\,[0, 0, 1]^\top = [-\tau^2/2, -\tau, 1]^\top$, so it adds the $\Delta t^5/20$, $\Delta t^3/3$ diagonal terms and the negative cross-terms.

This is important because replay intervals are variable (asynchronous sensors), so fixed-$Q$ assumptions are avoided.

---

## 6. Measurement Models

Runtime-selectable via `ekf_config.measurement_model` in [main.m](../matlab/main.m).

### 6.1 Linear Altitude Model (`altitude_linear`)

Implemented in [ekf_update_baro.m](../matlab/ekf/ekf_update_baro.m):

$$
y_z = z + v,\quad H = \begin{bmatrix} 1 & 0 & 0 \end{bmatrix}
$$

Standard linear KF measurement update. Provided as a baseline.

### 6.2 Nonlinear Pressure Model (`pressure_nonlinear`) — Default

Implemented in [ekf_update_baro_pressure.m](../matlab/ekf/ekf_update_baro_pressure.m).

Measurement:

$$
y_p = p_{meas}
$$
$$
h(z) = p_0 \left(1 - \frac{z_{abs}}{H}\right)^\beta,\quad z_{abs} = z + z_{ref}
$$

ISA troposphere constants used in code:

1. $H = T_0/L \approx 44330.77\ \text{m}$
2. $\beta = g_0/(RL) \approx 5.25588$

EKF linearization:

$$
H_k = \begin{bmatrix} \frac{\partial h}{\partial z} & 0 & 0 \end{bmatrix}
$$

The code maps altitude-domain variance (`r_baro_var`, m²) to pressure-domain effective variance:

$$
R_{eff} = \left(\frac{\partial h}{\partial z}\right)^2 r_{baro}
$$

This keeps the tunable noise parameter interpretable in altitude units (metres) while the filter updates in the pressure domain (Pa).

---

## 7. Update Equations and Numerical Form

For either measurement model:

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

Covariance update uses Joseph form for numerical stability:

$$
P_k^+ = (I-K_kH_k)P_k^-(I-K_kH_k)^\top + K_kR_kK_k^\top
$$

Numerical safeguards:

1. optional symmetry enforcement $P \leftarrow (P + P^\top)/2$
2. per-state variance floor (`min_variance_floor`)
3. non-finite or invalid measurements rejected — no state update performed

---

## 8. Innovation Gating

Implemented in both update functions. Normalized innovation squared (NIS):

$$
\text{NIS} = \frac{\nu_k^2}{S_k}
$$

Measurement accepted if gate is disabled, or $\text{NIS} \le n_\sigma^2$.

Current default in [main.m](../matlab/main.m): gate is **off** (`enable_innovation_gate = false`).

Rationale: a strict global gate causes baro starvation during high-dynamic events (boost phase, logger shutdown spikes) across the heterogeneous 25-flight dataset. With gating off, all baro measurements are accepted. The ±4400 Pa J510W shutdown spike is absorbed without divergence, confirming this is the correct trade-off for a heterogeneous fleet.

---

## 9. Asynchronous Replay and Input Holding

Replay construction is in [build_replay_events.m](../matlab/ekf/pipeline/build_replay_events.m):

1. IMU + baro rows merged by time into one event stream
2. deterministic tie-break: IMU first when timestamps are equal
3. event-wise `dt_sec = diff(t)`, guarded nonnegative

Estimator loop in [run_vertical_ekf_replay.m](../matlab/ekf/run_vertical_ekf_replay.m):

1. predict step runs at every event using held $u_z$
2. IMU events update held input for subsequent steps
3. baro events perform measurement update

This supports naturally asynchronous sensor rates (20–1141 Hz range across families) without forced resampling.

---

## 10. Measurement Preparation and Conventions

Pre-update preparation is in [prepare_measurements_for_ekf.m](../matlab/ekf/pipeline/prepare_measurements_for_ekf.m).

### 10.1 Acceleration Convention

Default assumption: IMU signal is specific force (+z upward).

$$
u_z = a_{imu} - g
$$

Controlled by `accel_is_specific_force` and `gravity_mps2`.

### 10.2 Launch-Relative Baro Convention

Absolute barometric altitude is computed from pressure, then shifted:

$$
z_{baro} = z_{abs,baro} - z_{ref}
$$

where $z_{ref}$ is estimated from the earliest baro samples (median by default).

For the nonlinear pressure update, $z_{ref}$ is carried so the measurement model evaluates pressure at $z_{abs} = z + z_{ref}$.

---

## 11. Initialization

Configured in [main.m](../matlab/main.m).

Default initialization:

1. $x_0 = [z_0,\ v_{z0},\ b_{a0}]^\top$ from explicit parameters
2. if launch-relative baro is on, $z_0$ is aligned to first finite baro-relative sample
3. $P_0 = \text{diag}(\sigma_z^2,\ \sigma_{v_z}^2,\ \sigma_{b_a}^2)$

Current validated parameters:

| Parameter | Value | Physical meaning |
|-----------|-------|-----------------|
| `q_vz_psd` | 4.0 m²/s | velocity process disturbance PSD |
| `q_ba_psd` | 0.0025 m²/s³ | bias random walk PSD (= 0.05² m/s² per Hz) |
| `r_baro_var` | 64 m² | baro altitude noise variance (= 8² m → σ ≈ 0.68 m) |
| `init_var_z` | 2500 m² | initial altitude uncertainty (σ = 50 m) |
| `init_var_vz` | 900 m²/s² | initial velocity uncertainty (σ = 30 m/s) |
| `init_var_ba` | 25 m²/s⁴ | initial bias uncertainty (σ = 5 m/s²) |
| `max_dt_sec` | 5.0 s | maximum single replay step |
| `measurement_model` | `pressure_nonlinear` | nonlinear ISA pressure update |
| `enable_innovation_gate` | `false` | gating disabled |

Parameters were selected by physical reasoning, not grid search.

---

## 12. Run Controls and Workflow

In [main.m](../matlab/main.m):

1. `active_flight_id = "auto"` — set an explicit flight ID to inspect a specific flight
2. `run_generate_report_artifacts = true/false` — runs all-flight artifact table regeneration
3. `report_figure_flight_ids = [...]` — explicit list for saved report figures only
4. `report_figures_all_flights = false` — keep false; set true only for full-fleet figure generation

Practical workflow:

1. iterate `active_flight_id` to inspect flights manually and read console diagnostics
2. pick final report figure flight IDs (see `dataset-and-results.md` §6 for recommendations)
3. set `report_figure_flight_ids` to those IDs
4. enable `run_generate_report_artifacts = true` for a full table + figure run

---

## 13. Canonical Report Artifacts

All outputs land in `_report_artifacts/`.

Tables (`_report_artifacts/tables/`):

1. `replay_validation_summary.csv` — per-flight replay event accounting
2. `ekf_runtime_health.csv` — per-flight runtime health flags
3. `innovation_gate_counts.csv` — per-flight gating statistics
4. `diagnostics_summary.csv` — per-flight NIS, bias, covariance diagnostics
5. `final_per_flight_metrics.csv` — final state and key metrics per flight
6. `final_aggregate_metrics.csv` — fleet-wide summary statistics
7. `report_figure_manifest.csv` — manifest of generated figure files

Figures (`_report_artifacts/figures/`, generated for `report_figure_flight_ids` only):

1. `replay_timing_<flight_id>.png`
2. `measurement_conventions_<flight_id>.png`
3. `ekf_overview_<flight_id>.png`
4. `ekf_innovations_<flight_id>.png`
5. `ekf_covariance_<flight_id>.png`
6. `ekf_event_timeline_<flight_id>.png`

Entrypoint: [generate_report_artifacts.m](../matlab/ekf/pipeline/generate_report_artifacts.m).  
Options: `figure_flight_ids` and `verbose` name-value pairs.  
Invalid figure IDs fail fast with a clear error from `apply_name_value.m`.

---

## 14. Validation Approach

Replay validation: [validate_replay_events.m](../matlab/ekf/pipeline/validate_replay_events.m) checks time monotonicity, finite signals, and event accounting.

All-flight EKF audit: there is no audit script in this repository (an earlier version of this page linked `matlab/debug/run_full_ekf_audit.m`, which does not exist). The recorded all-flight audit is [AUDIT-2026-04-25.md](../archive/AUDIT-2026-04-25.md).

Current validated configuration (from full 25-flight audit):

1. `measurement_model = pressure_nonlinear`
2. `enable_innovation_gate = false` — maximises baro update ratio across all flight families
3. all 25 flights pass with finite final state, baro_update_ratio = 1.000, P_baba converged

---

## 15. Assumptions and Known Limits

1. **Vertical channel only** — no full attitude, drag, or 6-DOF state
2. **No RTS smoothing** — forward-pass estimator only; no smoothed trajectory in mainline path
3. **No attitude data** — EKF assumes axial IMU = world-frame vertical throughout; post-apogee Raven divergence is a direct consequence of this (see `dataset-and-results.md` §4.2)
4. **Single barometric reference** — altitude is relative to launch-time ambient pressure; synoptic pressure changes accumulate as apparent altitude error (see `dataset-and-results.md` §4.3)
5. **Fixed global Q/R** — same parameters for all four sensor families (50–1141 Hz IMU, 20–55 Hz baro); per-family tuning would improve NIS consistency but is out of scope
6. **Gating disabled globally** — avoids baro starvation on diverse flight profiles; accepted trade-off
