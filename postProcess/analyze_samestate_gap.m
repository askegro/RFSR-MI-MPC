% analyze_samestate_gap.m
%
% Produces the paired-step comparison table for Section VI-A.2
% ("Per-Step Approximation Quality").
%
% At every non-rest step k, run_samestate_proposed solved the SAME MI-MPC
% problem instance twice: D (1-s limit, monotone on) drives the plant, and
% A_ref (100-s limit, monotone off) is solved at the identical plant state
% x_k without being applied. This is the only table in the manuscript where
% both rows refer to the same optimisation problem.
%
% A_ref is the unrestricted formulation with a long time limit; it is
% essentially always optimal. D is the prefix-restricted formulation with
% the operational time limit. Since D's feasible set is a strict subset of
% A_ref's, J_D >= J_A_ref at every step; positive gaps measure the cost of
% the restriction, and near-zero gaps correspond to steps where the
% exactness condition of Proposition 3 holds.
%
% Matched mask (applied to both rows):
%   D certifies optimality  AND  A_ref certifies optimality
%   AND  D does not curtail  AND  A_ref does not curtail
%
% Required input data:
%   Results_samestate_proposed_YYYYMMDD.mat  (auto-selects latest)
%   Run mainSimulationRunners/run_samestate_proposed.m first.
%
% Produces:
%   TABLE performance_paired  — D vs A_ref, objective components
%   Gap distribution          — per-step J_D - J_A_ref statistics

clc; close all;
thisFile    = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(projectRoot);
rootDir = initProjectPaths(thisFile);

try

fprintf('=== ANALYZE VI-A.2: Paired Comparison (D vs A_ref at same state) ===\n\n');

%% -------------------------------------------------------------------------
%  Load data
%% -------------------------------------------------------------------------
latestFile = findLatestResultFile( ...
    fullfile(rootDir, 'results', 'Results_samestate_proposed_*.mat'), ...
    'Run mainSimulationRunners/run_samestate_proposed.m first.');

data = load(latestFile);
fprintf('Loaded: %s\n\n', latestFile);

SEP  = repmat('=', 1, 66);
sep  = repmat('-', 1, 66);

L = data.Results.D.log;
C = metricsConfig();

requiredFields = { ...
    'rest_skip', 'optimality_proven', 'ref_optimality_proven', ...
    'slack_mag', 'ref_slack_mag', ...
    'J_obj', 'ref_J_obj', ...
    'J_SOH_weighted', 'ref_J_SOH_weighted', ...
    'J_SOC_weighted', 'ref_J_SOC_weighted', ...
    'J_curt_weighted', 'ref_J_curt_weighted', ...
    'S', 'ref_S', 'n_engaged', 'ref_n_engaged', ...
    'SOH_cell_vec', 'z_cell_vec'};
assert_has_fields(L, requiredFields, 'L');

%% ------------------------------------------------------------------------
% Build matched mask
%% ------------------------------------------------------------------------
active       = ~logical(L.rest_skip(:));
D_opt        =  logical(L.optimality_proven(:))     & active;
Aref_opt     =  logical(L.ref_optimality_proven(:)) & active;
D_no_curt    = ~(L.slack_mag(:)     > C.CURTAILMENT_THRESHOLD_A) & active;
Aref_no_curt = ~(L.ref_slack_mag(:) > C.CURTAILMENT_THRESHOLD_A) & active;

matched  = D_opt & Aref_opt & D_no_curt & Aref_no_curt;
nLog     = numel(matched);
idxMatch = find(matched);
n_active = sum(active);
n_match  = sum(matched);

% Manuscript correspondence (Section VI-A.2, eq:KpairDef):
%   active  -> K_act (this trajectory);  n_active -> |K_act|
%   matched -> K_pair (jointly certified-optimal AND uncurtailed, D and A_ref)
%   n_match -> |K_pair|
% Aliases kept for readability where the manuscript symbol is referenced below.
K_pair   = matched;  %#ok<NASGU>
n_K_pair = n_match;  %#ok<NASGU>

