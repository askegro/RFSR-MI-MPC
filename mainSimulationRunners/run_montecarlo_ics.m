% FILE: lightweightWrappers/run_montecarlo_ics.m
%
% Manuscript Section VI-B.1 (Monte Carlo Robustness).
% Runs 20 independent realisations of the WLTC drive cycle with
% randomised initial cell states (SOC, SOH, RNG seeds). For each
% realisation it runs:
%   Variant A = baseline  (sorting off, monotone off)
%   Variant D = proposed  (sorting on,  monotone on)
%
% Output: Results_montecarlo_ics_YYYYMMDD.mat
%   Results.A(r).sim  ... Variant A trace for realisation r
%   Results.D(r).sim  ... Variant D trace for realisation r
%   Summary.<vid>.<metric>_mean / _std over the 20 realisations
%   nRuns
%
% Metrics summarised per variant:
%   tracking      mean relative pack-power tracking error [%]
%   socstd        mean cross-sectional SOC standard deviation [%]
%   p95solve      95th-percentile Gurobi internal solver runtime [ms] (solver_time = r.runtime, active steps only; excludes YALMIP overhead)
%   medsolve      median Gurobi internal solver runtime [ms] (same filter as p95solve; matches extract_robustness_metrics.med_solve_ms)
%   optrate       fraction of active steps with proven optimality [%]
%
% Pack power is reconstructed as p_pack = i_pack_cmd * v_pack
% (does NOT depend on log.p_pack_cmd, so this analyzer is robust to
% pre-Stage-2 result files where p_pack_cmd was NaN).

% Only clear the workspace when run as the entry point, not when called
% from a wrapper script (e.g. run_VC_all) that owns timing variables.
if ~exist('t_pipeline','var')
    clc; clearvars; close all;
end
rootDir = initProjectPaths(mfilename('fullpath'));

fprintf('\n>>> Entering run_montecarlo_ics\n');

nRuns    = 20;
Results  = struct();
Variants = {'A', 'D'};   % standardised V-B/C variant labels

% -------------------------------------------------------------------------
% Run 20 independent realisations in parallel.
%
% Each parfor iteration handles one realisation r, running both Variant A
% and Variant D sequentially within the same worker.  The two variants for
% a given r share the same plant seeds so their trajectories are comparable.
%
% HOW TO CONTROL WORKER COUNT
%   Call parpool(N) before this script, e.g. parpool(8).
%   Each worker uses 1 Gurobi thread (set via gurobi_threads below).
%   Rule of thumb: N_workers = floor(physical_cores * 0.75).
% -------------------------------------------------------------------------
sims_A = cell(1, nRuns);   % collect worker output into cell arrays
sims_D = cell(1, nRuns);   % (struct arrays are not parfor-safe)

parfor r = 1:nRuns
    fprintf('[MC] Realisation %2d / %d  starting...\n', r, nRuns);

    % ------------------------------------------------------------------
    % Warmup pass: 50 steps with the same seeds as Variant A.
    % Populates YALMIP's solver cache (cachesolvers=1) and loads Gurobi
    % before the measured runs, eliminating the cold-start timing bias
    % observed in the first few iterations of each worker.
    % The result is intentionally discarded.
    % ------------------------------------------------------------------
    optsWarm = struct('enable_sorting',  false, ...
                      'enable_monotone', false, ...
                      'progress_every_steps', 0, ...
                      'gurobi_threads',  1,    ...
                      'seed',      1337 + r - 1, ...
                      'sort_seed', 42   + r - 1, ...
                      'soc_seed',  4242 + r - 1, ...
                      'simSteps',  50,           ...
                      'variant_id', 'warm');
    tcst_run_variant(optsWarm);   %#ok<PFBNS> result discarded

    % Variant A: full feasible set, no sorting, no monotone
    optsA = struct('enable_sorting',  false, ...
                   'enable_monotone', false, ...
                   'progress_every_steps', 0, ...
                   'gurobi_threads',  1,    ...   % one thread per worker
                   'seed',      1337 + r - 1, ...
                   'sort_seed', 42   + r - 1, ...
                   'soc_seed',  4242 + r - 1, ...
                   'variant_id', 'A');
    sims_A{r} = tcst_run_variant(optsA);

    % Variant D: sorting + monotone
    optsD = struct('enable_sorting',  true,  ...
                   'enable_monotone', true,  ...
                   'progress_every_steps', 0, ...
                   'gurobi_threads',  1,    ...   % one thread per worker
                   'seed',      1337 + r - 1, ...
                   'sort_seed', 42   + r - 1, ...
                   'soc_seed',  4242 + r - 1, ...
                   'variant_id', 'D');
    sims_D{r} = tcst_run_variant(optsD);
    fprintf('[MC] Realisation %2d / %d  done.\n', r, nRuns);
