% analyze_robustness_sweeps.m
%
% Unified post-processing script for Section VI-B of the manuscript
% ("Robustness Across Operating Conditions").
%
% Loads Results_robustness_sweeps_*.mat once and reproduces the manuscript
% tables for all three robustness sweeps, plus the summary statistics
% quoted in the introductory paragraph of Section VI-B:
%
%   VI-B.2  Heterogeneity sweep  (N=20, Np=10; 4 cases)
%   VI-B.3  Pack-size sweep      (WLTC_Med, Np=10; N = 16/20/24)
%   VI-B.4  Prediction-horizon sweep (WLTC_Med, N=20; Np = 4/6/8/10)
%   Summary  Mean A/D metrics and A->D reductions across the 4 het. cases
%
% All sections now report the same 8-column metric set:
%
%   MAE [%]  Curt. [%]  sigma_SOC [%]  efc_spr
%   t_50 [ms]  t_95 [ms]  eta_opt [%]  Fail [%]
%
% t_50 (median solver time) was present in VI-B.4 but not in VI-B.2 or
% VI-B.3 previously; it is now reported uniformly across all sections.
%
% Prerequisites
%   Run mainSimulationRunners/run_robustness_sweeps.m to produce
%   results/Results_robustness_sweeps_<date>.mat before running this script.
%
% Figure generation
%   Each sweep has a dedicated figure script in figureGeneration/:
%     (the per-sweep bar charts are not part of the manuscript)
%   These work standalone from any existing .mat file.

clc; close all;

thisFile    = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(projectRoot);
rootDir = initProjectPaths(thisFile);

%% -----------------------------------------------------------------------
%  Load latest robustness-sweep result file (once for all sections)
% ------------------------------------------------------------------------
latestFile = findLatestResultFile( ...
    fullfile(rootDir, 'results', 'Results_robustness_sweeps_*.mat'), ...
    'Run mainSimulationRunners/run_robustness_sweeps.m first.');
data = load(latestFile);
fprintf('Loaded %s\n', latestFile);
R = data.RobResults;

% Column header and format string shared by all sections
COL_HDR = '%-6s %-3s %10s %10s %13s %10s %10s %10s %10s %10s\n';
COL_FMT = '%-6s %-3s %10.3f %10.3f %10.3f %10.3f %10.1f %10.1f %10.1f %10.1f\n';
COL_SEP = repmat('-', 1, 100);
COL_LABELS = {'', '', 'MAE [%]', 'Curt. [%]', 'sigma_SOC [%]', ...
              'efc_spr', 't_50 [ms]', 't_95 [ms]', 'eta_opt [%]', 'Fail [%]'};

variants = {'A', 'D'};


%% -----------------------------------------------------------------------
%  VI-B.2  Heterogeneity sweep
% ------------------------------------------------------------------------
fprintf('\n%s\n', repmat('=', 1, 60));
fprintf('=== VI-B.2: Heterogeneity (N=20, Np=10, balanced) ===\n');
fprintf('%s\n\n', repmat('=', 1, 60));

het_cases = {'WLTC_Low', 'WLTC_Med', 'WLTC_High', 'HighPower'};

fprintf(COL_HDR, COL_LABELS{:});
fprintf('%s\n', COL_SEP);

for ci = 1:numel(het_cases)
    for vi = 1:numel(variants)
        key = sprintf('N20_Np10_%s_%s_balanced', het_cases{ci}, variants{vi});
        print_row(R, key, het_cases{ci}, variants{vi}, COL_FMT);
    end
    if ci < numel(het_cases)
        fprintf('%s\n', repmat('-', 1, 100));
    end
end

fprintf('%s\n', COL_SEP);
% (Supplementary heterogeneity bar chart is not part of the manuscript.)


%% -----------------------------------------------------------------------
%  VI-B.3  Pack-size sweep
% ------------------------------------------------------------------------
fprintf('\n%s\n', repmat('=', 1, 60));
fprintf('=== VI-B.3: Pack-Size Scaling (WLTC_Med, Np=10, balanced) ===\n');
fprintf('%s\n\n', repmat('=', 1, 60));
fprintf('  NOTE: N=20 entry is sourced from the heterogeneity sweep\n');
fprintf('  (Sweep 2 in run_robustness_sweeps.m skips the reference N=20).\n\n');

