function fetch_results(varargin)
% FETCH_RESULTS  Download the archived simulation result files into results/.
%
%   The .mat files produced by the five simulation campaigns total ~174 MB,
%   and one of them exceeds GitHub's 100 MiB per-file limit, so they are not
%   stored in this repository. They are archived on Zenodo instead. This
%   function downloads them into results/, so that REPRODUCE_ALL_RESULTS can
%   be run without rerunning the simulations and without a solver licence.
%
%   fetch_results
%       Download every archived .mat file not already present in results/.
%
%   fetch_results('nominal')
%       Download only files whose name contains 'nominal' (case-insensitive).
%       Useful because the manuscript figures need only Results_nominal_wltc_*,
%       which is ~10 MB, rather than the ~105 MB Monte Carlo archive.
%
%   fetch_results(___, 'Force', true)
%       Re-download even when a file of the expected size is already present.
%
%   fetch_results(___, 'RecordId', '1234567')
%       Use a specific Zenodo record instead of the one configured below.
%
%   Requires an internet connection. No solver licence is needed.
%
%   See also REPRODUCE_ALL_RESULTS, RUN_ALL_SIMULATIONS.

% -------------------------------------------------------------------------
% Zenodo record holding the result archive.
ZENODO_RECORD_ID = '22134357';

% ---- Arguments ----------------------------------------------------------
p = inputParser;
p.FunctionName = mfilename;
p.addOptional('Pattern', '', @(s) (ischar(s) || isstring(s)) && ...
    ~ismember(lower(char(s)), {'force', 'recordid'}));
p.addParameter('Force', false, @(x) islogical(x) && isscalar(x));
p.addParameter('RecordId', ZENODO_RECORD_ID, @(s) ischar(s) || isstring(s));
p.parse(varargin{:});

pattern  = char(p.Results.Pattern);
force    = p.Results.Force;
recordId = char(p.Results.RecordId);

if isempty(recordId) || ~all(isstrprop(recordId, 'digit'))
    error('fetch_results:NoRecordId', ...
        ['No Zenodo record ID is configured.\n' ...
         'Edit ZENODO_RECORD_ID near the top of fetch_results.m, or call\n' ...
         '    fetch_results(''RecordId'', ''1234567'')\n' ...
         'For https://zenodo.org/records/1234567 the record ID is 1234567.']);
end

% ---- Paths --------------------------------------------------------------
thisFile = mfilename('fullpath');
addpath(fileparts(thisFile));
rootDir    = initProjectPaths(thisFile);
resultsDir = ensureResultsDir(rootDir);

% ---- Record metadata ----------------------------------------------------
apiUrl = sprintf('https://zenodo.org/api/records/%s', recordId);
fprintf('Reading record metadata:\n  %s\n', apiUrl);

try
    meta = webread(apiUrl, weboptions('ContentType', 'json', 'Timeout', 60));
catch ME
    error('fetch_results:MetadataFailed', ...
        ['Could not read the Zenodo record metadata from\n  %s\n' ...
         'Check the record ID and your internet connection.\n' ...
         'Underlying error: %s'], apiUrl, ME.message);
end

entries = local_fileEntries(meta, recordId);
if isempty(entries)
    error('fetch_results:NoFiles', ...
        'The Zenodo record %s reports no files.', recordId);
end

% ---- Select the files we want ------------------------------------------
keep = false(size(entries));
for i = 1:numel(entries)
    isMat   = endsWith(lower(entries(i).name), '.mat');
    matches = isempty(pattern) || contains(lower(entries(i).name), lower(pattern));
    keep(i) = isMat && matches;
end
entries = entries(keep);

if isempty(entries)
    if isempty(pattern)
        error('fetch_results:NoMatFiles', ...
            'The Zenodo record %s contains no .mat files.', recordId);
    else
        error('fetch_results:NoMatch', ...
            'No .mat file in Zenodo record %s matches ''%s''.', recordId, pattern);
    end
end

fprintf('\n%d file(s) selected. Target folder:\n  %s\n\n', numel(entries), resultsDir);

% ---- Download -----------------------------------------------------------
nDownloaded = 0;
nSkipped    = 0;

for i = 1:numel(entries)
    e          = entries(i);
    targetPath = fullfile(resultsDir, e.name);

    if ~force && local_alreadyGood(targetPath, e.bytes)
        fprintf('  [skip]     %-48s already present\n', e.name);
        nSkipped = nSkipped + 1;
        continue;
    end

    if e.bytes > 0
        fprintf('  [download] %-48s %s\n', e.name, local_humanSize(e.bytes));
    else
        fprintf('  [download] %-48s\n', e.name);
    end

    partPath  = [targetPath '.part'];
    savedPath = '';
    try
        % websave returns the path it actually wrote to.
        savedPath = websave(partPath, e.url, weboptions('Timeout', 1800));

        info = dir(savedPath);
        if isempty(info)
            error('fetch_results:Missing', 'Download produced no file.');
        end

        if e.bytes > 0 && info.bytes ~= e.bytes
            error('fetch_results:SizeMismatch', ...
                ['Downloaded %d bytes but the record lists %d bytes.\n' ...
                 'The download was probably truncated or redirected to an ' ...
                 'error page.'], info.bytes, e.bytes);
        end

        local_verifyChecksum(savedPath, e.md5, e.name);

        movefile(savedPath, targetPath, 'f');
        savedPath   = '';
        nDownloaded = nDownloaded + 1;

    catch ME
        if ~isempty(savedPath) && isfile(savedPath)
            delete(savedPath);
        end
        if isfile(partPath)
            delete(partPath);
        end
        error('fetch_results:DownloadFailed', ...
            'Failed to download %s from\n  %s\nUnderlying error: %s', ...
            e.name, e.url, ME.message);
    end
