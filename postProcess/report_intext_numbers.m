function report_intext_numbers()
% postProcess/report_intext_numbers.m
%
% Produces every number quoted in the RUNNING TEXT of Section VI (Results
% and Discussion), together with the Section V inputs those results are
% generated from, the headline numbers restated in the Conclusion, and the
% SOS2 numbers of the Appendix.
%
% Manuscript section numbering used throughout (derived from the order of
% \section{} in the LaTeX source):
%   I    Introduction
%   II   System Modeling and MI-MPC Formulation
%   III  Combinatorial Structure of Cell Engagement
%   IV   Ranking-Based Feasible-Set Restriction
%   V    Evaluation Methodology            <- Tables I (V-A) and II (V-E)
%   VI   Results and Discussion            <- Tables III-VII
%   VII  Conclusion
%   Appendix  Detailed Mixed-Integer Convex Reformulation
%
% Output blocks (harvested by REPRODUCE_ALL_RESULTS.m via sentinels):
%   sec:V       Evaluation-methodology inputs (drive cycle, sweep design)
%   sec:VI-A1   Solver Certification and Runtime
%   sec:VI-A2   Same-State Approximation Cost
%   sec:VI-A3   Closed-Loop Control Performance
%   sec:VI-B1   Sensitivity to Initial Conditions
%   sec:VI-B2   Sensitivity to Cell Heterogeneity and Demand Conditions
%   sec:VI-B3   Sensitivity to Pack Size
%   sec:VI-B4   Sensitivity to Prediction Horizon
%   sec:VII     Conclusion headline numbers
%   sec:APP     Appendix SOS2 numbers
%
% kappa_WLTC is not stored in the result .mat files -- it is scale_factor
% inside build/buildScaledDriveCycle.m. It is recovered by rebuilding the
% drive-cycle pipeline, which report_table_evaluation_protocol.m does, so it
% is printed with Table I rather than here.
%
% Prerequisites (produced by mainSimulationRunners/):
%   results/Results_nominal_wltc_*.mat
%   results/Results_samestate_proposed_*.mat
%   results/Results_samestate_rulebased_*.mat
%   results/Results_montecarlo_ics_*.mat
%   results/Results_robustness_sweeps_*.mat
% A missing prerequisite is reported as NOT AVAILABLE for the affected
% block; every block that CAN be produced still is.
%
% All mask and metric definitions mirror the corresponding analyze_*.m
% scripts exactly (get_masks, metricsConfig thresholds,
% computeCurtailmentMetric, extract_robustness_metrics), so the values
% printed here agree with Tables I-VII by construction.

    IN_thisFile    = mfilename('fullpath');
    IN_thisDir     = fileparts(IN_thisFile);
    IN_projectRoot = fileparts(IN_thisDir);
    addpath(IN_projectRoot);
    addpath(IN_thisDir);
    rootDir    = initProjectPaths(IN_thisFile);
    resultsDir = fullfile(rootDir, 'results');

    % Each block is run in isolation: a failure in one section must not
    % suppress the other nine. This is deliberate -- an earlier version
    % dispatched them directly and a single bad field name cost the whole
    % report.
    safe(@sec_V,     resultsDir, 'sec:V');
    safe(@sec_VI_A1, resultsDir, 'sec:VI-A1');
    safe(@sec_VI_A2, resultsDir, 'sec:VI-A2');
    safe(@sec_VI_A3, resultsDir, 'sec:VI-A3');
    safe(@sec_VI_B1, resultsDir, 'sec:VI-B1');
    safe(@sec_VI_B2, resultsDir, 'sec:VI-B2');
    safe(@sec_VI_B3, resultsDir, 'sec:VI-B3');
    safe(@sec_VI_B4, resultsDir, 'sec:VI-B4');
    safe(@sec_VII,   resultsDir, 'sec:VII');
    safe(@sec_APP,   resultsDir, 'sec:APP');
end

%% =======================================================================
%  SECTION V -- Evaluation Methodology (inputs)
%% =======================================================================
function sec_V(resultsDir)
    b = blk_open('sec:V', 'Section V -- Evaluation Methodology (inputs quoted in the text)');
    try
        f = find_latest(fullfile(resultsDir, 'Results_nominal_wltc_*.mat'));
        if isempty(f)
            na('run_nominal_wltc');
        else
            S   = load(f);
            cfg = S.cfg;
            L   = S.Results.D.log;
            act = ~L.rest_skip;
            p   = L.p_pack_req;
            src(f);
            rule('V-A  Nominal driving-cycle evaluation');
            kv_i('Active control steps |K_act| (nominal WLTC)', sum(act));
            kv_i('Total simulation steps',                      numel(act));
            kv_f('Sampling interval Delta t [s]',               cfg.Tstep, '%8.3f');
            kv_i('Cells in series N',                           cfg.Ns);
            kv_i('Prediction horizon N_p',                      local_getNp(cfg));
            kv_f('Maximum discharge request [W]',               max(p(act)),      '%8.3f');
            kv_f('Maximum discharge request [kW]',              max(p(act))/1e3,  '%8.3f');
            kv_f('Maximum regen-charge magnitude [W]',          abs(min(p(act))), '%8.3f');
            kv_f('Maximum regen-charge magnitude [kW]',         abs(min(p(act)))/1e3, '%8.3f');
        end

        fr = find_latest(fullfile(resultsDir, 'Results_robustness_sweeps_*.mat'));
        rule('V-E  Pack-size sweep: rescaled peak demand');
        if isempty(fr)
            na('run_robustness_sweeps');
        else
            Sr = load(fr);
            Rr = rob_struct(Sr);
            for N = [16 20 24]
                k = sprintf('N%d_Np10_WLTC_Med_D_balanced', N);
                if isfield(Rr, k)
                    Lr = Rr.(k).log;
                    kv_f(sprintf('N = %2d : peak discharge request [W]', N), ...
                         max(Lr.p_pack_req(~Lr.rest_skip)), '%8.1f');
                else
                    miss(k);
                end
            end
        end

        fm = find_latest(fullfile(resultsDir, 'Results_montecarlo_ics_*.mat'));
        rule('V-E  Monte Carlo design');
        if isempty(fm)
            na('run_montecarlo_ics');
        else
            Sm = load(fm);
            C  = metricsConfig();
            kv_i('Paired realizations N_MC',        Sm.nRuns);
            kv_i('Bootstrap resamples B',           C.BOOTSTRAP_REPS);
            kv_f('Bootstrap CI level [%]',          C.BOOTSTRAP_CI_LEVEL, '%8.1f');
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