fprintf('Mask breakdown (of %d active steps):\n', n_active);
fprintf('  D optimal                          : %4d  (%5.1f%%)\n', sum(D_opt),        100*sum(D_opt)/n_active);
fprintf('  A_ref optimal (100-s limit)        : %4d  (%5.1f%%)\n', sum(Aref_opt),     100*sum(Aref_opt)/n_active);
fprintf('  D no curtailment                   : %4d  (%5.1f%%)\n', sum(D_no_curt),    100*sum(D_no_curt)/n_active);
fprintf('  A_ref no curtailment               : %4d  (%5.1f%%)\n', sum(Aref_no_curt), 100*sum(Aref_no_curt)/n_active);
fprintf('  Matched (all four)                 : %4d  (%5.1f%%)\n\n', n_match, 100*n_match/n_active);
fprintf('\n');
fprintf('\n');

if n_match == 0
    error('No matched steps. Cannot reproduce subsection statistics.');
end

%% ------------------------------------------------------------------------
% Table 1: weighted objective components
%% ------------------------------------------------------------------------
J_obj_D     = mean(vec(L.J_obj, 'J_obj', nLog, idxMatch),               'omitnan');
J_SOH_w_D   = mean(vec(L.J_SOH_weighted, 'J_SOH_weighted', nLog, idxMatch),      'omitnan');
J_SOC_w_D   = mean(vec(L.J_SOC_weighted, 'J_SOC_weighted', nLog, idxMatch),      'omitnan');
J_curt_w_D  = mean(vec(L.J_curt_weighted, 'J_curt_weighted', nLog, idxMatch),     'omitnan');

J_obj_Ar    = mean(vec(L.ref_J_obj, 'ref_J_obj', nLog, idxMatch),            'omitnan');
J_SOH_w_Ar  = mean(vec(L.ref_J_SOH_weighted, 'ref_J_SOH_weighted', nLog, idxMatch),  'omitnan');
J_SOC_w_Ar  = mean(vec(L.ref_J_SOC_weighted, 'ref_J_SOC_weighted', nLog, idxMatch),  'omitnan');
J_curt_w_Ar = mean(vec(L.ref_J_curt_weighted, 'ref_J_curt_weighted', nLog, idxMatch), 'omitnan');

fprintf('--- TABLE: Weighted objective components on matched steps (n = %d) ---\n', n_match);
fprintf('%s\n', SEP);
fprintf('%-16s %10s %10s %10s %10s\n', 'Controller', 'J_obj', 'J_SOH_w', 'J_SOC_w', 'J_curt_w');
fprintf('%s\n', sep);
fprintf('%-16s %10.4f %10.4f %10.4f %10.4f\n', 'D',       J_obj_D,  J_SOH_w_D,  J_SOC_w_D,  J_curt_w_D);
fprintf('%-16s %10.4f %10.4f %10.4f %10.4f\n', 'A_ref',   J_obj_Ar, J_SOH_w_Ar, J_SOC_w_Ar, J_curt_w_Ar);
fprintf('%s\n', sep);
fprintf('%-16s %10.4f %10.4f %10.4f %10.4f\n', 'D - A_ref', ...
    J_obj_D - J_obj_Ar, J_SOH_w_D - J_SOH_w_Ar, ...
    J_SOC_w_D - J_SOC_w_Ar, J_curt_w_D - J_curt_w_Ar);
fprintf('%s\n', SEP);
fprintf('\n');
fprintf('\n');


%% ------------------------------------------------------------------------
% Table 2: absolute and relative restriction-gap distribution
%% ------------------------------------------------------------------------
J_D_vec  = vec(L.J_obj, 'J_obj', nLog, idxMatch);
J_Ar_vec = vec(L.ref_J_obj, 'ref_J_obj', nLog, idxMatch);

gap_abs = J_D_vec - J_Ar_vec;
gap_rel = 100 * gap_abs ./ J_Ar_vec;

finiteGap      = isfinite(gap_abs) & isfinite(gap_rel);
idxMatchFinite = idxMatch(finiteGap);
gap_abs = gap_abs(finiteGap);
gap_rel = gap_rel(finiteGap);

MIP_TOL = 1e-4;  % Gurobi MIPGap setting (see buildSolverOptions.m)

fprintf('--- TABLE: Per-step restriction gap g(k) = J_D - J_A_ref (n = %d) ---\n', numel(gap_abs));
fprintf('%s\n', SEP);
fprintf('%-36s %10s %10s %10s %10s %10s\n', 'Quantity', 'Mean', 'Median', '95th pct.', 'Max.', 'Min.');
fprintf('%s\n', sep);
fprintf('%-36s %10.5f %10.5f %10.5f %10.5f %10.2e\n', ...
    'g_abs(k)', mean(gap_abs), median(gap_abs), prctile(gap_abs,95), max(gap_abs), min(gap_abs));