end

% Reassemble into the Results struct used by downstream analysers
for r = 1:nRuns
    Results.A(r).sim = sims_A{r};
    Results.D(r).sim = sims_D{r};
end


%% --- Summary over realisations --------------------------------------
Summary = struct();
for vi = 1:numel(Variants)
    vid       = Variants{vi};
    tracking  = nan(nRuns, 1);
    socstd    = nan(nRuns, 1);
    p95solve  = nan(nRuns, 1);
    medsolve  = nan(nRuns, 1);
    optrate   = nan(nRuns, 1);
    for r = 1:nRuns
        logi   = Results.(vid)(r).sim.log;
        active = ~isnan(logi.p_pack_req) & ~logical(logi.rest_skip);

        % Delivered pack power: use plant-measured value (v_pack_meas * i_pack_cmd),
        % consistent with the manuscript tracking metric definition (Sec. V-D,
        % eq:trackingMetric).  v_pack in the log is the MPC-predicted first-step
        % pack voltage, which differs from the closed-loop plant measurement.
        p_del  = logi.p_pack_meas(active);
        p_req  = logi.p_pack_req(active);
        e      = abs(p_del - p_req) ./ max(abs(p_req), 1e-9);
        tracking(r) = mean(e, 'omitnan') * 100;

        socstd(r)   = mean(std(logi.z_cell_vec(:, 2:end), 1, 1), 'omitnan') * 100;  % population std (divisor N), per manuscript
        sw = logi.solver_time(active);
        sw = sw(isfinite(sw)) * 1e3;   % ms, finite only
        p95solve(r) = prctile(sw, 95);
        medsolve(r) = median(sw);
        optrate(r)  = mean(logi.optimality_proven(active), 'omitnan') * 100;
    end
    Summary.(vid).tracking_mean = mean(tracking);  Summary.(vid).tracking_std = std(tracking);
    Summary.(vid).socstd_mean   = mean(socstd);    Summary.(vid).socstd_std   = std(socstd);
    Summary.(vid).p95solve_mean = mean(p95solve);  Summary.(vid).p95solve_std = std(p95solve);
    Summary.(vid).medsolve_mean = mean(medsolve);  Summary.(vid).medsolve_std = std(medsolve);
    Summary.(vid).optrate_mean  = mean(optrate);   Summary.(vid).optrate_std  = std(optrate);

    q = @(x, p) prctile(x, p);
    Summary.(vid).tracking_median = median(tracking); Summary.(vid).tracking_q25 = q(tracking,25); Summary.(vid).tracking_q75 = q(tracking,75);
    Summary.(vid).socstd_median   = median(socstd);   Summary.(vid).socstd_q25   = q(socstd,25);   Summary.(vid).socstd_q75   = q(socstd,75);
    Summary.(vid).p95solve_median = median(p95solve); Summary.(vid).p95solve_q25 = q(p95solve,25); Summary.(vid).p95solve_q75 = q(p95solve,75);
    Summary.(vid).medsolve_median = median(medsolve); Summary.(vid).medsolve_q25 = q(medsolve,25); Summary.(vid).medsolve_q75 = q(medsolve,75);
    Summary.(vid).optrate_median  = median(optrate);  Summary.(vid).optrate_q25  = q(optrate,25);  Summary.(vid).optrate_q75  = q(optrate,75);
end


%% --- Save --------------------------------------------------------------
resultsDir = ensureResultsDir(rootDir);
out_name = fullfile(resultsDir, "Results_montecarlo_ics_" + ...
           string(datetime('now','Format','yyyyMMdd')) + ".mat");
save(out_name, 'Results', 'Summary', 'nRuns');
fprintf('Saved %s\n', out_name);
disp(Summary);
