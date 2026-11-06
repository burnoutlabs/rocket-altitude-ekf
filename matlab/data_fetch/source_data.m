function urls = source_data()
% source_data.m
% Master dataset URL list for this project (self-contained matlab/ setup).
%
% Revision 2 (2026-04-25): Removed 14 dead-weight sources (BASE loggers,
% unparseable xlsx, standalone GPS/tracker CSVs). Added 10 new Tier-1
% sources (same parsers, proven hardware families). See archive/data_investigation/
% data-sources-to-cut.md and data-sources-to-add.md for full rationale.
%
% Groups:
%   1) 38 mm Prototype E190 — development platform, multiple motor profiles
%       Parsers: raven_csv, multi_time_csv, emulation_csv
%       Note: Raven flights are ascent-phase only (post-apogee body-frame flip).
%             BASE logger variants excluded (0.6-1 Hz rate causes EKF drift).
%   2) Madcow Adventurer — mid-power validation platform
%       Parser: raven_csv (Apr-2021), trimmed_txt (Jun-2022)
%       Note: Raven flights are ascent-phase only.
%   3) LOC Precision Vulcanite — dual-deploy robustness platform
%       Parser: trimmed_txt
%   4) Madcow Mini DX3 — additional trimmed_txt validation flights
%       Parser: trimmed_txt

urls = {
    % ---------------------------------------------------------------
    % 1) 38 mm Prototype E190
    % ---------------------------------------------------------------
    % --- Aerotech H148R  (1 Jul 2017) ---
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_1JUL2017_H148R_1_XTRA.csv'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_1JUL2017_H148R_1_Raven.csv'

    % --- Aerotech J500G  (8 Jul 2017, same day as J510W) ---
    % Raven-only flight (no multi_time cross-validation partner). Part of the
    % 25-flight dataset the report describes, so it stays in the list.
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J500G_Raven.csv'

    % --- Aerotech J510W  (8 Jul 2017) ---
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J510W_Raven.csv'
    % Second XTRA record (/213) of the same physical flight as E190_8JUL2017_J510W_1_XTRA.csv;
    % its sensor data matches that file. Kept because the report's 25-flight run includes
    % it, but cross-logger agreement counts this flight once (6 independent pairs, not 7).
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J510W_1_XTRA_213.csv'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J510W_1_XTRA.csv'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J510W_EmulationData.csv'

    % --- CTI J354  (9 Sep 2017) ---
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9SEP2017_J354_1_XTRA.csv'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9SEP2017_J354_Raven.csv'

    % --- CTI J394  (7 Oct 2017) ---
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_7OCT2017_J394_1_XTRA.csv'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_7OCT2017_J394_1_Raven.csv'

    % --- CTI J150  (9 Dec 2017) ---
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9DEC2017_J150_OnBoard.csv'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9DEC2017_J150_Raven.csv'

    % --- Aerotech J570W  (9 Dec 2017) ---
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9DEC2017_J570W_OnBoard.csv'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9DEC2017_J570W_Raven.csv'

    % ---------------------------------------------------------------
    % 2) Madcow Adventurer
    % ---------------------------------------------------------------
    % --- Apr-2021 (Raven altimeter) ---
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/Adventurer/20210417_Adventurer_J510W_1_Raven.csv'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/Adventurer/20210417_Adventurer_J530_1_Raven.csv'

    % --- Jun-2022 (trimmed TXT, ICM/MS5 logger) ---
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/Adventurer/22020609_Adv_J825R_F1_Trimmed.TXT'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/Adventurer/20220610_ADV_J570_Trimmed.TXT'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/Adventurer/20220611_Adv_J530_Trimmed.TXT'

    % ---------------------------------------------------------------
    % 3) LOC Precision Vulcanite
    % NOTE: 20210205 G78-10G-L dropped — 116 systematic baro steps throughout flight
    %       (static port oscillation under parachute). Unusable for EKF.
    % ---------------------------------------------------------------
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/Vulcanite/20210410_Vulcanite_J270W-14A_Trimmed.TXT'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/Vulcanite/20210410_Vulcanite_H128W-10_Trimmed.TXT'

    % ---------------------------------------------------------------
    % 4) Madcow Mini DX3 — First Flights
    % ---------------------------------------------------------------
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210205_MiniDX3_G77-10R-L_trimmed.TXT'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210205_MiniDX3_G79-10W-L_trimmed.TXT'
    'https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210410_MiniDX3_H128W-14_Trimmed.TXT'
};
end
