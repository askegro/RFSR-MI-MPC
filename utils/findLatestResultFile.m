function fileName = findLatestResultFile(pattern, runHint)
% FINDLATESTRESULTFILE Return the newest file matching a result pattern.

    candidates = dir(pattern);
    if isempty(candidates)
        if nargin < 2 || isempty(runHint)
            runHint = 'Run the corresponding simulation first.';
        end
        error('findLatestResultFile:MissingResult', ...
              'No %s file found on the path. %s', pattern, runHint);
    end
    [~, ix] = sort([candidates.datenum], 'descend');
    fileName = fullfile(candidates(ix(1)).folder, candidates(ix(1)).name);
end