%% =======================================================================
%  SECTION VI-A.1 -- Solver Certification and Runtime
%% =======================================================================
function sec_VI_A1(resultsDir)
    b = blk_open('sec:VI-A1', 'Section VI-A.1 -- Solver Certification and Runtime');
    try
        f = find_latest(fullfile(resultsDir, 'Results_nominal_wltc_*.mat'));
        if isempty(f), na('run_nominal_wltc'); blk_close(b); return; end
        S = load(f); src(f);
        R = S.Results; cfg = S.cfg;
        LA = R.A.log; LD = R.D.log;
        mA = masks(LA); mD = masks(LD);

        rule('Certification');
        etaA = 100*mA.n_opt/mA.n_act;  etaD = 100*mD.n_opt/mD.n_act;
        kv_f('Baseline eta_opt [%]',                         etaA, '%8.2f');
        kv_f('Proposed eta_opt [%]',                         etaD, '%8.2f');
        kv_f('Baseline NOT certified, share of K_act [%]',   100-etaA, '%8.2f');
        kv_i('Baseline TO+Inc. steps',                       mA.n_inc);
        kv_i('Baseline Fail steps',                          mA.n_hf);
        kv_i('Proposed Fail steps',                          mD.n_hf);
        kv_i('|K_act|',                                      mA.n_act);

        rule('Solver time over K_act');
        tA = 1e3*LA.solver_time(mA.active);  tD = 1e3*LD.solver_time(mD.active);
        kv3('Baseline', prctile(tA,50), prctile(tA,95), max(tA));
        kv3('Proposed', prctile(tD,50), prctile(tD,95), max(tD));
        kv_f('Speedup t_50  (Baseline/Proposed) [x]', prctile(tA,50)/prctile(tD,50), '%8.1f');
        kv_f('Speedup t_95  (Baseline/Proposed) [x]', prctile(tA,95)/prctile(tD,95), '%8.1f');
        kv_f('Speedup t_max (Baseline/Proposed) [x]', max(tA)/max(tD),               '%8.1f');

        rule('Branch-and-bound nodes over K_act');
        nA = LA.node_count(mA.active); nD = LD.node_count(mD.active);
        kv_f('Baseline root-node share [%]',  100*mean(nA<=1,'omitnan'), '%8.1f');
        kv_f('Proposed root-node share [%]',  100*mean(nD<=1,'omitnan'), '%8.1f');
        kv_i('Baseline n^node_95',            round(prctile(nA,95)));
        kv_i('Baseline n^node_max',           round(max(nA)));
        kv_i('Proposed n^node_max',           round(max(nD)));

        rule('Baseline timeout-incumbent quality');
        g = LA.mip_gap(mA.inc); g = g(isfinite(g));
        if isempty(g)
            note('No finite incumbent MIP gaps recorded.');
        else
            kv_i('TO+Inc. steps with a finite gap', numel(g));
            kv_f('Median incumbent MIP gap [%]',    100*median(g), '%8.3f');
            kv_f('Maximum incumbent MIP gap [%]',   100*max(g),    '%8.3f');
            kv_f('Share of gaps below 1% [%]',      100*mean(g<0.01), '%8.1f');
        end

        rule('Difficulty vs. requested power (baseline)');
        pab = abs(LA.p_pack_req);
        powrow('Optimal', pab(mA.opt));
        powrow('TO+Inc.', pab(mA.inc));
        powrow('Fail',    pab(mA.hf));

        rule('Persistence of non-certified baseline steps');
        bad = find(mA.inc | mA.hf);
        if numel(bad) > 1
            d  = diff(bad(:)); t = find(d>1);
            br = diff([0; t(:); numel(bad)]);
            kv_i('Total maximal non-certified bursts',     numel(br));
            kv_i('Bursts >= 5 consecutive active steps',   sum(br>=5));
            kv_i('Longest burst [active steps]',           max(br));
        else
            note('Fewer than 2 non-certified steps; burst analysis skipped.');
        end
        pa = LA.p_pack_req(mA.active); pa = pa(:);
        kv_f('Lag-1 autocorrelation of p_req',   corr(pa(1:end-1), pa(2:end)),           '%8.3f');
        kv_f('Lag-1 autocorrelation of |p_req|', corr(abs(pa(1:end-1)),abs(pa(2:end))),  '%8.3f');
        z  = LA.z_cell_vec; ai = find(mA.active);
        kv_f('Median max per-cell dSOC per step [pp]', ...
             median(max(abs(z(:,ai+1)-z(:,ai)),[],1))*100, '%8.4f');

        rule('Proposed-controller online cost');
        Tms = 1e3*local_getTstep(cfg);
        kv_f('Sampling period Delta t [ms]', Tms, '%8.0f');
        if isfield(LD,'t_prepare')
            v = 1e3*LD.t_prepare(mD.active & isfinite(LD.t_prepare));
            kv_f('Ranking + sort + parameter build, p95 [ms]', prctile(v,95), '%8.2f');
            kv_f('   as share of Delta t [%]',                 100*prctile(v,95)/Tms, '%8.3f');
            kv_f('Ranking + sort + parameter build, max [ms]', max(v), '%8.2f');
            kv_f('   as share of Delta t [%]',                 100*max(v)/Tms, '%8.3f');
        else
            note('t_prepare not logged in this result file.');
        end
        if isfield(LD,'t_ctrl_wall')
            w = 1e3*LD.t_ctrl_wall(mD.active & isfinite(LD.t_ctrl_wall));
            kv_f('Total control update, p95 [ms]', prctile(w,95), '%8.2f');
            kv_f('   as share of Delta t [%]',     100*prctile(w,95)/Tms, '%8.1f');
            kv_f('Total control update, max [ms]', max(w), '%8.2f');
            kv_f('   as share of Delta t [%]',     100*max(w)/Tms, '%8.1f');
        else
            note('t_ctrl_wall not logged in this result file.');
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

