% download_source_data.m
%
% Downloads URLs listed in source_data.m into ./_data_raw (gitignored).

overwriteExisting = false;
timeoutSeconds = 60;

this_dir = fileparts(mfilename('fullpath'));
matlabDir = fileparts(this_dir);
outputDir = fullfile(matlabDir, '_data_raw');
if ~isfolder(outputDir)
    mkdir(outputDir);
end

% Ensure the source-data module is resolvable when this script is run by path.
addpath(this_dir);

urls = source_data();
if isempty(urls)
    error('source_data.m returned no URLs.');
end

opts = weboptions('Timeout', timeoutSeconds);
rows = cell(numel(urls), 5); % url, file_name, status, bytes, message

for i = 1:numel(urls)
    url = urls{i};
    baseUrl = regexp(url, '^[^?#]+', 'match', 'once');
    [~, name, ext] = fileparts(baseUrl);
    if isempty(name)
        fileName = sprintf('file_%02d.dat', i);
    else
        fileName = [name ext];
    end

    outPath = fullfile(outputDir, fileName);
    status = 'downloaded';
    message = '';

    try
        if isfile(outPath) && ~overwriteExisting
            status = 'skipped_exists';
            message = 'Already exists.';
        else
            websave(outPath, url, opts);
        end
    catch ME
        status = 'failed';
        message = ME.message;
    end

    bytes = NaN;
    if isfile(outPath)
        info = dir(outPath);
        bytes = info.bytes;
    end

    rows(i, :) = {url, fileName, status, bytes, message};
    fprintf('[%d/%d] %s (%s)\n', i, numel(urls), fileName, status);
end

manifest = cell2table(rows, 'VariableNames', ...
    {'url', 'file_name', 'status', 'bytes', 'message'});
writetable(manifest, fullfile(outputDir, 'download_manifest.csv'));

fprintf('\nDone. Files are in: %s\n', outputDir);