fprintf('%-36s %10.3f %10.3f %10.3f %10.3f %10.2e\n\n', ...
    'g_rel(k) [%]', mean(gap_rel), median(gap_rel), prctile(gap_rel,95), max(gap_rel), min(gap_rel));

%% ------------------------------------------------------------------------
% Negative-gap audit: are all n^- gaps within MIP certification tolerance?
%
% D's feasible set is a strict subset of A_ref's, so J_D >= J_A_ref exactly.
% Any reported gap < 0 is a solver artefact. Gurobi certifies optimality when
%   (ObjVal - ObjBound) / |ObjVal| <= MIPGap
% so the reported incumbent can sit above the true optimum by up to
%   MIPGap * |ObjVal|.
% For a reported gap to be spuriously negative, A_ref's incumbent only needs
% to be inflated by |g(k)|. The relevant (single-sided) tolerance bound is:
%   |g(k)| <= MIP_TOL * |J_Ar(k)|
% If this holds for every negative step, the explanation is complete.
%% ------------------------------------------------------------------------
neg_mask = gap_abs < 0;
n_neg    = sum(neg_mask);
idxNeg   = idxMatchFinite(neg_mask);

fprintf('Gap < 0 (n^- reported in table/manuscript): %d steps (%.1f%%)\n', ...
    n_neg, 100*n_neg/numel(gap_abs));
fprintf('Gap > 0 (genuine restriction cost)        : %d steps (%.1f%%)\n', ...
    sum(gap_abs > 0), 100*mean(gap_abs > 0));
fprintf('Gap = 0 exactly                           : %d steps (%.1f%%)\n\n', ...
    sum(gap_abs == 0), 100*mean(gap_abs == 0));

if n_neg > 0
    J_Ar_neg      = J_Ar_vec(neg_mask(finiteGap));
    abs_neg       = abs(gap_abs(neg_mask));
    mip_bound     = MIP_TOL * abs(J_Ar_neg(:));
    all_within    = all(abs_neg(:) <= mip_bound);
    fprintf('MIP tolerance check (|g| <= %.0e * |J_Ar|):\n', MIP_TOL);
    fprintf('  Tightest bound (min J_Ar * MIP_TOL): %.2e\n', min(mip_bound));
    fprintf('  Max |negative gap|                  : %.2e\n', max(abs_neg));
    fprintf('  All %d negative gaps within bound   : %s\n', ...
        n_neg, mat2str(all_within));
end
fprintf('%s\n', SEP);
fprintf('\n');
fprintf('\n');

% if isfield(L, 'mip_gap') && isfield(L, 'ref_mip_gap') && n_neg > 0
%     mip_D_all   = L.mip_gap(:);
%     mip_Ar_all  = L.ref_mip_gap(:);
%     mip_D_neg   = mip_D_all(idxNeg);
%     mip_Ar_neg  = mip_Ar_all(idxNeg);
%     fprintf('Actual logged MIP residuals at negative-gap steps:\n');
%     fprintf('  D    : mean = %.2e,  max = %.2e\n', mean(mip_D_neg,'omitnan'), max(mip_D_neg));
%     fprintf('  A_ref: mean = %.2e,  max = %.2e\n\n', mean(mip_Ar_neg,'omitnan'), max(mip_Ar_neg));
% else
%     fprintf('  (mip_gap fields not available or no negative-gap steps)\n\n');
% end

%% ------------------------------------------------------------------------
% Component contribution to the mean gap
%% ------------------------------------------------------------------------
gap_SOH_w  = vec(L.J_SOH_weighted, 'J_SOH_weighted', nLog, idxMatch)  - vec(L.ref_J_SOH_weighted, 'ref_J_SOH_weighted', nLog, idxMatch);
gap_SOC_w  = vec(L.J_SOC_weighted, 'J_SOC_weighted', nLog, idxMatch)  - vec(L.ref_J_SOC_weighted, 'ref_J_SOC_weighted', nLog, idxMatch);
gap_curt_w = vec(L.J_curt_weighted, 'J_curt_weighted', nLog, idxMatch) - vec(L.ref_J_curt_weighted, 'ref_J_curt_weighted', nLog, idxMatch);

mean_gap_abs = mean(gap_abs, 'omitnan');
mean_gap_SOH = mean(gap_SOH_w, 'omitnan');
mean_gap_SOC = mean(gap_SOC_w, 'omitnan');
mean_gap_cur = mean(gap_curt_w,'omitnan');