pack_sizes = [16, 20, 24];

fprintf(COL_HDR, COL_LABELS{:});
fprintf('%s\n', COL_SEP);

for ni = 1:numel(pack_sizes)
    N_str = sprintf('N=%d', pack_sizes(ni));
    for vi = 1:numel(variants)
        key = sprintf('N%d_Np10_WLTC_Med_%s_balanced', pack_sizes(ni), variants{vi});
        print_row(R, key, N_str, variants{vi}, COL_FMT);
    end
    if ni < numel(pack_sizes)
        fprintf('%s\n', repmat('-', 1, 100));
    end
end

fprintf('%s\n', COL_SEP);
% (Supplementary pack-size scaling chart is not part of the manuscript.)


%% -----------------------------------------------------------------------
%  VI-B.4  Prediction-horizon sweep
% ------------------------------------------------------------------------
fprintf('\n%s\n', repmat('=', 1, 60));
fprintf('=== VI-B.4: Prediction Horizon (WLTC_Med, N=20, balanced) ===\n');
fprintf('%s\n\n', repmat('=', 1, 60));
fprintf('  NOTE: Np=10 entry is sourced from the heterogeneity sweep\n');
fprintf('  (Sweep 3 in run_robustness_sweeps.m skips the reference Np=10).\n\n');

horizons = [4, 6, 8, 10];

fprintf(COL_HDR, COL_LABELS{:});
fprintf('%s\n', COL_SEP);

for hi = 1:numel(horizons)
    Np_str = sprintf('Np=%d', horizons(hi));
    for vi = 1:numel(variants)
        key = sprintf('N20_Np%d_WLTC_Med_%s_balanced', horizons(hi), variants{vi});
        print_row(R, key, Np_str, variants{vi}, COL_FMT);
    end
    if hi < numel(horizons)
        fprintf('%s\n', repmat('-', 1, 100));
    end
end

fprintf('%s\n', COL_SEP);
% (Supplementary horizon chart is not part of the manuscript.)


%% -----------------------------------------------------------------------
%  Summary: mean A/D metrics and A->D reductions across the 4 het. cases
%  (These are the numbers quoted in the introductory paragraph of VI-B.)
% ------------------------------------------------------------------------
fprintf('\n%s\n', repmat('=', 1, 60));
fprintf('=== VI-B Summary: Mean across 4 heterogeneity scenarios ===\n');
fprintf('%s\n\n', repmat('=', 1, 60));

metric_ids = {'tracking_mae', 'curt_frac', 'soc_std_mean', ...
              'efc_spread', 'med_solve_ms', 'p95_solve_ms', ...
              'opt_rate', 'fail_frac'};

% Accumulate per-variant metrics across the four het. cases
acc = struct();
for vi = 1:numel(variants)
    vid = variants{vi};
    for mi = 1:numel(metric_ids)
        acc.(vid).(metric_ids{mi}) = nan(1, numel(het_cases));
    end
    for ci = 1:numel(het_cases)
        key = sprintf('N20_Np10_%s_%s_balanced', het_cases{ci}, vid);
        if ~isfield(R, key)
            fprintf('  WARNING: missing key %s\n', key);
            continue;
        end
        m = extract_robustness_metrics(R.(key).log, R.(key).cfg);
        for mi = 1:numel(metric_ids)
            if isfield(m, metric_ids{mi})
                acc.(vid).(metric_ids{mi})(ci) = m.(metric_ids{mi});
            end
        end
    end
end

% Print per-variant means
fprintf('%-3s %14s %10s %12s %10s %11s %12s %12s %12s\n', ...
        'V', 'MAE [%]', 'Curt [%]', 'soc_std [%]', 'efc_spr', ...
        't_50 [ms]', 't_95 [ms]', 'eta_opt [%]', 'Fail [%]');
