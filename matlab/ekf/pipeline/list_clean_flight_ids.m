function flight_ids = list_clean_flight_ids(cleaned_dir)
% list_clean_flight_ids
% Return sorted flight folder names under _data_clean/flights.

flights_dir = fullfile(cleaned_dir, 'flights');
if ~isfolder(flights_dir)
    error('Cleaned flights directory not found: %s', flights_dir);
end

entries = dir(flights_dir);
entries = entries([entries.isdir]);
entries = entries(~ismember({entries.name}, {'.', '..'}));

flight_ids = sort(string({entries.name}));
end