%% =======================================================================
%  SECTION VI-A.2 -- Same-State Approximation Cost
%% =======================================================================
function sec_VI_A2(resultsDir)
    b = blk_open('sec:VI-A2', 'Section VI-A.2 -- Same-State Approximation Cost');
    try
        C = metricsConfig();

        rule('Proposed-controller trajectory (D vs A_ref at the same pre-control state)');
        f1 = find_latest(fullfile(resultsDir, 'Results_samestate_proposed_*.mat'));
        if isempty(f1)
            na('run_samestate_proposed');
        else
            S = load(f1); src(f1);
            tol_pct = local_gap_tol_pct(S);
            L = S.Results.D.log;
            act  = ~logical(L.rest_skip(:));
            Dop  =  logical(L.optimality_proven(:))     & act;
            Aop  =  logical(L.ref_optimality_proven(:)) & act;
            Dnc  = ~(L.slack_mag(:)     > C.CURTAILMENT_THRESHOLD_A) & act;
            Anc  = ~(L.ref_slack_mag(:) > C.CURTAILMENT_THRESHOLD_A) & act;
            gapblock(act, Aop, Dop & Aop & Dnc & Anc, ...
                     L.J_obj(:), L.ref_J_obj(:), ...
                     L.J_curt_weighted(:), L.ref_J_curt_weighted(:), tol_pct);
        end

        rule('Rule-based-driver trajectory (D_ref vs A_ref at the same pre-control state)');
        f2 = find_latest(fullfile(resultsDir, 'Results_samestate_rulebased_*.mat'));
        if isempty(f2)
            na('run_samestate_rulebased');
        else
            S2 = load(f2); src(f2);
            tol_pct = local_gap_tol_pct(S2);
            LN = S2.Results.log;
            act = ~logical(LN.rest_skip(:));
            Aop =  logical(LN.ref_A_optimality_proven(:)) & act;
            Dop =  logical(LN.ref_D_optimality_proven(:)) & act;
            Aus =  logical(LN.ref_A_solution_usable(:))   & act;
            Dus =  logical(LN.ref_D_solution_usable(:))   & act;
            Anc = ~(LN.ref_A_slack_mag(:) > C.CURTAILMENT_THRESHOLD_A) & Aus;
            Dnc = ~(LN.ref_D_slack_mag(:) > C.CURTAILMENT_THRESHOLD_A) & Dus;
            cfgN = S2.Results.cfg;
            gapblock(act, Aop, Aop & Dop & Anc & Dnc, ...
                     LN.ref_D_J_obj(:), LN.ref_A_J_obj(:), ...
                     cfgN.w.lambda*LN.ref_D_J_curt(:), cfgN.w.lambda*LN.ref_A_J_curt(:), tol_pct);
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

function gapblock(act, full_opt, pair, J_pref, J_full, Jl_pref, Jl_full, tol_pct)
% GAPBLOCK  Restriction-gap statistics on the jointly certified states.
%
% tol_pct  Relative MIP-gap tolerance expressed in the units of g_rel [%],
%          i.e. 100*MIPGap. Both formulations are solved to this tolerance, so
%          each reported optimum may exceed its true optimum by up to
%          tol_pct of its magnitude. Set inclusion gives g_rel >= 0 in exact
%          arithmetic; observed negative values are therefore attributable to
%          the tolerance only while they stay within it. Negative gaps beyond
%          the tolerance would need a different explanation and are counted
%          separately below.
    n_act = sum(act); n_pair = sum(pair);
    kv_i('|K_act| (active states on this trajectory)', n_act);
    kv_i('|K_pair| (jointly certified and uncurtailed)', n_pair);
    kv_i('Full subset-selection reference solves NOT certified', n_act - sum(full_opt));
    note(sprintf('  (i.e. %d of the %d active states, even at the 100 s reference limit)', ...
        n_act - sum(full_opt), n_act));
    ga = J_pref(pair) - J_full(pair);
    Jf = J_full(pair);
    ok = isfinite(ga) & isfinite(Jf) & abs(Jf) > 1e-12;
    gr = 100 * ga(ok) ./ Jf(ok);
    kv_f('Mean   restriction gap g_rel_bar [%]', mean(gr,'omitnan'),   '%8.3f');
    kv_f('Median restriction gap g_rel_50  [%]', median(gr,'omitnan'), '%8.3f');
    kv_f('95th   restriction gap g_rel_95  [%]', prctile(gr,95),       '%8.3f');
    kv_f('Max    restriction gap g_rel_max [%]', max(gr),              '%8.3f');
    kv_i('Steps with g_rel exactly zero',        sum(gr == 0));
    kv_f('   as share of K_pair [%]',            100*mean(gr==0), '%8.1f');
    kv_i('Steps with g_rel > 0 (genuine restriction cost)', sum(gr > 0));
    kv_i('Steps with g_rel < 0 (sign not resolvable)',      sum(gr < 0));

    % --- Negative tail vs the solver tolerance ---------------------------
    kv_f('Min    restriction gap g_rel_min [%]',  min(gr),        '%8.4f');
    kv_f('5th    restriction gap g_rel_05  [%]',  prctile(gr,5),  '%8.4f');
    neg = gr(gr < 0);
    if ~isempty(neg)
        kv_f('Most negative gap [%]',              min(neg),      '%8.4f');
        kv_f('Median of the negative gaps [%]',    median(neg),   '%8.4f');
    end
    if nargin >= 8 && isfinite(tol_pct) && tol_pct > 0
        kv_f('Relative MIP-gap tolerance in g_rel units [%]', tol_pct, '%8.4f');
        kv_i('Negative gaps beyond 1x the tolerance', sum(gr < -tol_pct));
        kv_i('Negative gaps beyond 2x the tolerance', sum(gr < -2*tol_pct));
        kv_f('Share of |g_rel| within 2x the tolerance [%]', ...
             100*mean(abs(gr) <= 2*tol_pct), '%8.1f');
    else
        note('MIP-gap tolerance not found in the result file; tail counts skipped.');
    end
    kv_f('Mean Delta J_lambda,w^SS (expect exactly 0)', ...
         mean(Jl_pref(pair) - Jl_full(pair), 'omitnan'), '%10.6f');
end