% fprintf('--- Component contribution to mean restriction gap ---\n');
% fprintf('  Mean total gap        : %+0.8f\n', mean_gap_abs);
% fprintf('  Mean SOH-weighted gap : %+0.8f  (%6.2f%% of total)\n', mean_gap_SOH, 100*mean_gap_SOH/mean_gap_abs);
% fprintf('  Mean SOC-weighted gap : %+0.8f  (%6.2f%% of total)\n', mean_gap_SOC, 100*mean_gap_SOC/mean_gap_abs);
% fprintf('  Mean curtailment gap  : %+0.8f  (%6.2f%% of total)\n\n', mean_gap_cur, 100*mean_gap_cur/mean_gap_abs);

%% ------------------------------------------------------------------------
% Selection/cardinality diagnostics
%% ------------------------------------------------------------------------

%% ------------------------------------------------------------------------
% MANUSCRIPT TABLE IV (tab:same_state_summary): Same-State Approximation
% Cost on Jointly Certified, Uncurtailed Steps K_pair (Section VI-A.2).
%
% Column 1 ("Proposed-controller trajectory", D vs A_ref) reuses K_pair /
% n_match / gap_rel / mean_gap_* computed above in this script. Column 2
% ("Rule-based-driver trajectory", D_ref vs A_ref) is loaded and computed
% here from Results_samestate_rulebased_*.mat, mirroring the
% mask/gap logic for the rule-based-driver trajectory is inlined below, so
% this single script produces both columns of manuscript Table IV.
%% ------------------------------------------------------------------------
haveSecondTrajectory = true;
try
    fileN = findLatestResultFile( ...
        fullfile(rootDir, 'results', 'Results_samestate_rulebased_*.mat'), ...
        'Run mainSimulationRunners/run_samestate_rulebased.m first.');
    dataN = load(fileN);
    LN    = dataN.Results.log;
    cfgN  = dataN.Results.cfg;

    active_N       = ~logical(LN.rest_skip);
    Aref_opt_N     =  logical(LN.ref_A_optimality_proven) & active_N;
    Dref_opt_N     =  logical(LN.ref_D_optimality_proven) & active_N;
    Aref_usable_N  = logical(LN.ref_A_solution_usable) & active_N;
    Dref_usable_N  = logical(LN.ref_D_solution_usable) & active_N;
    Aref_no_curt_N = ~(LN.ref_A_slack_mag > C.CURTAILMENT_THRESHOLD_A) & Aref_usable_N;
    Dref_no_curt_N = ~(LN.ref_D_slack_mag > C.CURTAILMENT_THRESHOLD_A) & Dref_usable_N;

    K_pair_N   = Aref_opt_N & Dref_opt_N & Aref_no_curt_N & Dref_no_curt_N;  % manuscript K_pair
    n_active_N = sum(active_N);   % manuscript |K_act|
    n_pair_N   = sum(K_pair_N);   % manuscript |K_pair|

    JSOH_w_A_N = cfgN.w.SOH    * LN.ref_A_J_SOH(K_pair_N);
    JSOC_w_A_N = cfgN.w.SOC    * LN.ref_A_J_SOC(K_pair_N);
    Jlam_w_A_N = cfgN.w.lambda * LN.ref_A_J_curt(K_pair_N);
    JSOH_w_D_N = cfgN.w.SOH    * LN.ref_D_J_SOH(K_pair_N);
    JSOC_w_D_N = cfgN.w.SOC    * LN.ref_D_J_SOC(K_pair_N);
    Jlam_w_D_N = cfgN.w.lambda * LN.ref_D_J_curt(K_pair_N);

    dJ_obj_SS_N   = mean((JSOH_w_D_N+JSOC_w_D_N+Jlam_w_D_N) - (JSOH_w_A_N+JSOC_w_A_N+Jlam_w_A_N), 'omitnan');
    dJ_SOH_w_SS_N = mean(JSOH_w_D_N - JSOH_w_A_N, 'omitnan');
    dJ_SOC_w_SS_N = mean(JSOC_w_D_N - JSOC_w_A_N, 'omitnan');
    dJ_lam_w_SS_N = mean(Jlam_w_D_N - Jlam_w_A_N, 'omitnan');

    J_D_N = LN.ref_D_J_obj(K_pair_N);  J_A_N = LN.ref_A_J_obj(K_pair_N);
    gap_abs_N = J_D_N - J_A_N;
    finiteN   = isfinite(gap_abs_N) & isfinite(J_A_N) & abs(J_A_N) > 1e-12;
    g_rel_N   = 100 * gap_abs_N(finiteN) ./ J_A_N(finiteN);
