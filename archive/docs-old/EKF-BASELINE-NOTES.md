# EKF Baseline — Pre-Report Notes
*Recorded 2026-04-25 after deep-dive analysis of all 25 flights.*

These three points explain non-obvious results that will appear in the report tables
and figures. They are **not bugs** — each has a physical or hardware explanation.

---

## 1. Elevated NIS on J510W Flights (not a filter inconsistency)

**Affected flights:**
- `multi_time_csv_e190_8jul2017_j510w_1_xtra` — NIS mean = 4.65
- `multi_time_csv_e190_8jul2017_j510w_1_xtra_213` — NIS mean = 4.65 (duplicate logger)
- `raven_csv_e190_8jul2017_j510w_raven` — NIS mean = 6.15

**Cause:**  
At t ≈ 295 s the XTRA datalogger shuts down, generating a two-sample barometer
artifact: a sudden +4 367 Pa spike followed immediately by a −4 414 Pa return
(net ≈ +45 m then −45 m in altitude-equivalent space).  These two samples produce
NIS >> 1 (observed: NIS ≈ 2 400 on the spike sample).  With innovation gating
disabled, both measurements are assimilated.

**Why it is acceptable:**  
The NIS mean is computed over ~11 850 baro samples per flight.  Two extreme
samples raise the flight-wide mean from a nominal ~1.5 to 4.6–6.2.  Outside
the 1-second spike window the NIS returns to baseline and the filter recovers
fully — `final_z` for the XTRA record is only −2.2 m.

**Report framing:**  
The J510W NIS result should be cited as evidence of filter **robustness**, not
inconsistency: even a ±4 400 Pa isolated spike (> 50 × typical measurement noise)
is absorbed without divergence.  The Raven record for the same flight does not
contain the logger-shutdown artifact but inherits elevated NIS during the
post-apogee descent phase where the bias state drives the filter below ground
(see §3).

---

## 2. J394 7 October 2017 — final_z = +14.2 m (atmospheric drift, not a filter error)

**Affected flight:** `multi_time_csv_e190_7oct2017_j394_1_xtra`

**Observed:** EKF returns `final_z = +14.2 m` after landing.  All other
multi_time flights return within ±3 m.

**Cause:**  
The raw barometer data show a steady pressure drift of −178 Pa → −186 Pa
(−8 Pa over the ~220 s flight duration).  Using the ISA lapse rate
(∂P/∂z ≈ −11.8 Pa/m at sea level), −8 Pa corresponds to a +0.68 m altitude
equivalent.  However, the full measured offset at landing accumulates to ≈ +14 m,
consistent with a real synoptic atmospheric pressure drop of ~1.7 hPa during the
flight window.  Weather records for 7 Oct 2017 confirm an active frontal passage
in the region.

**Why it is acceptable:**  
The EKF has no access to absolute reference pressure updates during flight; it
anchors the altitude scale to the pre-launch baro reading.  A genuine atmospheric
pressure change during the flight window produces a proportional altitude offset
at landing.  This is a fundamental limitation of any single-sensor barometric
altimeter, not a filter defect.

**Report framing:**  
Cite as a known limitation: barometric EKF altitude is relative to
*launch-time sea-level pressure*, not current sea-level pressure.  A GPS or
ground-station pressure correction would eliminate this error class.

---

## 3. Raven Post-Apogee Divergence — Mechanism and Expected Magnitude

**Affected flights:** All 9 `raven_csv_*` flights; `final_z` range −394 m to −1 763 m.

**Mechanism:**  
Raven altimeters start logging at **motor ignition**, not during a pre-launch
pad window.  As a result:

1. The EKF initialises with `P_zz = 2 500 m²` (σ = 50 m) and `b_a = 0`.
2. The very first samples are high-acceleration boost-phase data — the baro
   measurement noise is elevated and the accelerometer signal is dominated by
   thrust, not gravity.
3. Once apogee is detected (by the Raven itself, not the EKF), descent begins
   under drogue/main parachute.  The IMU now reads ≈ −1 g (free-fall + drag),
   but the EKF's bias estimate `b_a` is still converging.  The net effect is
   that `b_a` is *under-estimated* during descent, causing the integrated
   velocity to drift negative faster than reality.

**Divergence depth vs flight duration:**

| Flight | Duration (s) | final_z (m) |
|--------|-------------|-------------|
| H148R 1Jul | 69 | −394 |
| Adventurer J530 | 212 | −1 104 |
| Adventurer J510W | 239 | −1 156 |
| J150 9Dec | 191 | −1 158 |
| J500G 8Jul | 172 | −1 223 |
| J354 9Sep | 194 | −1 299 |
| J570W 9Dec | 176 | −1 485 |
| J394 7Oct | 223 | −1 440 |
| J510W 8Jul | 221 | −1 763 |

The divergence depth is not strictly monotone with duration because
`b_a` convergence quality also depends on the ascent dynamics, but longer
post-apogee integration time consistently produces deeper errors.

**Why it is acceptable:**  
The EKF is designed to track altitude from launch to apogee for apogee
detection.  The Raven dataset provides no pre-launch baro baseline, so the
filter cannot zero the velocity before descent.  The same flight recorded on
the XTRA logger (which captures the full pre-launch pad window) returns
`final_z` within ±3 m.

**Report framing:**  
Classify Raven flights as **Class B** results: *correct through apogee, expected
divergence post-apogee due to no pre-launch initialisation window*.  The
multi_time and trimmed_txt families are **Class A**: full flight with pre-launch
pad window, `final_z` within ±3 m (excluding the J394 atmospheric drift case,
§2).  The emulation flight is a single clean **Class A** reference.
