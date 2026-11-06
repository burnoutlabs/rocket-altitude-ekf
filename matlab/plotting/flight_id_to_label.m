function label = flight_id_to_label(flight_id)
% flight_id_to_label  Map canonical flight_id string to a clean human-readable label.
%
% Returns the flight_id itself (as char) if the ID is not in the map.
%
% Usage:
%   label = flight_id_to_label('multi_time_csv_e190_9dec2017_j570w_onboard')
%   % returns: 'E190 J570W - 9 Dec 2017 (multi-time CSV)'

m = struct();

% 1) 38 mm Prototype E190
m.emulation_csv_e190_8jul2017_j510w_emulationdata = 'E190 J510W - 8 Jul 2017 (emulation CSV)';
m.multi_time_csv_e190_1jul2017_h148r_1_xtra       = 'E190 H148R - 1 Jul 2017 (multi-time CSV)';
m.multi_time_csv_e190_7oct2017_j394_1_xtra        = 'E190 J394 - 7 Oct 2017 (multi-time CSV)';
m.multi_time_csv_e190_8jul2017_j510w_1_xtra       = 'E190 J510W - 8 Jul 2017 (multi-time CSV)';
m.multi_time_csv_e190_9dec2017_j150_onboard       = 'E190 J150 - 9 Dec 2017 (multi-time CSV)';
m.multi_time_csv_e190_9dec2017_j570w_onboard      = 'E190 J570W - 9 Dec 2017 (multi-time CSV)';
m.multi_time_csv_e190_9sep2017_j354_1_xtra        = 'E190 J354 - 9 Sep 2017 (multi-time CSV)';
m.raven_csv_e190_1jul2017_h148r_1_raven           = 'E190 H148R - 1 Jul 2017 (Raven CSV)';
m.raven_csv_e190_7oct2017_j394_1_raven            = 'E190 J394 - 7 Oct 2017 (Raven CSV)';
m.raven_csv_e190_8jul2017_j510w_raven             = 'E190 J510W - 8 Jul 2017 (Raven CSV)';
m.raven_csv_e190_9dec2017_j150_raven              = 'E190 J150 - 9 Dec 2017 (Raven CSV)';
m.raven_csv_e190_9dec2017_j570w_raven             = 'E190 J570W - 9 Dec 2017 (Raven CSV)';
m.raven_csv_e190_9sep2017_j354_raven              = 'E190 J354 - 9 Sep 2017 (Raven CSV)';

% 2) Madcow Adventurer
m.raven_csv_20210417_adventurer_j510w_1_raven     = 'Adventurer J510W - 17 Apr 2021 (Raven CSV)';
m.raven_csv_20210417_adventurer_j530_1_raven      = 'Adventurer J530 - 17 Apr 2021 (Raven CSV)';
m.trimmed_txt_20220610_adv_j570_trimmed           = 'Adventurer J570 - 10 Jun 2022 (trimmed TXT)';
m.trimmed_txt_20220611_adv_j530_trimmed           = 'Adventurer J530 - 11 Jun 2022 (trimmed TXT)';
m.trimmed_txt_22020609_adv_j825r_f1_trimmed       = 'Adventurer J825R - 9 Jun 2022 (trimmed TXT)';

% 3) LOC Precision Vulcanite
m.trimmed_txt_20210410_vulcanite_h128w_10_trimmed = 'Vulcanite H128W-10 - 10 Apr 2021 (trimmed TXT)';
m.trimmed_txt_20210410_vulcanite_j270w_14a_trimmed = 'Vulcanite J270W-14A - 10 Apr 2021 (trimmed TXT)';

% 4) Madcow Mini DX3
m.trimmed_txt_20210205_minidx3_g77_10r_l_trimmed  = 'Mini DX3 G77-10R - 5 Feb 2021 (trimmed TXT)';
m.trimmed_txt_20210205_minidx3_g79_10w_l_trimmed  = 'Mini DX3 G79-10W - 5 Feb 2021 (trimmed TXT)';
m.trimmed_txt_20210410_minidx3_h128w_14_trimmed   = 'Mini DX3 H128W-14 - 10 Apr 2021 (trimmed TXT)';

key = char(flight_id);
if isfield(m, key)
    label = m.(key);
else
    label = key;
end
end