catch ME
    haveSecondTrajectory = false;
    secondTrajectoryErr  = ME.message;
end

fprintf('--- TABLE same_state_summary (tab:same_state_summary): Same-State Approximation Cost on K_pair ---\n');
fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:same_state_summary>>>\n');
fprintf('%s\n', SEP);
fprintf('%-28s %22s %22s\n', 'Metric', 'Proposed-controller', 'Rule-based-driver');
fprintf('%-28s %22s %22s\n', '', 'trajectory', 'trajectory');
fprintf('%s\n', sep);
if haveSecondTrajectory
    fprintf('%-28s %18d/%-3d %18d/%-3d\n', '|K_pair| (of |K_act|)', n_match, n_active, n_pair_N, n_active_N);
    fprintf('%-28s %22.4f %22.4f\n', 'Delta J_obj^SS',     mean_gap_abs, dJ_obj_SS_N);
    fprintf('%-28s %+22.4f %+22.4f\n', 'Delta J_SOH,w^SS',  mean_gap_SOH, dJ_SOH_w_SS_N);
    fprintf('%-28s %+22.4f %+22.4f\n', 'Delta J_SOC,w^SS',  mean_gap_SOC, dJ_SOC_w_SS_N);
    fprintf('%-28s %22.4f %22.4f  (expect 0: K_pair excludes curtailed steps)\n', ...
        'Delta J_lambda,w^SS', mean_gap_cur, dJ_lam_w_SS_N);
    fprintf('%-28s %22.3f %22.3f\n', 'g_rel_bar [%]', mean(gap_rel,'omitnan'),   mean(g_rel_N,'omitnan'));
    fprintf('%-28s %22.3f %22.3f\n', 'g_rel_50 [%]',  median(gap_rel,'omitnan'), median(g_rel_N,'omitnan'));
    fprintf('%-28s %22.3f %22.3f\n', 'g_rel_95 [%]',  prctile(gap_rel,95),       prctile(g_rel_N,95));
    fprintf('%-28s %22.3f %22.3f\n', 'g_rel_max [%]', max(gap_rel),              max(g_rel_N));
else
    fprintf('%-28s %18d/%-3d %22s\n', '|K_pair| (of |K_act|)', n_match, n_active, 'N/A');
    fprintf('%-28s %22.4f %22s\n', 'Delta J_obj^SS',     mean_gap_abs, 'N/A');
    fprintf('%-28s %+22.4f %22s\n', 'Delta J_SOH,w^SS',  mean_gap_SOH, 'N/A');
    fprintf('%-28s %+22.4f %22s\n', 'Delta J_SOC,w^SS',  mean_gap_SOC, 'N/A');
    fprintf('%-28s %22.4f %22s\n', 'Delta J_lambda,w^SS', mean_gap_cur, 'N/A');
    fprintf('%-28s %22.3f %22s\n', 'g_rel_bar [%]', mean(gap_rel,'omitnan'),   'N/A');
    fprintf('%-28s %22.3f %22s\n', 'g_rel_50 [%]',  median(gap_rel,'omitnan'), 'N/A');
    fprintf('%-28s %22.3f %22s\n', 'g_rel_95 [%]',  prctile(gap_rel,95),       'N/A');
    fprintf('%-28s %22.3f %22s\n', 'g_rel_max [%]', max(gap_rel),              'N/A');
    fprintf('  (Rule-based-driver trajectory unavailable: %s)\n', secondTrajectoryErr);
end
fprintf('%s\n', SEP);
fprintf('<<<MANUSCRIPT_TABLE_END tab:same_state_summary>>>\n');
fprintf('\n');
fprintf('\n');
% Switch logs can be saved either as nSteps-by-nCells or nCells-by-nSteps,
% depending on MATLAB save/load conventions. Orient them explicitly before
% applying the time-index matched mask.
S_D  = orientStepByCell(L.S,     nLog, 'S');
S_Ar = orientStepByCell(L.ref_S, nLog, 'ref_S');

n_D_from_S  = sum(S_D,  2);
n_Ar_from_S = sum(S_Ar, 2);
card_diff   = n_D_from_S(idxMatch) - n_Ar_from_S(idxMatch);