fprintf('%s\n', repmat('-', 1, 100));
for vi = 1:numel(variants)
    vid = variants{vi};
    mu  = @(mid) mean(acc.(vid).(mid), 'omitnan');
    fprintf('%-3s %14.4f %10.3f %12.4f %10.4g %11.1f %12.1f %12.2f %10.2f\n', vid, ...
        mu('tracking_mae'), mu('curt_frac'), mu('soc_std_mean'), ...
        mu('efc_spread'),   mu('med_solve_ms'), mu('p95_solve_ms'), mu('opt_rate'), mu('fail_frac'));
end

% Print A->D reductions
fprintf('\n--- A -> D reductions (mean-of-cases basis) ---\n');
mu_A = @(mid) mean(acc.A.(mid), 'omitnan');
mu_D = @(mid) mean(acc.D.(mid), 'omitnan');
pct  = @(mid) (1 - mu_D(mid) / mu_A(mid)) * 100;

fprintf('  MAE:          %6.1f%% reduction  (%.4f%% -> %.4f%%)\n', ...
    pct('tracking_mae'), mu_A('tracking_mae'), mu_D('tracking_mae'));
fprintf('  curt_frac:    %6.1f%% reduction  (%.3f%% -> %.3f%%)\n', ...
    pct('curt_frac'),    mu_A('curt_frac'),    mu_D('curt_frac'));
fprintf('  soc_std_mean: %6.1f%% reduction  (%.4f%% -> %.4f%%)\n', ...
    pct('soc_std_mean'), mu_A('soc_std_mean'), mu_D('soc_std_mean'));
fprintf('  efc_spread:   %6.1f%% reduction  (%.4g -> %.4g)\n', ...
    pct('efc_spread'),   mu_A('efc_spread'),   mu_D('efc_spread'));
fprintf('  t_50:         %6.1f%% reduction  (%.1f ms -> %.1f ms)\n', ...
    pct('med_solve_ms'), mu_A('med_solve_ms'), mu_D('med_solve_ms'));
fprintf('  t_95:        %6.1f%% reduction  (%.1f ms -> %.1f ms)\n', ...
    pct('p95_solve_ms'), mu_A('p95_solve_ms'), mu_D('p95_solve_ms'));
fprintf('  opt_rate:     %.2f%% -> %.2f%%  (absolute %+.2f pp)\n', ...
    mu_A('opt_rate'), mu_D('opt_rate'), mu_D('opt_rate') - mu_A('opt_rate'));
fprintf('  fail_frac:    %.2f%% -> %.2f%%  (absolute %+.2f pp)\n', ...
    mu_A('fail_frac'), mu_D('fail_frac'), mu_D('fail_frac') - mu_A('fail_frac'));


%% -----------------------------------------------------------------------
%  MANUSCRIPT TABLE VII (tab:robustness_sweeps): Robustness Results For
%  Heterogeneity, Demand, Pack-Size, and Prediction-Horizon Variations.
%
%  Reproduces manuscript Table VII exactly, reusing R / variants /
%  het_cases / pack_sizes / horizons already defined above in this
%  script and the shared extract_robustness_metrics helper -- no new
%  data loading, no duplicated key conventions.
% ------------------------------------------------------------------------
fprintf('--- TABLE robustness_sweeps (tab:robustness_sweeps): Robustness Results (Heterog./Demand, Pack Size, Horizon) ---\n');
fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:robustness_sweeps>>>\n');
SEP78 = repmat('=', 1, 78);
sep78 = repmat('-', 1, 78);
ctrlLabel = struct('A', 'Base', 'D', 'Prop');
fprintf('%s\n', SEP78);
fprintf('%-10s %-10s %-6s %10s %13s %18s %10s %11s\n', ...
    'Sweep', 'Cond.', 'Ctrl.', 'e_bar [%]', 'Phi_curt [%]', 'sigma_SOC_bar [%]', 't_95 [ms]', 'eta_opt [%]');
fprintf('%s\n', sep78);

