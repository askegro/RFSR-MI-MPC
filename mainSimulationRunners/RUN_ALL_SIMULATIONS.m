function RUN_ALL_SIMULATIONS(nWorkers)
% mainSimulationRunners/RUN_ALL_SIMULATIONS.m
%
% ============================ CLICK AND PLAY =============================
% Regenerates ALL five result files that Section VI is computed from, by
% running the five simulation campaigns in sequence.
%
%   RUN_ALL_SIMULATIONS        % uses a default worker count
%   RUN_ALL_SIMULATIONS(8)     % uses 8 parallel workers for the sweeps
%
% Campaign -> result file -> manuscript use
%   1. run_nominal_wltc
%        results/Results_nominal_wltc_<date>.mat
%        Table III, Table V, Figs. 2-4, Sections VI-A.1 and VI-A.3 text,
%        Appendix-A SOS2 numbers
%   2. run_samestate_proposed
%        results/Results_samestate_proposed_<date>.mat
%        Table IV, column 1 (proposed-controller trajectory)
%   3. run_samestate_rulebased
%        results/Results_samestate_rulebased_<date>.mat
%        Table IV, column 2 (rule-based-driver trajectory)
%   4. run_montecarlo_ics         (parallel)
%        results/Results_montecarlo_ics_<date>.mat
%        Table VI
%   5. run_robustness_sweeps           (parallel)
%        results/Results_robustness_sweeps_<date>.mat
%        Table VII, Sections VI-B.2 to VI-B.4
%
% -------------------------------------------------------------------------
% WARNING: THIS TAKES HOURS.
% -------------------------------------------------------------------------
% Campaigns 2 and 3 solve the full subset-selection formulation at every
% state with a 100-s reference time limit; campaigns 4 and 5 run many full
% WLTC cycles. Only run this if you want to regenerate the data from
% scratch. To reproduce the published numbers from the shipped result
% files, run REPRODUCE_ALL_RESULTS.m at the project root instead.
%
% Requires YALMIP and Gurobi on the MATLAB path (Gurobi 13.0.1 was used for
% the manuscript). Campaigns 4 and 5 additionally use Parallel Computing
% Toolbox; each worker uses one Gurobi thread. A sensible worker count is
% about floor(0.75 * number of physical cores).
%
% Each campaign writes its own timestamped .mat into results/. The
% post-processing scripts always pick up the most recent matching file, so
% previous result files are left untouched.
% =========================================================================

    if nargin < 1 || isempty(nWorkers)
        nWorkers = max(1, floor(0.75 * local_physical_cores()));
    end

    RS_thisFile = mfilename('fullpath');
    RS_rootDir  = initProjectPaths(RS_thisFile);

    RS_campaigns = { ...
        'run_nominal_wltc',      false; ...
        'run_samestate_proposed',              false; ...
        'run_samestate_rulebased',  false; ...
        'run_montecarlo_ics',              true;  ...
        'run_robustness_sweeps',                true;  ...
    };

    RS_n      = size(RS_campaigns, 1);
    RS_status = cell(RS_n, 1);
    RS_secs   = zeros(RS_n, 1);

    fprintf('\n%s\n', repmat('=', 1, 78));
    fprintf('RUN_ALL_SIMULATIONS -- started %s\n', char(datetime('now')));
    fprintf('Project root : %s\n', RS_rootDir);
    fprintf('Results go to: %s\n', fullfile(RS_rootDir, 'results'));
    fprintf('%s\n\n', repmat('=', 1, 78));

    RS_needPool = any([RS_campaigns{:, 2}]);
    if RS_needPool
        RS_p = gcp('nocreate');
        if isempty(RS_p)
            fprintf('Starting parallel pool with %d workers...\n', nWorkers);
            parpool(nWorkers);
        else
            fprintf('Reusing existing parallel pool (%d workers).\n', RS_p.NumWorkers);
        end
        fprintf('\n');
    end

    RS_t0 = tic;
    for RS_i = 1:RS_n
        RS_name = RS_campaigns{RS_i, 1};
        fprintf('%s\n', repmat('-', 1, 78));
        fprintf('[%d/%d] %s   (started %s)\n', RS_i, RS_n, RS_name, ...
            char(datetime('now', 'Format', 'HH:mm:ss')));
        fprintf('%s\n', repmat('-', 1, 78));
        RS_ti = tic;
        try
            % Each campaign is executed inside its own throw-away function
            % workspace (local_run_script). The runner scripts begin with
            % "clc; close all; clearvars;", so running them directly in this
            % function's workspace would wipe the loop state.
            local_run_script(RS_name);
            RS_status{RS_i} = 'OK';
        catch RS_err
            RS_status{RS_i} = sprintf('FAILED: %s', RS_err.message);
            fprintf(2, '\n!! %s failed: %s\n\n', RS_name, RS_err.message);
        end
        RS_secs(RS_i) = toc(RS_ti);
        fprintf('[%d/%d] %s finished in %.1f min -- %s\n\n', ...
            RS_i, RS_n, RS_name, RS_secs(RS_i)/60, RS_status{RS_i});
    end

    fprintf('\n%s\n', repmat('=', 1, 78));
    fprintf('RUN_ALL_SIMULATIONS -- summary (total %.1f min)\n', toc(RS_t0)/60);
    fprintf('%s\n', repmat('=', 1, 78));
    for RS_i = 1:RS_n
        fprintf('  %-36s %8.1f min   %s\n', RS_campaigns{RS_i,1}, RS_secs(RS_i)/60, RS_status{RS_i});
    end
    fprintf('%s\n', repmat('=', 1, 78));
    fprintf('Next step: run REPRODUCE_ALL_RESULTS.m at the project root.\n\n');
end

function local_run_script(scriptName)
% Execute one runner script in an isolated workspace. The script shares
% this function's workspace, so its leading "clearvars" cannot touch the
% caller's loop state. mainSimulationRunners/ is already on the MATLAB
% path via initProjectPaths.
    eval(scriptName);
end

function n = local_physical_cores()
    n = 4;
    try
        n = feature('numcores');
    catch
    end
    if ~isscalar(n) || ~isfinite(n) || n < 1
        n = 4;
    end
end
