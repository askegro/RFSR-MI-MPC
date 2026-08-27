function rootDir = initProjectPaths(anchorPath)
% INITPROJECTPATHS Add project folders required by the simulation stack.
%
% This is the single path bootstrap point for scripts and callable runners.
% Pass mfilename('fullpath') from the caller, or omit for current directory.

    if nargin < 1 || isempty(anchorPath)
        anchorPath = pwd;
    end

    if isfolder(anchorPath)
        startDir = anchorPath;
    else
        startDir = fileparts(anchorPath);
    end

    rootDir = findProjectRoot(startDir);

    folders = {
        rootDir
        fullfile(rootDir, 'config')
        fullfile(rootDir, 'build')
        fullfile(rootDir, 'solutionHandling')        
        fullfile(rootDir, 'plant')
        fullfile(rootDir, 'state_machine')
        fullfile(rootDir, 'control')
        fullfile(rootDir, 'control', 'mpc')
        fullfile(rootDir, 'utils')
        fullfile(rootDir, 'data')
        fullfile(rootDir, 'application')
        fullfile(rootDir, 'bootstrap')
        fullfile(rootDir, 'mainSimulationRunners')
        fullfile(rootDir, 'postProcess')
        fullfile(rootDir, 'figureGeneration')
    };

    for i = 1:numel(folders)
        if isfolder(folders{i})
            addpath(folders{i});
        end
    end
end

function rootDir = findProjectRoot(startDir)
    rootDir = startDir;
    while true
        if isfile(fullfile(rootDir, 'config', 'default_config.m')) && ...
           isfolder(fullfile(rootDir, 'control')) && ...
           isfolder(fullfile(rootDir, 'plant'))
            return;
        end

        parentDir = fileparts(rootDir);
        if strcmp(parentDir, rootDir)
            error('initProjectPaths:RootNotFound', ...
                  'Could not locate project root starting from %s.', startDir);
        end
        rootDir = parentDir;
    end
end