% fprintf('--- Engaged-cardinality diagnostics on matched set ---\n');
% fprintf('  Mean n_engaged, D                  : %8.4f\n', mean(n_D_from_S(idxMatch), 'omitnan'));
% fprintf('  Mean n_engaged, A_ref              : %8.4f\n', mean(n_Ar_from_S(idxMatch), 'omitnan'));
% fprintf('  Steps with different cardinality   : %8d / %d\n', sum(abs(card_diff) > 1e-9), n_match);
% fprintf('  Max |n_D - n_A_ref|                : %8.4g\n\n', max(abs(card_diff)));

fprintf('  Cardinality distribution, matched steps:\n');
uniqueN = unique(n_D_from_S(idxMatch));
for ii = 1:numel(uniqueN)
    cnt = sum(n_D_from_S(idxMatch) == uniqueN(ii));
    fprintf('    %2.0f cells : %4d steps\n', uniqueN(ii), cnt);
end
fprintf('\n');

%% ------------------------------------------------------------------------
% Selected-cell SOH/SOC diagnostics
% Use the pre-control state at row k: SOH_cell_vec(k,:), z_cell_vec(k,:)
% for the control action S(k,:). The state logs have one extra row for the
% terminal post-step state; therefore only rows 1:nSteps are used here.
%% ------------------------------------------------------------------------
nSteps = size(S_D, 1);
SOH_pre = orientStateStepByCell(L.SOH_cell_vec, nSteps, 'SOH_cell_vec');
SOC_pre = orientStateStepByCell(L.z_cell_vec,   nSteps, 'z_cell_vec');

[SOH_D_stepMean,  SOH_D_pooled]  = selectedMean(SOH_pre, S_D,  idxMatch);
[SOH_Ar_stepMean, SOH_Ar_pooled] = selectedMean(SOH_pre, S_Ar, idxMatch);
[SOC_D_stepMean,  SOC_D_pooled]  = selectedMean(SOC_pre, S_D,  idxMatch);
[SOC_Ar_stepMean, SOC_Ar_pooled] = selectedMean(SOC_pre, S_Ar, idxMatch);
% 
% fprintf('--- Selected-cell state diagnostics on matched set ---\n');
% fprintf('  Values below are mean over per-step selected-cell means.\n');
% fprintf('%-24s %12s %12s %12s\n', 'Quantity', 'D', 'A_ref', 'D - A_ref');
% fprintf('%s\n', repmat('-', 1, 64));
% fprintf('%-24s %12.6f %12.6f %12.6f\n', 'Selected-cell SOH', SOH_D_stepMean, SOH_Ar_stepMean, SOH_D_stepMean - SOH_Ar_stepMean);
% fprintf('%-24s %12.6f %12.6f %12.6f\n\n', 'Selected-cell SOC', SOC_D_stepMean, SOC_Ar_stepMean, SOC_D_stepMean - SOC_Ar_stepMean);
% 
% fprintf('  Pooled selected-entry means, reported for cross-check:\n');
% fprintf('    SOH: D = %.6f, A_ref = %.6f, D - A_ref = %.6f\n', SOH_D_pooled, SOH_Ar_pooled, SOH_D_pooled - SOH_Ar_pooled);
% fprintf('    SOC: D = %.6f, A_ref = %.6f, D - A_ref = %.6f\n\n', SOC_D_pooled, SOC_Ar_pooled, SOC_D_pooled - SOC_Ar_pooled);

%% ------------------------------------------------------------------------
% Subset-overlap diagnostics
%% ------------------------------------------------------------------------
hamming = sum(abs(S_D(idxMatch,:) - S_Ar(idxMatch,:)), 2);
differentCells = hamming / 2;  % valid because cardinalities are identical

% fprintf('--- Subset-overlap diagnostics on matched set ---\n');
% fprintf('  Identical selected subset              : %6.2f%%  (%d / %d steps)\n', ...
%     100*mean(hamming == 0), sum(hamming == 0), n_match);
% fprintf('  Mean number of differing selected cells: %6.3f\n', mean(differentCells, 'omitnan'));
% fprintf('  Median differing selected cells        : %6.3f\n', median(differentCells, 'omitnan'));
% fprintf('  95th pct. differing selected cells     : %6.3f\n', prctile(differentCells, 95));
% fprintf('  Max differing selected cells           : %6.3f\n\n', max(differentCells));

