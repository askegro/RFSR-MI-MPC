function resultsDir = ensureResultsDir(rootDir)
% ENSURERESULTSDIR  Return path to <rootDir>/results, creating it if needed.
%
%   If the folder did not previously exist it is created and then opened
%   in the system file explorer so the user can see where outputs land.

    resultsDir = fullfile(rootDir, 'results');
    if ~isfolder(resultsDir)
        mkdir(resultsDir);
        fprintf('Created results folder:\n  %s\n', resultsDir);
        if ispc
            winopen(resultsDir);
        elseif ismac
            system(sprintf('open ''%s''', resultsDir));
        else
            system(sprintf('xdg-open ''%s'' &', resultsDir));
        end
    end
end