%% =======================================================================
%  SECTION VI-A.3 -- Closed-Loop Control Performance
%% =======================================================================
function sec_VI_A3(resultsDir)
    b = blk_open('sec:VI-A3', 'Section VI-A.3 -- Closed-Loop Control Performance');
    try
        f = find_latest(fullfile(resultsDir, 'Results_nominal_wltc_*.mat'));
        if isempty(f), na('run_nominal_wltc'); blk_close(b); return; end
        S = load(f); src(f);
        R = S.Results; cfg = S.cfg;
        if isfield(cfg,'NUMERICS') && isfield(cfg.NUMERICS,'TRACKING_POWER_EPS')
            P_EPS = cfg.NUMERICS.TRACKING_POWER_EPS;
        else
            P_EPS = 1e-9;
        end
        mA = masks(R.A.log); mD = masks(R.D.log);

        rule('Cell-to-cell SOC dispersion and its reduction factors');
        sA = sigma_soc(R.A.log.z_cell_vec);
        sD = sigma_soc(R.D.log.z_cell_vec);
        ratio_row('cycle-mean sigma_SOC [%]', sA.mean, sD.mean);
        ratio_row('95th pct  sigma_SOC [%]',  sA.p95,  sD.p95);
        ratio_row('maximum   sigma_SOC [%]',  sA.max,  sD.max);

        rule('SOH-weighted closed-loop objective contribution');
        JA = mean(R.A.log.J_SOH_weighted(mA.usable),'omitnan');
        JD = mean(R.D.log.J_SOH_weighted(mD.usable),'omitnan');
        kv_f('Baseline J_SOH,w^CL',              JA, '%10.4f');
        kv_f('Proposed J_SOH,w^CL',              JD, '%10.4f');
        kv_f('Relative change (Prop vs Base) [%]', 100*(JD-JA)/JA, '%+10.3f');

        rule('Power-tracking error');
        for v = {'A','D'}
            vid = v{1}; L = R.(vid).log; m = masks(L);
            p_req = L.p_pack_req; p_del = L.p_pack_meas;
            nz  = m.active & (abs(p_req) > P_EPS);
            rel = 100*abs(p_req - p_del) ./ max(abs(p_req), P_EPS);
            lbl = ctrl_label(vid);
            kv_f(sprintf('%-9s e_50  [%%]', lbl), prctile(rel(nz),50), '%10.4f');
            kv_f(sprintf('%-9s e_99  [%%]', lbl), prctile(rel(nz),99), '%10.4f');
            kv_f(sprintf('%-9s e_max [%%]', lbl), max(rel(nz)),        '%10.4f');
        end

        rule('Curtailment');
        for v = {'A','D'}
            vid = v{1}; L = R.(vid).log; m = masks(L);
            nC = round(computeCurtailmentMetric(L, m.active) * m.n_act);
            lbl = ctrl_label(vid);
            kv_i(sprintf('%-9s detected curtailment steps', lbl), nC);
            kv_f(sprintf('%-9s Phi_curt [%%]', lbl), 100*nC/m.n_act, '%10.3f');
        end

        rule('Cell utilization and switching activity');
        kv_f('Baseline phi_eng_bar', phi_eng(R.A.log, mA), '%10.3f');
        kv_f('Proposed phi_eng_bar', phi_eng(R.D.log, mD), '%10.3f');
        wA = switching(R.A.log, mA); wD = switching(R.D.log, mD);
        kv_f('Baseline n_sw_bar [cells]', wA.mean, '%10.2f');
        kv_f('Proposed n_sw_bar [cells]', wD.mean, '%10.2f');
        kv_f('Change in n_sw_bar [%]',    100*(wD.mean-wA.mean)/wA.mean, '%+10.1f');
        kv_i('Baseline n_sw_95 [cells]',  round(wA.p95));
        kv_i('Proposed n_sw_95 [cells]',  round(wD.p95));

        % --- Cell temperature and thermal-constraint activity -------------
        % Supports the manuscript statement that cell temperatures stayed
        % within the admissible band and that no thermal constraint was
        % active. Temperatures are logged in kelvin; printed in degC.
        rule('Cell temperature and thermal-constraint activity (nominal WLTC)');
        [Tlo_K, Thi_K, has_lim] = local_T_limits(R);
        if has_lim
            kv_f('T_cell lower limit [degC]', Tlo_K - 273.15, '%10.2f');
            kv_f('T_cell upper limit [degC]', Thi_K - 273.15, '%10.2f');
        else
            note('Temperature limits not found in the saved constants.');
        end
        for v = {'A','D'}
            vid = v{1}; L = R.(vid).log; lbl = ctrl_label(vid);
            t = local_T_range(L);
            kv_f(sprintf('%-9s min cell temperature [degC]', lbl), t.min_C, '%10.2f');
            kv_f(sprintf('%-9s max cell temperature [degC]', lbl), t.max_C, '%10.2f');
            if has_lim
                kv_f(sprintf('%-9s margin to T_cell^max [K]', lbl), Thi_K - t.max_K, '%10.2f');
                kv_f(sprintf('%-9s margin to T_cell^min [K]', lbl), t.min_K - Tlo_K, '%10.2f');
                kv_i(sprintf('%-9s steps with a cell within 0.1 K of a limit', lbl), ...
                     local_T_active_steps(L, Tlo_K, Thi_K, 0.1));
            end
        end

        % --- Same, pooled over every saved result file --------------------
        % The manuscript sentence covers all reported simulations, not only
        % the nominal case, so pool the nominal, Monte Carlo and robustness
        % result files. Wrapped separately: a missing file must not abort
        % the rest of this section.
        rule('Cell temperature pooled over all reported result files');
        try
            pats = {'Results_nominal_wltc_*.mat', ...
                    'Results_montecarlo_ics_*.mat', ...
                    'Results_robustness_sweeps_*.mat', ...
                    'Results_samestate_proposed_*.mat', ...
                    'Results_samestate_rulebased_*.mat'};
            mnK = inf; mxK = -inf; nlogs = 0; nfiles = 0;
            for ip = 1:numel(pats)
                fp = find_latest(fullfile(resultsDir, pats{ip}));
                if isempty(fp), continue; end
                Sp = load(fp);
                [mnK, mxK, nlogs] = local_T_walk(Sp, mnK, mxK, nlogs, 0);
                nfiles = nfiles + 1;
            end
            if isfinite(mnK) && isfinite(mxK)
                kv_i('Result files scanned',                    nfiles);
                kv_i('Temperature trajectories scanned',        nlogs);
                kv_f('Pooled min cell temperature [degC]',      mnK - 273.15, '%10.2f');
                kv_f('Pooled max cell temperature [degC]',      mxK - 273.15, '%10.2f');
                if has_lim
                    kv_f('Pooled margin to T_cell^max [K]',     Thi_K - mxK,  '%10.2f');
                    kv_f('Pooled margin to T_cell^min [K]',     mnK - Tlo_K,  '%10.2f');
                end
            else
                note('No temperature logs found in the scanned files.');
            end
        catch errT
            note(sprintf('Pooled temperature scan skipped: %s', errT.message));
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

%% =======================================================================
%  SECTION VI-B.1 -- Sensitivity to Initial Conditions
%% =======================================================================
function sec_VI_B1(resultsDir)
    b = blk_open('sec:VI-B1', 'Section VI-B.1 -- Sensitivity to Initial Conditions');
    try
        f = find_latest(fullfile(resultsDir, 'Results_montecarlo_ics_*.mat'));
        if isempty(f)
            na('run_montecarlo_ics');
            note('This .mat is large; see README.md if it was not shipped with the repo.');
        else
            S = load(f); src(f);
            C = metricsConfig();
            kv_i('Paired realizations N_MC',  S.nRuns);
            kv_i('Bootstrap resamples B',     C.BOOTSTRAP_REPS);
            kv_f('Bootstrap CI level [%]',    C.BOOTSTRAP_CI_LEVEL, '%8.1f');
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