%% ------------------------------------------------------------------------
% LaTeX tables (full environments)
%% ------------------------------------------------------------------------
%fprintf('--- LaTeX Table 1: Paired objective comparison ---\n\n');

dObj  = J_obj_D  - J_obj_Ar;
dSOH  = J_SOH_w_D  - J_SOH_w_Ar;
dSOC  = J_SOC_w_D  - J_SOC_w_Ar;
dCurt = J_curt_w_D - J_curt_w_Ar;


% % Supplementary gap diagnostics (not in LaTeX table, retained for diagnosis)
% fprintf('Supplementary gap diagnostics:\n');
% fprintf('  Min g_abs = %s,  n_neg = %d  (%.1f%% of matched set)\n', ...
%     fmtSciTight(min(gap_abs)), n_neg, 100*n_neg/n_fin);
% if ~isnan(mean_mip_D)
%     fprintf('  MIP residuals at negative-gap steps -- D: mean=%s max=%s;  A_ref: mean=%s max=%s\n\n', ...
%         fmtSciMIP(mean_mip_D), fmtSciMIP(max_mip_D), fmtSciMIP(mean_mip_Ar), fmtSciMIP(max_mip_Ar));
% else
%     fprintf('  (mip_gap fields unavailable)\n\n');
% end

% %% Block-bootstrap CI for mean same-state restriction gap
% B = C.BOOTSTRAP_REPS;
% ciLevel = C.BOOTSTRAP_CI_LEVEL;
% blockLen = C.BLOCK_BOOTSTRAP_LEN;
% 
% [ci_gap_abs, ~] = block_bootstrap_mean_ci(gap_abs, B, ciLevel, blockLen, 20260601);
% [ci_gap_rel, ~] = block_bootstrap_mean_ci(gap_rel, B, ciLevel, blockLen, 20260602);
% 
% fprintf('Block-bootstrap CI for mean restriction gap:\n');
% fprintf('  B = %d, CI level = %.1f%%, block length = %d steps\n', B, ciLevel, blockLen);
% fprintf('  mean g(k)              = %+0.8f, CI [%+0.8f, %+0.8f]\n', ...
%     mean(gap_abs,'omitnan'), ci_gap_abs(1), ci_gap_abs(2));
% fprintf('  mean 100g/J_A_ref [%%]  = %+0.6f, CI [%+0.6f, %+0.6f]\n\n', ...
%     mean(gap_rel,'omitnan'), ci_gap_rel(1), ci_gap_rel(2));

% Prepare quantities for Table 3
n_diff_card    = sum(abs(card_diff) > 1e-9);
pct_identical  = 100 * mean(hamming == 0);
mean_eng_D     = mean(n_D_from_S(idxMatch), 'omitnan');
mean_eng_Ar    = mean(n_Ar_from_S(idxMatch),'omitnan');
mean_eng_diff  = mean_eng_D - mean_eng_Ar;
dSOH_sel       = SOH_D_stepMean - SOH_Ar_stepMean;
dSOC_sel       = SOC_D_stepMean - SOC_Ar_stepMean;

% Hamming-distance statistics (= differentCells = hamming/2 for equal-card steps)
hd_mean   = mean(differentCells, 'omitnan');
hd_median = median(differentCells, 'omitnan');
hd_p95    = prctile(differentCells, 95);

%% ------------------------------------------------------------------------
% MATLAB-formatted selection diagnostics table
% (selection diagnostics; not a manuscript table)
%% ------------------------------------------------------------------------
fprintf('\n--- TABLE: First-control-move selection diagnostics on K_D^pair ---\n');
fprintf('%s\n', SEP);
fprintf('%-34s %9s %9s %12s\n', 'Quantity', 'D', 'A_ref', 'D - A_ref');
fprintf('%s\n', sep);
fprintf('%-34s %9.3f %9.3f %+12.3f\n', 'Mean engaged cells', ...
    mean_eng_D, mean_eng_Ar, mean_eng_diff);
fprintf('%-34s %9.4f %9.4f %+12.4f\n', 'Selected-cell SOH', ...
    SOH_D_stepMean, SOH_Ar_stepMean, dSOH_sel);
fprintf('%-34s %9.4f %9.4f %+12.4f\n', 'Selected-cell SOC', ...
    SOC_D_stepMean, SOC_Ar_stepMean, dSOC_sel);
fprintf('%s\n', sep);
fprintf('%-34s %s\n', 'Different-cardinality steps', ...
    sprintf('%d/%d  (--)', n_diff_card, n_match));
