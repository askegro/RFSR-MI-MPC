% analyze_montecarlo_ics.m
%
% Reproduces Section VI-B.1 of the manuscript ("Monte Carlo Robustness").
% Loads the latest Results_montecarlo_ics_*.mat (produced by
% lightweightWrappers/run_montecarlo_ics.m) and reports, for Variants
% A and D, per-realisation median [Q25, Q75] of:
%
%   tracking_mae    mean relative pack-power tracking error [%]
%   socstd          mean cross-sectional SOC standard deviation [%]
%   p95solve        95th-percentile solve time [ms]
%   optrate         proven-optimality rate [%]
%
% Median [Q25, Q75] is used instead of mean +/- std because the tracking
% error distribution across realisations is right-skewed (std > mean for
% Variant A), making mean +/- std misleading.
%
% Also prints the relative reduction (A vs D) on median values, paired
% bootstrap CIs for the mean D-A difference, and a sign test.

clc; close all;
thisFile    = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(projectRoot);
rootDir = initProjectPaths(thisFile);
fprintf('=== ANALYZE VI-B.1: Monte Carlo Robustness ===\n\n');

SEP = repmat('=', 1, 66);
sep = repmat('-', 1, 66);

%% Load
latestFile = findLatestResultFile( ...
    fullfile(rootDir, 'results', 'Results_montecarlo_ics_*.mat'), ...
    'Run mainSimulationRunners/run_montecarlo_ics.m first.');
data = load(latestFile);
fprintf('Loaded %s\n', latestFile);
fprintf('Realisations: %d\n\n', data.nRuns);

S = data.Summary;
v_ids = fieldnames(S);

%% TABLE: Per-variant median [Q25, Q75] over realisations
fprintf('--- TABLE mc_summary: Per-variant median [Q25, Q75] over %d realisations ---\n', data.nRuns);
fprintf('%s\n', SEP);
fprintf('%-3s  %-22s %-22s %-22s %-22s\n', 'V', ...
    'Tracking MAE [%]', 'sigma_SOC [%]', 't_p95 [ms]', 'eta_opt [%]');
fprintf('%s\n', sep);

for vi = 1:numel(v_ids)
    vid = v_ids{vi};
    % Fall back to recomputing quartiles from raw data if the file predates
    % the quartile fields (i.e. was produced by an older run_montecarlo_ics).
    if isfield(S.(vid), 'tracking_median')
        tr_med = S.(vid).tracking_median; tr_q25 = S.(vid).tracking_q25; tr_q75 = S.(vid).tracking_q75;
        so_med = S.(vid).socstd_median;   so_q25 = S.(vid).socstd_q25;   so_q75 = S.(vid).socstd_q75;
        p9_med = S.(vid).p95solve_median; p9_q25 = S.(vid).p95solve_q25; p9_q75 = S.(vid).p95solve_q75;
        op_med = S.(vid).optrate_median;  op_q25 = S.(vid).optrate_q25;  op_q75 = S.(vid).optrate_q75;
    else
        warning('Quartile fields missing in Summary — recomputing from raw data.');
        tr = nan(data.nRuns,1); so = nan(data.nRuns,1);
        p9 = nan(data.nRuns,1); op = nan(data.nRuns,1);
        for r = 1:data.nRuns
            m = local_mc_metrics(data.Results.(vid)(r).sim.log);
            tr(r) = m.tracking; so(r) = m.socstd;
            p9(r) = m.p95solve; op(r) = m.optrate;
        end
        tr_med=median(tr); tr_q25=prctile(tr,25); tr_q75=prctile(tr,75);
        so_med=median(so); so_q25=prctile(so,25); so_q75=prctile(so,75);
        p9_med=median(p9); p9_q25=prctile(p9,25); p9_q75=prctile(p9,75);
        op_med=median(op); op_q25=prctile(op,25); op_q75=prctile(op,75);
    end
    fprintf('%-3s  %5.4f [%5.4f, %5.4f]  %5.4f [%5.4f, %5.4f]  %6.1f [%6.1f, %6.1f]  %6.2f [%6.2f, %6.2f]\n', ...
        vid, tr_med, tr_q25, tr_q75, so_med, so_q25, so_q75, ...
        p9_med, p9_q25, p9_q75, op_med, op_q25, op_q75);
