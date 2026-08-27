% postProcess/report_table_robustness_case_params.m
%
% Reproduces manuscript Table II (tab:robustness_case_params,
% "Initial-Dispersion Parameters for the Heterogeneity/Demand Sweep"),
% which appears in Section V-E (sweep design). The corresponding results
% are reported in Section VI-B.2.
%
% This table has no simulation-log source: it simply echoes the initial-
% dispersion parameters and demand type used to configure the four
% heterogeneity/demand scenarios in run_robustness_sweeps.m. Previously this
% table existed only implicitly, hardcoded inline as the `rob_cases`
% struct literal in run_robustness_sweeps.m (Sweep-dimensions section) and
% was never printed anywhere in manuscript form.
%
% IMPORTANT: the four rows below are a literal duplicate of the
% `rob_cases` struct in run_robustness_sweeps.m ("Heterogeneity /
% drive-cycle cases"). If that struct changes, this table must be
% updated to match — the two are not read from a common source.
%
% Manuscript symbol -> code source (run_robustness_sweeps.m, rob_cases):
%   sigma_SOC,0 [%]   100 * rob_cases(i).soc_std
%   sigma_SOH,0 [%]   100 * rob_cases(i).soh_std
%   Demand            rob_cases(i).dc_type / P_const

clc;
fprintf('=== REPORT TABLE II: Initial-Dispersion Parameters (tab:robustness_case_params) ===\n\n');

SEP = repmat('=', 1, 52);
sep = repmat('-', 1, 52);

% Must match rob_cases in run_robustness_sweeps.m (Sweep-dimensions section).
rob_cases = struct( ...
    'id',       {'WLTC Low',  'WLTC Med',  'WLTC High', 'High Power'}, ...
    'soc_std',  {0.0005,       0.001,       0.01,        0.001       }, ...
    'soh_std',  {0.005,        0.01,        0.015,       0.005       }, ...
    'demand',   {'WLTC',       'WLTC',      'WLTC',      '200 W const.'} ...
);

fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:robustness_case_params>>>\n');
fprintf('%s\n', SEP);
fprintf('%-12s %16s %16s %14s\n', 'Case', 'sigma_SOC,0 [%]', 'sigma_SOH,0 [%]', 'Demand');
fprintf('%s\n', sep);
for i = 1:numel(rob_cases)
    fprintf('%-12s %16.2f %16.1f %14s\n', rob_cases(i).id, ...
        100*rob_cases(i).soc_std, 100*rob_cases(i).soh_std, rob_cases(i).demand);
end
fprintf('%s\n', SEP);
fprintf('<<<MANUSCRIPT_TABLE_END tab:robustness_case_params>>>\n');

fprintf('\n=== Report complete (Table II) ===\n');
