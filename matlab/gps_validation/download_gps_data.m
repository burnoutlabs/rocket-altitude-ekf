% download_gps_data.m
%
% Downloads GPS validation files listed in gps_data.m into
% gps_validation/_gps_raw/ (gitignored).
%
% Re-running skips already-downloaded files unless overwrite = true.
% After downloading, inspect files then run process_gps_data.m.

clear; clc;

here = fileparts(mfilename('fullpath'));
if isempty(here)
    here = pwd;
end

addpath(here);

out_dir = fullfile(here, '_gps_raw');
if ~isfolder(out_dir)
    mkdir(out_dir);
    fprintf('Created: %s\n', out_dir);
end

overwrite      = false;
timeout_sec    = 60;
opts           = weboptions('Timeout', timeout_sec);

entries = gps_data();
if isempty(entries)
    error('gps_data.m returned no entries.');
end

rows = cell(numel(entries), 5);

fprintf('\n%-55s  %s\n', 'File', 'Status');
fprintf('%s\n', repmat('-', 1, 70));

for i = 1:numel(entries)
    url      = entries(i).url;
    filename = entries(i).file_name;
    out_path = fullfile(out_dir, filename);

    if isfile(out_path) && ~overwrite
        info   = dir(out_path);
        status = 'skipped_exists';
        bytes  = info.bytes;
        msg    = 'Already exists.';
        fprintf('%-55s  skipped (%.1f KB)\n', filename, bytes / 1024);
    else
        try
            websave(out_path, url, opts);
            info   = dir(out_path);
            status = 'downloaded';
            bytes  = info.bytes;
            msg    = '';
            fprintf('%-55s  downloaded (%.1f KB)\n', filename, bytes / 1024);
        catch ME
            status = 'failed';
            bytes  = NaN;
            msg    = ME.message;
            fprintf('%-55s  FAILED: %s\n', filename, msg);
        end
    end

    rows(i, :) = {url, filename, status, bytes, msg};
end

manifest = cell2table(rows, 'VariableNames', ...
    {'url', 'file_name', 'status', 'bytes', 'message'});
writetable(manifest, fullfile(out_dir, 'gps_download_manifest.csv'));

fprintf('\nDone. Files in: %s\n', out_dir);
fprintf('Next: inspect files, then run process_gps_data.m\n');