end
fprintf('%s\n', SEP);
fprintf('\n');
fprintf('\n');

%% TABLE: Relative reduction A -> D on medians (if both present)
if isfield(S, 'A') && isfield(S, 'D') && isfield(S.A, 'tracking_median')
    fprintf('--- TABLE mc_reduction: A -> D relative reduction (median of realisations) ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-14s %12s %12s %16s\n', 'Metric', 'Median A', 'Median D', 'Reduction [%]');
    fprintf('%s\n', sep);
    pct = @(b, a) (1 - b/a) * 100;
    fprintf('%-14s %12.4f %12.4f %+16.1f\n', 'tracking [%]', ...
        S.A.tracking_median, S.D.tracking_median, ...
        pct(S.D.tracking_median, S.A.tracking_median));
    fprintf('%-14s %12.4f %12.4f %+16.1f\n', 'soc_std [%]', ...
        S.A.socstd_median, S.D.socstd_median, ...
        pct(S.D.socstd_median, S.A.socstd_median));
    fprintf('%-14s %12.1f %12.1f %+16.1f\n', 't_p95 [ms]', ...
        S.A.p95solve_median, S.D.p95solve_median, ...
        pct(S.D.p95solve_median, S.A.p95solve_median));
    fprintf('%-14s %12.2f %12.2f %+16.2f  (absolute change [pp])\n', 'eta_opt [%]', ...
        S.A.optrate_median, S.D.optrate_median, ...
        S.D.optrate_median - S.A.optrate_median);
    fprintf('%s\n', SEP);
    fprintf('\n');
end
fprintf('\n');