fprintf('%-34s %s\n', 'Identical-subset steps [%]', ...
    sprintf('%.1f  (--)', pct_identical));
fprintf('%s\n', sep);
fprintf('%-34s\n', 'Differing cells between first-step engagement vectors');
fprintf('%s\n', sep);
fprintf('%-34s %9.2f  (--)\n', 'Mean',     hd_mean);
fprintf('%-34s %9.0f  (--)\n', 'Median',   hd_median);
fprintf('%-34s %9.0f  (--)\n', '95th pct.', hd_p95);
fprintf('%s\n\n', SEP);

fprintf('=== Analysis complete (VI-A.2 paired comparison) ===\n');

catch ME
    fprintf(2, '\nERROR while running %s:\n%s\n', mfilename, ...
        getReport(ME, 'extended', 'hyperlinks', 'off'));
    rethrow(ME);
end

%% ------------------------------------------------------------------------
% Local helpers
%% ------------------------------------------------------------------------


%% ------------------------------------------------------------------------
% Original local helpers
%% ------------------------------------------------------------------------

function s = fmtDiff4(val)
    % Format a difference value with 4 decimal places.
    % Negative values get a $-$ prefix so the minus sign renders in text mode.
    if val < 0
        s = sprintf('$-$%.4f', abs(val));
    else
        s = sprintf('%.4f', val);
    end
end

function s = fmtSciTight(val)
    % Format val as LaTeX scientific notation with tight spacing around \times.
    % Used for min-column values that may be negative.
    % Example: -5.68e-4 -> '$-5.68\!\times\!10^{-4}$'
    absval = abs(val);
    ex   = floor(log10(absval));
    mant = absval / 10^ex;
    if val < 0
        s = sprintf('$-%.2f\\!\\times\\!10^{%d}$', mant, ex);
    else
        s = sprintf('$%.2f\\!\\times\\!10^{%d}$', mant, ex);
    end
end

function s = fmtSciMIP(val)
    % Format a MIP-residual value as LaTeX scientific notation (2 sig figs).
    % Example: 2.9e-5 -> '$2.9\times10^{-5}$'
    absval = abs(val);
    ex   = floor(log10(absval));
    mant = absval / 10^ex;
    s = sprintf('$%.1f\\times10^{%d}$', mant, ex);
end

function y = vec(x, fieldName, nExpected, idx)
    % Return x(idx) after checking that x is a per-step vector.
    yAll = x(:);
    if numel(yAll) < nExpected
        error('Field %s has %d entries, but the matched mask has %d steps.', ...
              fieldName, numel(yAll), nExpected);
    end
    y = yAll(idx);
end

function Mtc = orientStepByCell(M, nSteps, fieldName)
    % Return an nSteps-by-nCells matrix, accepting either orientation.
    if size(M,1) == nSteps
        Mtc = M;
    elseif size(M,2) == nSteps
        Mtc = M.';
    else
        error(['Field %s must have one dimension equal to the number of logged ', ...
               'steps (%d). Actual size is %d-by-%d.'], ...
               fieldName, nSteps, size(M,1), size(M,2));
    end
end

function Xtc = orientStateStepByCell(X, nSteps, fieldName)
    % Return the first nSteps pre-control states as nSteps-by-nCells.
    % State logs normally have nSteps+1 rows/columns because they include
    % the terminal post-step state.
    if size(X,1) == nSteps
        Xtc = X;
    elseif size(X,1) == nSteps + 1
        Xtc = X(1:nSteps, :);
    elseif size(X,2) == nSteps
        Xtc = X.';
    elseif size(X,2) == nSteps + 1
        Xtc = X(:, 1:nSteps).';
    else
        error(['Field %s must have one dimension equal to nSteps or nSteps+1 ', ...
               '(%d or %d). Actual size is %d-by-%d.'], ...
               fieldName, nSteps, nSteps+1, size(X,1), size(X,2));
    end
end

function [stepMean, pooledMean] = selectedMean(X, S, idx)
    % X and S are nSteps-by-nCells. idx contains matched step indices.
    S_m = S(idx, :);
    X_m = X(idx, :);
    n_m = sum(S_m, 2);

    perStep = sum(S_m .* X_m, 2) ./ n_m;
    stepMean = mean(perStep, 'omitnan');

    pooledMean = sum(S_m(:) .* X_m(:), 'omitnan') / sum(S_m(:));
end