%% =======================================================================
%  SECTION VI-B.2 -- Cell Heterogeneity and Demand Conditions
%% =======================================================================
function sec_VI_B2(resultsDir)
    b = blk_open('sec:VI-B2', 'Section VI-B.2 -- Sensitivity to Cell Heterogeneity and Demand');
    try
        R = load_rob(resultsDir);
        if isempty(R), blk_close(b); return; end

        cases = {'WLTC_Low','WLTC_Med','WLTC_High','HighPower'};
        rule('Per-case metrics (N = 20, N_p = 10)');
        hdr_rob();
        for i = 1:numel(cases)
            for v = {'A','D'}
                row_rob(R, sprintf('N20_Np10_%s_%s_balanced', cases{i}, v{1}), cases{i}, v{1});
            end
        end

        rule('Active-step counts per case (K_act)');
        for i = 1:numel(cases)
            m = rob(R, sprintf('N20_Np10_%s_D_balanced', cases{i}));
            if isempty(m), miss(cases{i}); else, kv_i(sprintf('%-12s |K_act|', cases{i}), m.n_active); end
        end

        rule('High Power case (constant 200 W discharge)');
        hA = rob(R,'N20_Np10_HighPower_A_balanced');
        hD = rob(R,'N20_Np10_HighPower_D_balanced');
        if isempty(hA) || isempty(hD)
            miss('N20_Np10_HighPower_{A,D}_balanced');
        else
            kv_f('Baseline eta_opt [%]',          hA.opt_rate,     '%8.1f');
            kv_f('Proposed eta_opt [%]',          hD.opt_rate,     '%8.1f');
            kv_f('Baseline sigma_SOC_bar [%]',    hA.soc_std_mean, '%8.3f');
            kv_f('Proposed sigma_SOC_bar [%]',    hD.soc_std_mean, '%8.3f');
            kv_f('Reduction factor [x]',          hA.soc_std_mean/hD.soc_std_mean, '%8.1f');
        end

        rule('Effect of increasing initial dispersion (WLTC cases)');
        for v = {'A','D'}
            vid = v{1};
            lo = rob(R, sprintf('N20_Np10_WLTC_Low_%s_balanced', vid));
            hi = rob(R, sprintf('N20_Np10_WLTC_High_%s_balanced', vid));
            if ~isempty(lo) && ~isempty(hi)
                kv_f(sprintf('%-9s sigma_SOC_bar, Low -> High [%%]', ctrl_label(vid)), lo.soc_std_mean, '%8.3f');
                kv_f('   -> High [%]', hi.soc_std_mean, '%8.3f');
            end
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

%% =======================================================================
%  SECTION VI-B.3 -- Sensitivity to Pack Size
%% =======================================================================
function sec_VI_B3(resultsDir)
    b = blk_open('sec:VI-B3', 'Section VI-B.3 -- Sensitivity to Pack Size');
    try
        R = load_rob(resultsDir);
        if isempty(R), blk_close(b); return; end

        rule('Per-pack-size metrics (N_p = 10, WLTC Med)');
        hdr_rob();
        for N = [16 20 24]
            for v = {'A','D'}
                row_rob(R, sprintf('N%d_Np10_WLTC_Med_%s_balanced', N, v{1}), sprintf('N=%d', N), v{1});
            end
        end

        rule('Proposed-controller runtime tail across pack sizes');
        p16 = rob(R,'N16_Np10_WLTC_Med_D_balanced');
        p24 = rob(R,'N24_Np10_WLTC_Med_D_balanced');
        if ~isempty(p16) && ~isempty(p24)
            kv_f('Proposed t_95 at N = 16 [ms]', p16.p95_solve_ms, '%8.1f');
            kv_f('Proposed t_95 at N = 24 [ms]', p24.p95_solve_ms, '%8.1f');
        end
        rule('Baseline runtime tail across pack sizes (all near the 1 s limit)');
        for N = [16 20 24]
            m = rob(R, sprintf('N%d_Np10_WLTC_Med_A_balanced', N));
            if ~isempty(m), kv_f(sprintf('Baseline t_95 at N = %2d [ms]', N), m.p95_solve_ms, '%8.1f'); end
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