end

fprintf('\nDone. %d downloaded, %d already present.\n', nDownloaded, nSkipped);
if nDownloaded > 0 || nSkipped > 0
    fprintf('You can now run REPRODUCE_ALL_RESULTS.\n');
end

end

% =========================================================================
function entries = local_fileEntries(meta, recordId)
% Normalise the file list from a Zenodo record into a struct array with
% fields: name, url, bytes, md5.
%
% Zenodo has used more than one JSON shape for this (a plain "files" array,
% and an InvenioRDM-style "files.entries" object), so both are handled.
% Note that MATLAB's jsondecode mangles field names containing dots, so the
% file name is always taken from a field inside the entry, never from the
% key of the entries object.

entries = struct('name', {}, 'url', {}, 'bytes', {}, 'md5', {});

if ~isfield(meta, 'files')
    return;
end

raw = meta.files;
items = {};

if isstruct(raw) && isscalar(raw) && isfield(raw, 'entries')
    inner = raw.entries;
    if isstruct(inner)
        fn = fieldnames(inner);
        for i = 1:numel(fn)
            items{end+1} = inner.(fn{i}); %#ok<AGROW>
        end
    elseif iscell(inner)
        items = inner(:).';
    end
elseif iscell(raw)
    items = raw(:).';
elseif isstruct(raw)
    for i = 1:numel(raw)
        items{end+1} = raw(i); %#ok<AGROW>
    end
end

for i = 1:numel(items)
    it = items{i};
    if ~isstruct(it)
        continue;
    end

    name = local_firstField(it, {'key', 'filename'});
    if isempty(name)
        continue;
    end

    bytes = 0;
    for f = {'size', 'filesize'}
        if isfield(it, f{1}) && isnumeric(it.(f{1})) && isscalar(it.(f{1}))
            bytes = double(it.(f{1}));
            break;
        end
    end

    md5 = '';
    if isfield(it, 'checksum') && (ischar(it.checksum) || isstring(it.checksum))
        md5 = char(it.checksum);
        md5 = regexprep(md5, '^md5:', '');   % Zenodo prefixes the algorithm
        if ~all(isstrprop(md5, 'xdigit')) || numel(md5) ~= 32
            md5 = '';                        % not an MD5 we can check
        end
    end

    url = '';
    if isfield(it, 'links') && isstruct(it.links)
        url = local_firstField(it.links, {'content', 'download', 'self'});
    end
    if isempty(url)
        % Fall back to the conventional public download URL.
        url = sprintf('https://zenodo.org/records/%s/files/%s?download=1', ...
            recordId, local_urlEncode(name));
    end

    entries(end+1) = struct('name', name, 'url', url, ...
        'bytes', bytes, 'md5', md5); %#ok<AGROW>
end

end

% =========================================================================
function v = local_firstField(s, names)
v = '';
for i = 1:numel(names)
    if isfield(s, names{i})
        candidate = s.(names{i});
        if ischar(candidate) || isstring(candidate)
            candidate = char(candidate);
            if ~isempty(candidate)
                v = candidate;
                return;
            end
        end
    end
end
end

% =========================================================================
function tf = local_alreadyGood(targetPath, expectedBytes)
tf = false;
info = dir(targetPath);
if isempty(info) || info.isdir
    return;
end
if expectedBytes > 0
    tf = (info.bytes == expectedBytes);
else
    tf = (info.bytes > 0);
end
end

% =========================================================================
function local_verifyChecksum(filePath, expectedMd5, name)
% Verify the MD5 reported by Zenodo. Silently skipped if no checksum was
% reported or if the Java digest is unavailable in this MATLAB session.

if isempty(expectedMd5)
    return;
end

try
    digest = java.security.MessageDigest.getInstance('MD5');
    fid = fopen(filePath, 'r');
    if fid < 0
        return;
    end
    cleanup = onCleanup(@() fclose(fid));
    while true
        chunk = fread(fid, 4*1024*1024, '*uint8');
        if isempty(chunk)
            break;
        end
        digest.update(typecast(chunk, 'int8'));
    end
    raw    = typecast(digest.digest(), 'uint8');
    actual = lower(reshape(dec2hex(raw, 2).', 1, []));
catch
    return;   % no Java digest available; size check already passed
end

if ~strcmpi(actual, expectedMd5)
    error('fetch_results:ChecksumMismatch', ...
        ['MD5 mismatch for %s.\n  expected %s\n  actual   %s\n' ...
         'The file is corrupt; delete it and try again.'], ...
        name, lower(expectedMd5), actual);
end
end

% =========================================================================
function s = local_humanSize(bytes)
if bytes >= 1024^3
    s = sprintf('%.1f GB', bytes / 1024^3);
elseif bytes >= 1024^2
    s = sprintf('%.1f MB', bytes / 1024^2);
elseif bytes >= 1024
    s = sprintf('%.1f kB', bytes / 1024);
else
    s = sprintf('%d B', bytes);
end
end

% =========================================================================
function out = local_urlEncode(name)
% Percent-encode the characters that realistically appear in a file name.
out = name;
out = strrep(out, '%', '%25');
out = strrep(out, ' ', '%20');
out = strrep(out, '#', '%23');
out = strrep(out, '?', '%3F');
end