fprintf('-- Heterog./demand --\n');
for ci = 1:numel(het_cases)
    for vi = 1:numel(variants)
        vid = variants{vi};
        key = sprintf('N20_Np10_%s_%s_balanced', het_cases{ci}, vid);
        if ~isfield(R, key)
            fprintf('%-10s %-10s %-6s  (missing key: %s)\n', 'Het/dem', het_cases{ci}, ctrlLabel.(vid), key);
            continue;
        end
        m = extract_robustness_metrics(R.(key).log, R.(key).cfg);
        fprintf('%-10s %-10s %-6s %10.3f %13.3f %18.3f %10.1f %11.1f\n', ...
            'Het/dem', het_cases{ci}, ctrlLabel.(vid), ...
            m.tracking_mae, m.curt_frac, m.soc_std_mean, m.p95_solve_ms, m.opt_rate);
    end
end
fprintf('%s\n', sep78);

fprintf('-- Pack size --\n');
for ni = 1:numel(pack_sizes)
    N_str = sprintf('N=%d', pack_sizes(ni));
    for vi = 1:numel(variants)
        vid = variants{vi};
        if pack_sizes(ni) == 20
            key = sprintf('N20_Np10_WLTC_Med_%s_balanced', vid);  % shared with heterogeneity sweep
        else
            key = sprintf('N%d_Np10_WLTC_Med_%s_balanced', pack_sizes(ni), vid);
        end
        if ~isfield(R, key)
            fprintf('%-10s %-10s %-6s  (missing key: %s)\n', 'Pack size', N_str, ctrlLabel.(vid), key);
            continue;
        end
        m = extract_robustness_metrics(R.(key).log, R.(key).cfg);
        fprintf('%-10s %-10s %-6s %10.3f %13.3f %18.3f %10.1f %11.1f\n', ...
            'Pack size', N_str, ctrlLabel.(vid), ...
            m.tracking_mae, m.curt_frac, m.soc_std_mean, m.p95_solve_ms, m.opt_rate);
    end
end
fprintf('%s\n', sep78);

fprintf('-- Horizon --\n');
for hi = 1:numel(horizons)
    Np_str = sprintf('Np=%d', horizons(hi));
    for vi = 1:numel(variants)
        vid = variants{vi};
        if horizons(hi) == 10
            key = sprintf('N20_Np10_WLTC_Med_%s_balanced', vid);  % shared with heterogeneity sweep
        else
            key = sprintf('N20_Np%d_WLTC_Med_%s_balanced', horizons(hi), vid);
        end
        if ~isfield(R, key)
            fprintf('%-10s %-10s %-6s  (missing key: %s)\n', 'Horizon', Np_str, ctrlLabel.(vid), key);
            continue;
        end
        m = extract_robustness_metrics(R.(key).log, R.(key).cfg);
        fprintf('%-10s %-10s %-6s %10.3f %13.3f %18.3f %10.1f %11.1f\n', ...
            'Horizon', Np_str, ctrlLabel.(vid), ...
            m.tracking_mae, m.curt_frac, m.soc_std_mean, m.p95_solve_ms, m.opt_rate);
    end
end
fprintf('%s\n', SEP78);
fprintf('<<<MANUSCRIPT_TABLE_END tab:robustness_sweeps>>>\n');
fprintf('\n');


fprintf('\n%s\n', repmat('=', 1, 60));
fprintf('=== Analysis complete (Section VI-B robustness sweeps) ===\n');
fprintf('%s\n', repmat('=', 1, 60));


%% -----------------------------------------------------------------------
%  Local helper
% ------------------------------------------------------------------------
function print_row(R, key, row_label, variant, fmt)
% PRINT_ROW  Look up key in R, extract metrics, print one table row.
% Prints a "missing key" warning row if the key is absent.
    if ~isfield(R, key)
        fprintf('  WARNING: missing key: %s\n', key);
        return;
    end
    m = extract_robustness_metrics(R.(key).log, R.(key).cfg);
    fprintf(fmt, row_label, variant, ...
        m.tracking_mae, m.curt_frac, m.soc_std_mean, m.efc_spread, ...
        m.med_solve_ms, m.p95_solve_ms, m.opt_rate, m.fail_frac);
end