%% =======================================================================
%  SECTION VI-B.4 -- Sensitivity to Prediction Horizon
%% =======================================================================
function sec_VI_B4(resultsDir)
    b = blk_open('sec:VI-B4', 'Section VI-B.4 -- Sensitivity to Prediction Horizon');
    try
        R = load_rob(resultsDir);
        if isempty(R), blk_close(b); return; end
        H = [4 6 8 10];

        rule('Per-horizon metrics (N = 20, WLTC Med)');
        hdr_rob();
        for h = H
            for v = {'A','D'}
                row_rob(R, hkey(h, v{1}), sprintf('Np=%d', h), v{1});
            end
        end

        rule('Baseline computation-performance tradeoff over the horizon');
        b4 = rob(R, hkey(4,'A')); b10 = rob(R, hkey(10,'A'));
        if ~isempty(b4) && ~isempty(b10)
            kv_f('Baseline sigma_SOC_bar at N_p = 4  [%]',  b4.soc_std_mean,  '%8.3f');
            kv_f('Baseline sigma_SOC_bar at N_p = 10 [%]',  b10.soc_std_mean, '%8.3f');
            kv_f('Baseline eta_opt at N_p = 4  [%]',        b4.opt_rate,      '%8.1f');
            kv_f('Baseline eta_opt at N_p = 10 [%]',        b10.opt_rate,     '%8.1f');
            kv_f('Baseline t_95 at N_p = 4 [ms]',           b4.p95_solve_ms,  '%8.1f');
        end
        firstCurt = NaN;
        for h = H
            m = rob(R, hkey(h,'A'));
            if ~isempty(m) && m.curt_frac > 0 && isnan(firstCurt), firstCurt = h; end
        end
        if isnan(firstCurt)
            note('Baseline curtailment is zero at every tested horizon.');
        else
            kv_i('Smallest N_p at which baseline curtailment appears', firstCurt);
        end

        rule('Proposed controller over the horizon');
        p4 = rob(R, hkey(4,'D')); p10 = rob(R, hkey(10,'D'));
        if ~isempty(p4) && ~isempty(p10)
            kv_f('Proposed t_95 at N_p = 4  [ms]',          p4.p95_solve_ms,  '%8.1f');
            kv_f('Proposed t_95 at N_p = 10 [ms]',          p10.p95_solve_ms, '%8.1f');
            kv_f('Proposed sigma_SOC_bar at N_p = 4  [%]',  p4.soc_std_mean,  '%8.3f');
            kv_f('Proposed sigma_SOC_bar at N_p = 10 [%]',  p10.soc_std_mean, '%8.3f');
        end
        allCert = true; allNoCurt = true;
        for h = H
            m = rob(R, hkey(h,'D'));
            if ~isempty(m)
                if m.opt_rate  < 100, allCert  = false; end
                if m.curt_frac > 0,   allNoCurt = false; end
            end
        end
        kv_s('Proposed certifies every active step at every tested N_p', yesno(allCert));
        kv_s('Proposed shows no detected curtailment at any tested N_p', yesno(allNoCurt));

        rule('Cross-horizon comparison quoted at the end of the subsection');
        if ~isempty(p4) && ~isempty(b10) && ~isempty(b4)
            kv_s('Proposed N_p=4 sigma_SOC_bar below baseline N_p=10', ...
                 yesno(p4.soc_std_mean < b10.soc_std_mean));
            kv_f('   Proposed N_p=4  sigma_SOC_bar [%]',   p4.soc_std_mean,  '%8.3f');
            kv_f('   Baseline N_p=10 sigma_SOC_bar [%]',   b10.soc_std_mean, '%8.3f');
            kv_f('t_95 ratio, Baseline N_p=4  / Proposed N_p=4 [x]', ...
                 b4.p95_solve_ms/p4.p95_solve_ms, '%8.1f');
            kv_f('t_95 ratio, Baseline N_p=10 / Proposed N_p=4 [x]', ...
                 b10.p95_solve_ms/p4.p95_solve_ms, '%8.1f');
            kv_f('Proposed eta_opt at N_p = 4 [%]', p4.opt_rate, '%8.1f');
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

function k = hkey(h, vid)
    k = sprintf('N20_Np%d_WLTC_Med_%s_balanced', h, vid);
end

%% =======================================================================
%  SECTION VII -- Conclusion headline numbers
%% =======================================================================
function sec_VII(resultsDir)
    b = blk_open('sec:VII', 'Section VII -- Conclusion (headline numbers restated)');
    try
        f = find_latest(fullfile(resultsDir, 'Results_nominal_wltc_*.mat'));
        if isempty(f)
            na('run_nominal_wltc');
        else
            S = load(f); src(f);
            R = S.Results;
            mA = masks(R.A.log); mD = masks(R.D.log);
            tA = R.A.log.solver_time(mA.active); tD = R.D.log.solver_time(mD.active);
            sA = sigma_soc(R.A.log.z_cell_vec);  sD = sigma_soc(R.D.log.z_cell_vec);
            rule('Nominal 20-cell WLTC case');
            kv_f('Certified-optimality rate, baseline [%]', 100*mA.n_opt/mA.n_act, '%8.2f');
            kv_f('Certified-optimality rate, proposed [%]', 100*mD.n_opt/mD.n_act, '%8.2f');
            kv_f('t_95 reduction factor [x]',               prctile(tA,95)/prctile(tD,95), '%8.1f');
            kv_f('Cycle-mean sigma_SOC reduction factor [x]', sA.mean/sD.mean, '%8.1f');
            nC = round(computeCurtailmentMetric(R.D.log, mD.active) * mD.n_act);
            kv_i('Proposed detected curtailment steps (claim: none)', nC);
        end

        rule('Same-state restriction gap, both trajectories');
        C = metricsConfig();
        gbar = [NaN NaN];
        f1 = find_latest(fullfile(resultsDir, 'Results_samestate_proposed_*.mat'));
        if ~isempty(f1)
            S1 = load(f1); L = S1.Results.D.log;
            act = ~logical(L.rest_skip(:));
            pr  =  logical(L.optimality_proven(:)) & logical(L.ref_optimality_proven(:)) & act ...
                & ~(L.slack_mag(:)     > C.CURTAILMENT_THRESHOLD_A) ...
                & ~(L.ref_slack_mag(:) > C.CURTAILMENT_THRESHOLD_A);
            gbar(1) = mean_grel(L.J_obj(:), L.ref_J_obj(:), pr);
            kv_f('Proposed-controller trajectory g_rel_bar [%]', gbar(1), '%8.3f');
        end
        f2 = find_latest(fullfile(resultsDir, 'Results_samestate_rulebased_*.mat'));
        if ~isempty(f2)
            S2 = load(f2); LN = S2.Results.log;
            act = ~logical(LN.rest_skip(:));
            pr  =  logical(LN.ref_A_optimality_proven(:)) & logical(LN.ref_D_optimality_proven(:)) & act ...
                & ~(LN.ref_A_slack_mag(:) > C.CURTAILMENT_THRESHOLD_A) ...
                & ~(LN.ref_D_slack_mag(:) > C.CURTAILMENT_THRESHOLD_A);
            gbar(2) = mean_grel(LN.ref_D_J_obj(:), LN.ref_A_J_obj(:), pr);
            kv_f('Rule-based-driver trajectory g_rel_bar [%]', gbar(2), '%8.3f');
        end
        if any(isfinite(gbar))
            kv_f('Larger of the two mean gaps [%]', max(gbar(isfinite(gbar))), '%8.3f');
        end
    catch err
        oops(err);
    end
    blk_close(b);
end

function g = mean_grel(J_pref, J_full, pair)
    ga = J_pref(pair) - J_full(pair);
    Jf = J_full(pair);
    ok = isfinite(ga) & isfinite(Jf) & abs(Jf) > 1e-12;
    g  = mean(100 * ga(ok) ./ Jf(ok), 'omitnan');
end