%% Bootstrap CIs for paired A-D differences across Monte Carlo realizations
if isfield(data.Results, 'A') && isfield(data.Results, 'D')
    C = metricsConfig();
    B = C.BOOTSTRAP_REPS;
    ciLevel = C.BOOTSTRAP_CI_LEVEL;

    tracking_A = nan(data.nRuns, 1);
    tracking_D = nan(data.nRuns, 1);
    socstd_A   = nan(data.nRuns, 1);
    socstd_D   = nan(data.nRuns, 1);
    p95_A      = nan(data.nRuns, 1);
    p95_D      = nan(data.nRuns, 1);
    opt_A      = nan(data.nRuns, 1);
    opt_D      = nan(data.nRuns, 1);

    for r = 1:data.nRuns
        mA = local_mc_metrics(data.Results.A(r).sim.log);
        mD = local_mc_metrics(data.Results.D(r).sim.log);

        tracking_A(r) = mA.tracking;
        tracking_D(r) = mD.tracking;
        socstd_A(r)   = mA.socstd;
        socstd_D(r)   = mD.socstd;
        p95_A(r)      = mA.p95solve;
        p95_D(r)      = mD.p95solve;
        opt_A(r)      = mA.optrate;
        opt_D(r)      = mD.optrate;
    end

    d_tracking = tracking_D - tracking_A;
    d_socstd   = socstd_D   - socstd_A;
    d_p95      = p95_D      - p95_A;
    d_opt      = opt_D      - opt_A;

    [ci_tracking, ~] = bootstrap_mean_ci(d_tracking, B, ciLevel, 20260528);
    [ci_socstd,   ~] = bootstrap_mean_ci(d_socstd,   B, ciLevel, 20260529);
    [ci_p95,      ~] = bootstrap_mean_ci(d_p95,      B, ciLevel, 20260530);
    [ci_opt,      ~] = bootstrap_mean_ci(d_opt,      B, ciLevel, 20260531);

    % --- TABLE mc_bootstrap (tab:mc_bootstrap) ---
    % A and D columns: medians across realisations.
    % Difference and CI columns: paired D-A bootstrap statistics (need not equal
    % the difference between displayed medians — see manuscript caption).
    fprintf('--- TABLE mc_bootstrap (tab:mc_bootstrap): Paired Monte Carlo Results Over %d Initial-Condition Realizations ---\n', data.nRuns);
    fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:mc_bootstrap>>>\n');
    fprintf('%s\n', SEP);
    fprintf('  Bootstrap: B = %d, CI level = %.1f%%\n', B, ciLevel);
    fprintf('  Baseline/Proposed: medians across realisations. Mean paired difference and CI: paired D-A bootstrap.\n');
    fprintf('%-20s %10s %10s %14s  %s\n', 'Metric', 'Baseline', 'Proposed', 'Mean pair. diff.', '95% bootstrap CI');
    fprintf('%s\n', sep);
    fprintf('%-20s %10.3f %10.3f %+14.3f  [%+.3f, %+.3f]\n', 'e_bar [%]', ...
        median(tracking_A,'omitnan'), median(tracking_D,'omitnan'), ...
        mean(d_tracking,'omitnan'), ci_tracking(1), ci_tracking(2));
    fprintf('%-20s %10.3f %10.3f %+14.3f  [%+.3f, %+.3f]\n', 'sigma_SOC_bar [%]', ...
        median(socstd_A,'omitnan'), median(socstd_D,'omitnan'), ...
        mean(d_socstd,'omitnan'), ci_socstd(1), ci_socstd(2));
    fprintf('%-20s %10.1f %10.1f %+14.1f  [%+.1f, %+.1f]\n', 't_95 [ms]', ...
        median(p95_A,'omitnan'), median(p95_D,'omitnan'), ...
        mean(d_p95,'omitnan'), ci_p95(1), ci_p95(2));
    fprintf('%-20s %10.1f %10.1f %+14.1f  [%+.1f, %+.1f]\n', 'eta_opt [%]', ...
        median(opt_A,'omitnan'), median(opt_D,'omitnan'), ...
        mean(d_opt,'omitnan'), ci_opt(1), ci_opt(2));
    fprintf('%s\n', SEP);
    fprintf('<<<MANUSCRIPT_TABLE_END tab:mc_bootstrap>>>\n');
    fprintf('\n');
    fprintf('\n');

    % --- IN-TEXT BLOCK sec:VI-B1 -----------------------------------------
    % Supports the Section VI-B.1 sentence: "The 95% bootstrap confidence
    % intervals for all reported paired differences exclude zero". Checked
    % here, where the intervals are already in scope, rather than recomputed
    % elsewhere with a different seed.
    fprintf('<<<MANUSCRIPT_TABLE_BEGIN sec:VI-B1-ci>>>\n');
    fprintf('Section VI-B.1 -- do the 95%% bootstrap CIs exclude zero?\n');
    fprintf('%s\n', repmat('=', 1, 78));
    fprintf('    %-22s %14s %26s %10s\n', 'Metric', 'Mean D-A', '95% bootstrap CI', 'Excl. 0');
    fprintf('    %s\n', repmat('-', 1, 74));
    mcCI = { ...
        'e_bar [%]',          mean(d_tracking,'omitnan'), ci_tracking, '%+14.3f   [%+10.3f, %+10.3f]'; ...
        'sigma_SOC_bar [%]',  mean(d_socstd,  'omitnan'), ci_socstd,   '%+14.3f   [%+10.3f, %+10.3f]'; ...
        't_95 [ms]',          mean(d_p95,     'omitnan'), ci_p95,      '%+14.1f   [%+10.1f, %+10.1f]'; ...
        'eta_opt [pp]',       mean(d_opt,     'omitnan'), ci_opt,      '%+14.3f   [%+10.3f, %+10.3f]'; ...
    };
    allExcl = true;
    for mi = 1:size(mcCI, 1)
        ciM  = mcCI{mi, 3};
        excl = (ciM(1) > 0 && ciM(2) > 0) || (ciM(1) < 0 && ciM(2) < 0);
        allExcl = allExcl && excl;
        if excl, exclStr = 'yes'; else, exclStr = 'NO'; end
        fprintf(['    %-22s ' mcCI{mi, 4} ' %10s\n'], ...
            mcCI{mi, 1}, mcCI{mi, 2}, ciM(1), ciM(2), exclStr);
    end
    fprintf('    %s\n', repmat('-', 1, 74));
    if allExcl, allStr = 'yes'; else, allStr = 'NO'; end
    fprintf('    %-58s %8s\n', 'All four CIs exclude zero', allStr);
    fprintf('    %-58s %8d\n', 'Realizations N_MC', data.nRuns);
    fprintf('    %-58s %8d\n', 'Bootstrap resamples B', B);
    fprintf('<<<MANUSCRIPT_TABLE_END sec:VI-B1-ci>>>\n');
    fprintf('\n');

    % --- TABLE mc_bootstrap_detailed: Full bootstrap CI table ---
    fprintf('--- TABLE mc_bootstrap_detailed: Paired bootstrap CIs across Monte Carlo realisations ---\n');
    fprintf('%s\n', SEP);
    fprintf('Bootstrap: B = %d, CI level = %.1f%%\n', B, ciLevel);
    fprintf('%-18s %12s %22s\n', 'Metric', 'Mean D-A', 'CI for mean D-A');
    fprintf('%s\n', sep);
    fprintf('%-18s %+12.5f  [%+.5f, %+.5f]\n', ...
        'tracking [%]',   mean(d_tracking,'omitnan'), ci_tracking(1), ci_tracking(2));
    fprintf('%-18s %+12.5f  [%+.5f, %+.5f]\n', ...
        'sigma_SOC [%]',  mean(d_socstd,'omitnan'),   ci_socstd(1),   ci_socstd(2));
    fprintf('%-18s %+12.2f  [%+.2f, %+.2f]\n', ...
        't_p95 [ms]',     mean(d_p95,'omitnan'),       ci_p95(1),       ci_p95(2));
    fprintf('%-18s %+12.3f  [%+.3f, %+.3f]\n', ...
        'eta_opt [pp]',   mean(d_opt,'omitnan'),        ci_opt(1),        ci_opt(2));
    fprintf('%s\n', SEP);
    fprintf('\n');
    fprintf('\n');

    % --- TABLE mc_sign_test: Sign test ---
    N = data.nRuns;
    fprintf('--- TABLE mc_sign_test: Sign test — D better than A in N/%d realisations ---\n', N);
    fprintf('%s\n', SEP);
    fprintf('%-20s %12s %12s\n', 'Metric', 'Direction', 'Count');
    fprintf('%s\n', sep);
    fprintf('%-20s %12s %12s\n', 'tracking  [%]', 'D < A', sprintf('%d/%d', sum(d_tracking < 0), N));
    fprintf('%-20s %12s %12s\n', 'sigma_SOC [%]', 'D < A', sprintf('%d/%d', sum(d_socstd   < 0), N));
    fprintf('%-20s %12s %12s\n', 't_p95     [ms]','D < A', sprintf('%d/%d', sum(d_p95      < 0), N));
    fprintf('%-20s %12s %12s\n', 'eta_opt   [pp]','D > A', sprintf('%d/%d', sum(d_opt      > 0), N));
    fprintf('%s\n', SEP);
    fprintf('\n');
end

fprintf('\n=== Analysis complete (Section VI-B.1) ===\n');


function m = local_mc_metrics(logi)
    active = ~isnan(logi.p_pack_req) & ~logical(logi.rest_skip);

    p_del = logi.p_pack_meas(active);
    p_req = logi.p_pack_req(active);
    e = abs(p_del - p_req) ./ max(abs(p_req), 1e-9);

    m.tracking = mean(e, 'omitnan') * 100;
    m.socstd   = mean(std(logi.z_cell_vec(:, 2:end), 1, 1), 'omitnan') * 100;

    sw = logi.solver_time(active);
    m.p95solve = prctile(sw(isfinite(sw)) * 1e3, 95);

    m.optrate = mean(logi.optimality_proven(active), 'omitnan') * 100;
end