%% =======================================================================
%  APPENDIX -- SOS2 approximation of the inverse pack voltage
%% =======================================================================
function sec_APP(resultsDir)
    b = blk_open('sec:APP', 'Appendix -- SOS2 approximation of the inverse pack voltage');
    try
        f = find_latest(fullfile(resultsDir, 'Results_nominal_wltc_*.mat'));
        if isempty(f), na('run_nominal_wltc'); blk_close(b); return; end
        S = load(f); src(f);
        R = S.Results;
        C = metricsConfig();
        pwl  = R.D.constants_v.models.pwl.invVpack;
        v_bp = pwl.vgrid(:); r_bp = pwl.invgrid(:);
        dv   = diff(v_bp);
        vf   = linspace(v_bp(1), v_bp(end), 10000);
        err  = max(abs(interp1(v_bp, r_bp, vf, 'linear') - 1./vf));
        pk   = max(abs(R.D.log.p_pack_req));

        rule('Breakpoint grid');
        kv_i('Number of breakpoints N_v',                 numel(v_bp));
        kv_f('Pack-voltage range low  [V]',               v_bp(1),   '%10.2f');
        kv_f('Pack-voltage range high [V]',               v_bp(end), '%10.2f');
        kv_f('Smallest breakpoint spacing [V]',           min(dv),   '%10.2f');
        kv_f('Largest  breakpoint spacing [V]',           max(dv),   '%10.2f');

        rule('Approximation error');
        kv_e('Worst-case pointwise error eps_SOS2 [V^-1]', err);
        kv_f('Peak requested power |p_req| [W]',           pk, '%10.1f');
        kv_e('Implied curtailment-error bound |dlambda| [A]', pk*err);
        kv_e('Detection threshold eps_lambda [A]',         C.CURTAILMENT_THRESHOLD_A);
        kv_f('Bound / threshold [-]',                      pk*err/C.CURTAILMENT_THRESHOLD_A, '%10.4f');
    catch err
        oops(err);
    end
    blk_close(b);
end

%% =======================================================================
%  Robustness-sweep helpers
%% =======================================================================
function R = load_rob(resultsDir)
% NOTE: run_robustness_sweeps.m saves its sweep struct as RobResults, NOT as
% Results (unlike every other runner). Do not "simplify" this to S.Results.
    R = [];
    f = find_latest(fullfile(resultsDir, 'Results_robustness_sweeps_*.mat'));
    if isempty(f), na('run_robustness_sweeps'); return; end
    S = load(f); src(f);
    R = rob_struct(S);
end

function R = rob_struct(S)
    if isfield(S, 'RobResults')
        R = S.RobResults;
    elseif isfield(S, 'Results')
        R = S.Results;          % tolerated for legacy result files
    else
        error('report_intext_numbers:noRobResults', ...
            ['Robustness result file contains neither RobResults nor ' ...
             'Results. Variables found: %s'], strjoin(fieldnames(S)', ', '));
    end
end

function m = rob(R, key)
    if isstruct(R) && isfield(R, key)
        m = extract_robustness_metrics(R.(key).log, R.(key).cfg);
    else
        m = [];
    end
end

function hdr_rob()
    fprintf('    %-12s %-6s %10s %12s %14s %10s %10s\n', ...
        'Cond.', 'Ctrl.', 'e_bar [%]', 'Phi_curt[%]', 'sigma_SOC[%]', 't_95[ms]', 'eta_opt[%]');
    fprintf('    %s\n', repmat('-', 1, 78));
end

function row_rob(R, key, condLabel, vid)
    m = rob(R, key);
    if isempty(m)
        fprintf('    %-12s %-6s   (missing key: %s)\n', condLabel, ctrl_label(vid), key);
    else
        fprintf('    %-12s %-6s %10.3f %12.3f %14.3f %10.1f %10.1f\n', ...
            condLabel, ctrl_label(vid), m.tracking_mae, m.curt_frac, ...
            m.soc_std_mean, m.p95_solve_ms, m.opt_rate);
    end
end

%% =======================================================================
%  Shared metric helpers (mirror the analyze_*.m definitions exactly)
%% =======================================================================
function m = masks(L)
    m.active   = ~L.rest_skip;
    m.opt      = L.optimality_proven & m.active;
    m.inc      = L.incumbent_timeout & m.active;
    m.hf       = L.hard_fail         & m.active;
    m.usable   = (m.opt | m.inc)     & m.active;
    m.n_act    = sum(m.active);
    m.n_opt    = sum(m.opt);
    m.n_inc    = sum(m.inc);
    m.n_hf     = sum(m.hf);
    m.n_usable = sum(m.usable);
end

function s = sigma_soc(z)
    sig = std(z(:,2:end), 1, 1) * 100;
    sig = sig(isfinite(sig));
    s.mean = mean(sig, 'omitnan');
    s.p95  = prctile(sig, 95);
    s.max  = max(sig);
end

function s = switching(L, m)
    S_d    = double(L.S);
    n_sw   = sum(abs(diff(S_d, 1, 2)), 1);
    n_sw_a = n_sw(m.active(2:end));
    s.mean = mean(n_sw_a);
    s.p95  = prctile(n_sw_a, 95);
    s.max  = max(n_sw_a);
end

function v = phi_eng(L, m)
    S  = double(L.S);
    ef = mean(S(:, m.usable), 2);
    v  = mean(ef(isfinite(ef)), 'omitnan');
end

function s = ctrl_label(vid)
    if strcmp(vid, 'A'), s = 'Baseline'; else, s = 'Proposed'; end
end

function np = local_getNp(cfg)
% Prediction horizon N_p. NOTE: cfg.Np is the number of PARALLEL STRINGS
% (default 1), not the horizon -- the horizon lives in cfg.mpc.Np. Do not
% substitute one for the other.
    np = NaN;
    if isfield(cfg, 'mpc') && isfield(cfg.mpc, 'Np')
        np = cfg.mpc.Np;
    end
end

function dt = local_getTstep(cfg)
    if isfield(cfg, 'Tstep') && ~isempty(cfg.Tstep), dt = cfg.Tstep; else, dt = 1; end
end

function f = find_latest(pattern)
    d = dir(pattern);
    if isempty(d), f = ''; return; end
    [~, i] = max([d.datenum]);
    f = fullfile(d(i).folder, d(i).name);
end

%% =======================================================================
%  Section dispatch with per-block error isolation
%% =======================================================================
function safe(fh, resultsDir, tag)
% Run one section. If it throws before its own internal handler catches
% the error, emit a self-contained block carrying the error so the failure
% is visible in the report and localised to this section.
    try
            fh(resultsDir);
    catch err
        fprintf('<<<MANUSCRIPT_TABLE_BEGIN %s>>>\n', tag);
        fprintf('  [BLOCK FAILED]\n');
        fprintf('  %s\n', err.message);
        if ~isempty(err.stack)
            fprintf('  at %s line %d\n', err.stack(1).name, err.stack(1).line);
        end
        fprintf('<<<MANUSCRIPT_TABLE_END %s>>>\n\n', tag);
    end
end

%% =======================================================================
%  Printing helpers
%% =======================================================================
function tag = blk_open(tag, title)
    fprintf('<<<MANUSCRIPT_TABLE_BEGIN %s>>>\n', tag);
    fprintf('%s\n', title);
    fprintf('%s\n', repmat('=', 1, 78));
end

function blk_close(tag)
    fprintf('<<<MANUSCRIPT_TABLE_END %s>>>\n', tag);
    fprintf('\n');
end

function rule(txt)
    fprintf('\n  -- %s\n', txt);
    fprintf('  %s\n', repmat('-', 1, 76));
end

function src(f)
    fprintf('  source: %s\n', f);
end

function na(runner)
    fprintf('  [NOT AVAILABLE -- run mainSimulationRunners/%s.m]\n', runner);
end

function miss(key)
    fprintf('    (missing key: %s)\n', key);
end

function oops(err)
    fprintf('\n  [SECTION FAILED -- the rest of the report is unaffected]\n');
    fprintf('  %s\n', err.message);
    if ~isempty(err.stack)
        fprintf('  at %s line %d\n', err.stack(1).name, err.stack(1).line);
    end
end

function note(txt)
    fprintf('    note: %s\n', txt);
end

function kv_i(label, val)
    fprintf('    %-58s %8d\n', label, val);
end

function kv_f(label, val, fmt)
    if isempty(fmt), return; end
    fprintf(['    %-58s ' fmt '\n'], label, val);
end

function kv_e(label, val)
    fprintf('    %-58s %14.4e\n', label, val);
end

function kv_s(label, val)
    fprintf('    %-58s %8s\n', label, val);
end

function kv3(label, a, b, c)
    fprintf('    %-58s %8.1f %8.1f %8.1f\n', ...
        [label ' t_50 / t_95 / t_max [ms]'], a, b, c);
end

function powrow(label, vals)
    if isempty(vals)
        fprintf('    %-24s %12s %12s\n', label, '-', '-');
    else
        fprintf('    %-24s mean %8.1f W   median %8.1f W\n', label, mean(vals), median(vals));
    end
end

function ratio_row(label, a, b)
    fprintf('    %-40s %10.4f -> %10.4f   factor %6.1fx\n', label, a, b, a/b);
end

function s = yesno(tf)
    if tf, s = 'yes'; else, s = 'no'; end
end


%% =======================================================================
%  Cell-temperature helpers
%% =======================================================================
function t = local_T_range(L)
% LOCAL_T_RANGE  Min/max logged cell temperature, in kelvin and degC.
%   L.T_cell_vec is Ns x (nSteps+1), in kelvin, preallocated with NaN, so
%   non-finite entries (unfilled columns after an early break) are dropped.
    t = struct('min_K',NaN,'max_K',NaN,'min_C',NaN,'max_C',NaN);
    if ~isfield(L,'T_cell_vec'), return; end
    T = L.T_cell_vec(:);
    T = T(isfinite(T));
    if isempty(T), return; end
    t.min_K = min(T);
    t.max_K = max(T);
    t.min_C = t.min_K - 273.15;
    t.max_C = t.max_K - 273.15;
end


function n = local_T_active_steps(L, Tlo_K, Thi_K, tol_K)
% LOCAL_T_ACTIVE_STEPS  Number of steps at which any cell sits within tol_K
% of either temperature limit, i.e. steps where the thermal constraint is at
% or near activity.
    n = NaN;
    if ~isfield(L,'T_cell_vec'), return; end
    T    = L.T_cell_vec;
    near = (T >= Thi_K - tol_K) | (T <= Tlo_K + tol_K);
    near(~isfinite(T)) = false;
    n = sum(any(near, 1));
end


function [Tlo_K, Thi_K, ok] = local_T_limits(R)
% LOCAL_T_LIMITS  Recover the cell temperature limits [K] from the constants
% bundle saved alongside each variant's log.
    Tlo_K = NaN; Thi_K = NaN; ok = false;
    vids = {'A','D'};
    for i = 1:numel(vids)
        vid = vids{i};
        if isfield(R, vid) && isfield(R.(vid), 'constants_v') && ...
                isfield(R.(vid).constants_v, 'limits')
            lim = R.(vid).constants_v.limits;
            if isfield(lim,'T_cell_min') && isfield(lim,'T_cell_max')
                Tlo_K = lim.T_cell_min;
                Thi_K = lim.T_cell_max;
                ok    = true;
                return;
            end
        end
    end
end


function [mn, mx, n] = local_T_walk(S, mn, mx, n, depth)
% LOCAL_T_WALK  Recursively pool min/max over every T_cell_vec field found in
% a loaded results struct, whatever the nesting used by a given runner.
    if depth > 6 || ~isstruct(S), return; end
    for e = 1:numel(S)
        fn = fieldnames(S(e));
        for i = 1:numel(fn)
            v = S(e).(fn{i});
            if strcmp(fn{i}, 'T_cell_vec') && isnumeric(v) && ~isempty(v)
                t = v(isfinite(v));
                if ~isempty(t)
                    mn = min(mn, min(t(:)));
                    mx = max(mx, max(t(:)));
                    n  = n + 1;
                end
            elseif isstruct(v)
                [mn, mx, n] = local_T_walk(v, mn, mx, n, depth+1);
            elseif iscell(v)
                for c = 1:numel(v)
                    if isstruct(v{c})
                        [mn, mx, n] = local_T_walk(v{c}, mn, mx, n, depth+1);
                    end
                end
            end
        end
    end
end


function tol_pct = local_gap_tol_pct(S)
% LOCAL_GAP_TOL_PCT  Relative MIP-gap tolerance in g_rel units [%].
%   Searches the loaded result struct for a solver MIPGap setting and returns
%   100*MIPGap. Falls back to the project default (1e-4) if none is stored.
    g = local_find_field(S, 'MIPGap', 0);
    if ~isfinite(g) || g <= 0
        g = 1e-4;   % buildSolverOptions default
    end
    tol_pct = 100 * g;
end


function val = local_find_field(S, name, depth)
% LOCAL_FIND_FIELD  First finite scalar value of a named field, searched
% recursively through a nested struct. Returns NaN if not found.
    val = NaN;
    if depth > 6 || ~isstruct(S), return; end
    for e = 1:numel(S)
        fn = fieldnames(S(e));
        for i = 1:numel(fn)
            v = S(e).(fn{i});
            if strcmp(fn{i}, name) && isnumeric(v) && isscalar(v) && isfinite(v)
                val = double(v);
                return;
            elseif isstruct(v)
                val = local_find_field(v, name, depth+1);
                if isfinite(val), return; end
            end
        end
    end
end
