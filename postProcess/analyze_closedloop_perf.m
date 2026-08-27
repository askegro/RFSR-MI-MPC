% postProcess/analyze_closedloop_perf.m

clc;

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));  % parent of postProcess
addpath(projectRoot);

rootDir = initProjectPaths(thisFile);

%% Load latest ablation result and configure output capture
latestFile = findLatestResultFile(fullfile(rootDir, 'results', 'Results_nominal_wltc_*.mat'), ...
    'Run mainSimulationRunners/run_nominal_wltc.m first.');

try
    fprintf('=== ANALYZE VI-A.3: Closed-Loop Performance (Variants A and D) ===\n\n');

    SEP = repmat('=', 1, 66);
    sep = repmat('-', 1, 66);

    data = load(latestFile);
    fprintf('Loaded %s\n\n', latestFile);

    R        = data.Results;
    variants = {'A', 'D'};
    cfg      = data.cfg;

    if isfield(cfg, 'NUMERICS') && isfield(cfg.NUMERICS, 'TRACKING_POWER_EPS')
        P_EPS = cfg.NUMERICS.TRACKING_POWER_EPS;
    else
        P_EPS = 1e-9;
    end

    for v = variants
        vid = v{1};
        M.(vid) = get_masks(R.(vid).log);
    end


    %% =========================================================================
    %  COMPUTE: All data structures (no printing)
    %% =========================================================================

    % --- Objective components and curtailment ---
    perf = struct();
    for v = variants
        vid = v{1};
        L   = R.(vid).log;
        m   = M.(vid);

        perf.(vid).J_SOH_w  = mean(L.J_SOH_weighted(m.usable),  'omitnan');
        perf.(vid).J_SOC_w  = mean(L.J_SOC_weighted(m.usable),  'omitnan');
        perf.(vid).J_curt_w = mean(L.J_curt_weighted(m.usable), 'omitnan');
        perf.(vid).J_obj    = mean(L.J_obj(m.usable),            'omitnan');
        Curt = computeCurtailmentMetric(L, m.active);
        perf.(vid).curt_pct = 100 * Curt;
    end

    % --- SOC dispersion ---
    soc = struct();
    for v = variants
        vid   = v{1};
        z     = R.(vid).log.z_cell_vec;
        sigma = std(z(:,2:end), 1, 1) * 100;  % population std (divisor N), per manuscript
        sigma = sigma(isfinite(sigma));
        soc.(vid).mean = mean(sigma, 'omitnan');
        soc.(vid).p95  = prctile(sigma, 95);
        soc.(vid).max  = max(sigma);
    end

    % --- Power tracking (mean, e50, e99, emax) ---
    pt = struct();
    for v = variants
        vid    = v{1};
        L      = R.(vid).log;
        m      = M.(vid);
        p_req  = L.p_pack_req;
        p_del  = L.p_pack_meas;
        nz     = m.active & (abs(p_req) > P_EPS);
        rel    = abs(p_req - p_del) ./ max(abs(p_req), P_EPS);
        rel_nz = rel(nz);
        pt.(vid).mean = 100 * mean(rel_nz);
        pt.(vid).e50  = 100 * prctile(rel_nz, 50);
        pt.(vid).e99  = 100 * prctile(rel_nz, 99);
        pt.(vid).emax = 100 * max(rel_nz);
    end

    % --- EFC and engagement-frequency uniformity ---
    uniformity = struct();
    for v = variants
        vid = v{1};
        L   = R.(vid).log;
        m   = M.(vid);

        efc = L.EFC_cell_vec(:,end);
        efc = efc(isfinite(efc));
        uniformity.(vid).efc_mean  = mean(efc, 'omitnan');
        uniformity.(vid).efc_std   = std(efc, 0, 'omitnan');
        uniformity.(vid).efc_cov   = uniformity.(vid).efc_std / uniformity.(vid).efc_mean * 100;
        uniformity.(vid).efc_min   = min(efc);
        uniformity.(vid).efc_max   = max(efc);
        uniformity.(vid).efc_ratio = uniformity.(vid).efc_max / uniformity.(vid).efc_min;

        S  = double(L.S);
        ef = mean(S(:,m.usable), 2);
        ef = ef(isfinite(ef));
        uniformity.(vid).eng_mean  = mean(ef, 'omitnan');
        uniformity.(vid).eng_std   = std(ef, 0, 'omitnan');
        uniformity.(vid).eng_cov   = uniformity.(vid).eng_std / uniformity.(vid).eng_mean * 100;
        uniformity.(vid).eng_min   = min(ef);
        uniformity.(vid).eng_max   = max(ef);
        uniformity.(vid).eng_ratio = uniformity.(vid).eng_max / uniformity.(vid).eng_min;
    end

    % --- Switching statistics ---
    sw_stats = struct();
    for v = variants
        vid    = v{1};
        S_d    = double(R.(vid).log.S);
        n_sw   = sum(abs(diff(S_d, 1, 2)), 1);
        act_sw = M.(vid).active(2:end);
        n_sw_a = n_sw(act_sw);
        sw_stats.(vid).mean   = mean(n_sw_a);
        sw_stats.(vid).median = median(n_sw_a);
        sw_stats.(vid).p95    = prctile(n_sw_a, 95);
        sw_stats.(vid).max    = max(n_sw_a);
    end

    % --- Compounding / SOC spread by solve class (moved from analyze_solver_certification) ---
    L_A = R.A.log;
    L_D = R.D.log;
    m_A = M.A;
    m_D = M.D;
    z_A     = L_A.z_cell_vec;
    z_std_A = squeeze(std(z_A, 0, 1)) * 100;     % length T+1
    z_std_at_opt = z_std_A(find(m_A.opt) + 1);
    z_std_at_inc = z_std_A(find(m_A.inc) + 1);
    z_std_at_opt = z_std_at_opt(isfinite(z_std_at_opt));
    z_std_at_inc = z_std_at_inc(isfinite(z_std_at_inc));
    soc_std_opt_mean = mean(z_std_at_opt);
    soc_std_inc_mean = mean(z_std_at_inc);
    a_inc_d_opt = m_A.inc & m_D.opt;

    % --- Power tracking: mean, p99, max only (moved from analyze_solver_certification) ---
    pt_vb1 = struct();
    for v = variants
        vid   = v{1};
        L     = R.(vid).log;
        m     = M.(vid);
        p_req = L.p_pack_req;
        p_del = L.p_pack_meas;
        nz    = m.active & (abs(p_req) > P_EPS);
        rel   = abs(p_req - p_del) ./ (max(abs(p_req), P_EPS));
        pt_vb1.(vid).mean = 100 * mean(rel(nz));
        pt_vb1.(vid).p99  = 100 * prctile(rel(nz), 99);
        pt_vb1.(vid).max  = 100 * max(rel(nz));
    end


    %% =========================================================================
    %  SECTION 1 — MANUSCRIPT TABLES  (tab: labels from Section VI-A.2/3)
    %% =========================================================================

    % --- TABLE closed_loop_summary (tab:closed_loop_summary) ---
    % Reproduces manuscript Table V exactly (Section VI-A.3), consolidating
    % the perf/soc/pt/uniformity/sw_stats structs computed above (variant
    % A = Baseline, D = Proposed) into the paper's single table, with
    % manuscript row grouping, symbols, and units. This does not replace
    % the more detailed per-topic tables below (performance_all,
    % soc_dispersion, etc.) -- those remain for diagnostic purposes.
    fprintf('--- TABLE closed_loop_summary (tab:closed_loop_summary): Closed-Loop Performance Over The Nominal WLTC Cycle ---\n');
    fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:closed_loop_summary>>>\n');
    fprintf('%s\n', SEP);
    fprintf('%-24s %10s %10s\n', 'Metric', 'Baseline', 'Proposed');
    fprintf('%s\n', sep);
    fprintf('%s\n', 'Closed-loop online objective');
    fprintf('%-24s %10.4f %10.4f\n', 'J_obj^CL [-]',      perf.A.J_obj,    perf.D.J_obj);
    fprintf('%-24s %10.4f %10.4f\n', 'J_SOH,w^CL [-]',    perf.A.J_SOH_w,  perf.D.J_SOH_w);
    fprintf('%-24s %10.4f %10.4f\n', 'J_SOC,w^CL [-]',    perf.A.J_SOC_w,  perf.D.J_SOC_w);
    fprintf('%-24s %10.4f %10.4f\n', 'J_lambda,w^CL [-]', perf.A.J_curt_w, perf.D.J_curt_w);
    fprintf('%s\n', sep);
    fprintf('%s\n', 'Curtailment');
    fprintf('%-24s %10.3f %10.3f\n', 'Phi_curt [%]', perf.A.curt_pct, perf.D.curt_pct);
    fprintf('%s\n', sep);
    fprintf('%s\n', 'Cell-to-cell SOC regulation');
    fprintf('%-24s %10.4f %10.4f\n', 'sigma_SOC_bar [%]', soc.A.mean, soc.D.mean);
    fprintf('%-24s %10.4f %10.4f\n', 'sigma_SOC_95 [%]',  soc.A.p95,  soc.D.p95);
    fprintf('%-24s %10.4f %10.4f\n', 'sigma_SOC_max [%]', soc.A.max,  soc.D.max);
    fprintf('%s\n', sep);
    fprintf('%s\n', 'Power-tracking error');
    fprintf('%-24s %10.4f %10.4f\n', 'e_50 [%]',  pt.A.e50,  pt.D.e50);
    fprintf('%-24s %10.4f %10.4f\n', 'e_99 [%]',  pt.A.e99,  pt.D.e99);
    fprintf('%-24s %10.4f %10.4f\n', 'e_max [%]', pt.A.emax, pt.D.emax);
    fprintf('%s\n', sep);
    fprintf('%s\n', 'Cell usage and switching');
    fprintf('%-24s %10.3f %10.3f\n', 'phi_eng_bar [-]', uniformity.A.eng_mean, uniformity.D.eng_mean);
    fprintf('%-24s %10.2f %10.2f\n', 'n_sw_bar [-]', sw_stats.A.mean, sw_stats.D.mean);
    fprintf('%-24s %10.0f %10.0f\n', 'n_sw_95 [-]',  sw_stats.A.p95,  sw_stats.D.p95);
    fprintf('%s\n', SEP);
    fprintf('<<<MANUSCRIPT_TABLE_END tab:closed_loop_summary>>>\n');
    fprintf('\n\n');

    % --- TABLE performance_all (tab:performance_all) ---
    % Closed-loop deployed performance over usable active WLTC steps.
    % J_obj = J_SOH_w + J_SOC_w + J_curt_w; Curt = fraction of active steps with curtailment.
    fprintf('--- TABLE performance_all: Closed-loop deployed performance over usable active WLTC steps ---\n');
    fprintf('%s\n', SEP);
    fprintf('  (J_obj = J_SOH_w + J_SOC_w + J_curt_w; Curt = fraction of active steps with curtailment)\n');
    fprintf('%-6s %10s %10s %10s %10s %10s\n', ...
        'Var.', 'J_obj', 'J_SOH_w', 'J_SOC_w', 'J_curt_w', 'Curt[%]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %10.4f %10.4f %10.4f %10.4f %10.3f\n', vid, ...
            perf.(vid).J_obj,    perf.(vid).J_SOH_w, ...
            perf.(vid).J_SOC_w,  perf.(vid).J_curt_w, ...
            perf.(vid).curt_pct);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE soc_dispersion (tab:soc_dispersion) ---
    % Cross-sectional SOC dispersion over the nominal WLTC cycle.
    % sigma_SOC_bar = cycle-mean; sigma_SOC_95 and sigma_SOC_max = 95th-pctile and max over active steps.
    fprintf('--- TABLE soc_dispersion: Cross-sectional SOC dispersion over the nominal WLTC cycle ---\n');
    fprintf('%s\n', SEP);
    fprintf('  (sigma_SOC_bar = cycle-mean; sigma_SOC_95, sigma_SOC_max = p95 and max over active steps)\n');
    fprintf('%-6s %18s %18s %18s\n', ...
        'Var.', 'sigma_SOC_bar[%]', 'sigma_SOC_95[%]', 'sigma_SOC_max[%]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %18.4f %18.4f %18.4f\n', vid, ...
            soc.(vid).mean, soc.(vid).p95, soc.(vid).max);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE power_tracking_summary (diagnostic) ---
    % Power-tracking error over active nonzero-power steps of the nominal WLTC cycle.
    % e_bar = mean relative tracking error; e50, e99, emax = median, 99th-pctile, maximum.
    fprintf('--- TABLE power_tracking_summary: Power-tracking error over active nonzero-power steps ---\n');
    fprintf('%s\n', SEP);
    fprintf('  (e_bar = mean; e50, e99, emax = median, 99th-pctile, max relative tracking error)\n');
    fprintf('%-6s %10s %10s %10s %10s\n', 'Var.', 'e_bar[%]', 'e50[%]', 'e99[%]', 'emax[%]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %10.4f %10.4f %10.4f %10.4f\n', vid, ...
            pt.(vid).mean, pt.(vid).e50, pt.(vid).e99, pt.(vid).emax);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE usage_uniformity (tab:usage_uniformity) ---
    % End-of-cycle cell-usage uniformity over usable active WLTC steps.
    % f = engagement frequency; CoV and Ratio computed across the 20 cells.
    fprintf('--- TABLE usage_uniformity: End-of-cycle cell-usage uniformity over usable active WLTC steps ---\n');
    fprintf('%s\n', SEP);
    fprintf('  (f = engagement frequency; CoV and Ratio across 20 cells)\n');
    fprintf('%-6s %8s %9s %8s %10s %10s %10s\n', ...
        'Var.', 'f_bar', 'f_CoV[%]', 'f_ratio', 'EFC_bar', 'EFC_CoV[%]', 'EFC_ratio');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %8.3f %9.2f %8.2f %10.4f %10.2f %10.2f\n', vid, ...
            uniformity.(vid).eng_mean, uniformity.(vid).eng_cov, uniformity.(vid).eng_ratio, ...
            uniformity.(vid).efc_mean, uniformity.(vid).efc_cov, uniformity.(vid).efc_ratio);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE switching (tab:switching) ---
    % Cell engagement switches per active step over the nominal WLTC cycle.
    % Step 1 excluded (no prior engagement state exists).
    fprintf('--- TABLE switching: Cell engagement switches per active step over the nominal WLTC cycle ---\n');
    fprintf('%s\n', SEP);
    fprintf('  (Step 1 excluded; no prior engagement state exists)\n');
    fprintf('%-6s %12s %14s %12s %10s\n', 'Var.', 'Mean[cells]', 'Median[cells]', 'p95[cells]', 'Max[cells]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %12.2f %14.0f %12.0f %10.0f\n', vid, ...
            sw_stats.(vid).mean, sw_stats.(vid).median, sw_stats.(vid).p95, sw_stats.(vid).max);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');


    %% =========================================================================
    %  SECTION 2 — DETAILED / DIAGNOSTIC TABLES
    %% =========================================================================

    % --- TABLE power_tracking_detailed: per-variant tracking with max-error context ---
    fprintf('--- TABLE power_tracking_detailed: Power-tracking error (closed-loop, detailed) ---\n');
    fprintf('%s\n', SEP);
    fprintf('  e_k = |P_req - P_meas| / max(|P_req|, eps), active nonzero-power steps\n');
    fprintf('%-6s %10s %10s %10s %10s\n', 'Var', 'mean[%]', 'e50[%]', 'e99[%]', 'emax[%]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %10.4f %10.4f %10.4f %10.4f\n', vid, ...
            pt.(vid).mean, pt.(vid).e50, pt.(vid).e99, pt.(vid).emax);
    end
    fprintf('%s\n', SEP);
    fprintf('\n');

    fprintf('--- TABLE max_error_diagnostic: Context of maximum tracking error ---\n');
    fprintf('%s\n', SEP);
    fprintf('  Is the worst-case error isolated to high-demand steps?\n');
    fprintf('%-6s %12s %14s %18s %16s\n', ...
        'Var', 'emax[%]', '|P_req|_worst[W]', 'pctile_vs_active[%]', 'solve_class');
    fprintf('%s\n', sep);
    for v = variants
        vid   = v{1};
        L     = R.(vid).log;
        m     = M.(vid);
        p_req = L.p_pack_req;
        p_del = L.p_pack_meas;
        nz    = m.active & (abs(p_req) > P_EPS);
        rel   = abs(p_req - p_del) ./ max(abs(p_req), P_EPS);

        nz_idx       = find(nz);
        [emax, imax] = max(rel(nz));
        worst_step   = nz_idx(imax);
        p_worst      = abs(p_req(worst_step));
        p_active     = abs(p_req(m.active));
        pctile_rank  = 100 * mean(p_active <= p_worst);

        if L.optimality_proven(worst_step)
            sc = 'Opt';
        elseif L.incumbent_timeout(worst_step)
            sc = 'TO+Inc';
        else
            sc = 'Fail';
        end

        fprintf('%-6s %12.4f %14.1f %18.1f %16s\n', vid, 100*emax, p_worst, pctile_rank, sc);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE sigma_SOC_selected_steps ---
    step_pts = 0:300:1800;
    fprintf('--- TABLE sigma_SOC_selected_steps: SOC dispersion at selected step indices ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-6s', 'Var');
    for t = step_pts
        fprintf('%10s', sprintf('t=%d', t));
    end
    fprintf('\n');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        z   = R.(vid).log.z_cell_vec;
        fprintf('%-6s', vid);
        for t = step_pts
            if t < size(z,2)
                fprintf('%10.4f', std(z(:,t+1), 1, 1)*100);
            else
                fprintf('%10s', 'N/A');
            end
        end
        fprintf('\n');
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE sigma_SOC_cycle_summary ---
    fprintf('--- TABLE sigma_SOC_cycle_summary: Cycle SOC dispersion summary ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-6s %12s %12s %12s\n', 'Var', 'mean[%]', 'p95[%]', 'max[%]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %12.4f %12.4f %12.4f\n', vid, ...
            soc.(vid).mean, soc.(vid).p95, soc.(vid).max);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE efc_uniformity ---
    fprintf('--- TABLE efc_uniformity: End-of-cycle EFC uniformity ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-6s %12s %12s %10s %12s %12s %10s\n', ...
        'Var', 'mean', 'std', 'CoV[%]', 'min', 'max', 'ratio[x]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %12.6f %12.6f %10.2f %12.4f %12.4f %10.2f\n', vid, ...
            uniformity.(vid).efc_mean, uniformity.(vid).efc_std, uniformity.(vid).efc_cov, ...
            uniformity.(vid).efc_min,  uniformity.(vid).efc_max,  uniformity.(vid).efc_ratio);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE engagement_uniformity ---
    fprintf('--- TABLE engagement_uniformity: Cell engagement-frequency uniformity ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-6s %12s %12s %10s %12s %12s %10s\n', ...
        'Var', 'mean', 'std', 'CoV[%]', 'min', 'max', 'ratio[x]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %12.3f %12.3f %10.2f %12.3f %12.3f %10.2f\n', vid, ...
            uniformity.(vid).eng_mean, uniformity.(vid).eng_std, uniformity.(vid).eng_cov, ...
            uniformity.(vid).eng_min,  uniformity.(vid).eng_max,  uniformity.(vid).eng_ratio);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE performance_delta_D_vs_A ---
    fprintf('--- TABLE performance_delta_D_vs_A: Objective and curtailment deltas ---\n');
    fprintf('%s\n', SEP);
    fprintf('  (Weighted contributions: J_obj = J_SOH_w + J_SOC_w + J_curt_w)\n');
    fprintf('%-20s %12s %12s %12s %12s\n', 'Metric', 'A', 'D', 'D-A', 'D/A[x]');
    fprintf('%s\n', sep);
    print_delta_row('J_obj',    perf.A.J_obj,    perf.D.J_obj);
    print_delta_row('J_SOH_w',  perf.A.J_SOH_w,  perf.D.J_SOH_w);
    print_delta_row('J_SOC_w',  perf.A.J_SOC_w,  perf.D.J_SOC_w);
    print_delta_row('J_curt_w', perf.A.J_curt_w, perf.D.J_curt_w);
    print_delta_row('Curt[%]',  perf.A.curt_pct, perf.D.curt_pct);
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE dispersion_uniformity_delta_D_vs_A ---
    fprintf('--- TABLE dispersion_uniformity_delta_D_vs_A: SOC/EFC/engagement deltas ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-20s %12s %12s %12s %12s\n', 'Metric', 'A', 'D', 'D-A', 'D/A[x]');
    fprintf('%s\n', sep);
    print_delta_row('SOC mean[%]',  soc.A.mean,              soc.D.mean);
    print_delta_row('SOC p95[%]',   soc.A.p95,               soc.D.p95);
    print_delta_row('SOC max[%]',   soc.A.max,               soc.D.max);
    print_delta_row('EFC CoV[%]',   uniformity.A.efc_cov,    uniformity.D.efc_cov);
    print_delta_row('EFC ratio[x]', uniformity.A.efc_ratio,  uniformity.D.efc_ratio);
    print_delta_row('Eng CoV[%]',   uniformity.A.eng_cov,    uniformity.D.eng_cov);
    print_delta_row('Eng ratio[x]', uniformity.A.eng_ratio,  uniformity.D.eng_ratio);
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE manuscript_performance_all: Combined row (J components + sigma_SOC) ---
    fprintf('--- TABLE manuscript_performance_all: J components + SOC dispersion per variant ---\n');
    fprintf('%s\n', SEP);
    fprintf('  (J_obj = J_SOH_w + J_SOC_w + J_curt_w over usable steps; sigma_SOC = cycle mean)\n');
    fprintf('%-6s %10s %10s %10s %10s %10s %10s\n', ...
        'Var', 'J_obj', 'J_SOH_w', 'J_SOC_w', 'J_curt_w', 'Curt[%]', 'sig_SOC[%]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %10.4f %10.4f %10.4f %10.4f %10.3f %10.4f\n', vid, ...
            perf.(vid).J_obj,    perf.(vid).J_SOH_w, ...
            perf.(vid).J_SOC_w,  perf.(vid).J_curt_w, ...
            perf.(vid).curt_pct, soc.(vid).mean);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE switching_frequency: Detailed switching count ---
    % The switching-activity figure is not part of the manuscript.
    fprintf('--- TABLE switching_frequency: Cell engagement switches per active step (detailed) ---\n');
    fprintf('%s\n', SEP);
    fprintf('  (switches = cells with S_i(k) != S_i(k-1))\n');
    fprintf('%-6s %10s %10s %10s %10s\n', 'Var', 'mean', 'median', 'p95', 'max');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %10.3f %10.3f %10.3f %10.0f\n', vid, ...
            sw_stats.(vid).mean, sw_stats.(vid).median, ...
            sw_stats.(vid).p95,  sw_stats.(vid).max);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');


    %% =========================================================================
    %  SECTION 3 — TABLES MOVED FROM analyze_solver_certification
    %% =========================================================================

    % --- TABLE power_tracking: mean, p99, max ---
    fprintf('--- TABLE power_tracking: Power tracking ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-6s %10s %10s %10s\n', 'Var', 'mean[%]', 'p99[%]', 'max[%]');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        fprintf('%-6s %10.4f %10.4f %10.4f\n', vid, ...
            pt_vb1.(vid).mean, pt_vb1.(vid).p99, pt_vb1.(vid).max);
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n');

    % --- TABLE compounding_degradation_A / compounding_soc_std_A ---
    fprintf('--- TABLE compounding_degradation_A: SOC spread and objective by solve class (Variant A) ---\n');
    fprintf('\n--- TABLE compounding_soc_std_A: SOC spread by solve class (Variant A) ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-12s %12s %16s\n', 'Class', 'mean_std[%]', 'ratio_vs_opt[x]');
    fprintf('%s\n', sep);
    fprintf('%-12s %12.4f %16.1f\n', 'Optimal',   soc_std_opt_mean, 1.0);
    fprintf('%-12s %12.4f %16.1f\n', 'Incumbent', soc_std_inc_mean, soc_std_inc_mean/soc_std_opt_mean);
    fprintf('%s\n', SEP);
    fprintf('\n');

    % --- TABLE objective_on_A_incumbent_D_opt (DIAGNOSTIC ONLY) ---
    % NOTE: A and D are on diverged closed-loop plant states — this is NOT a controlled
    % per-step comparison. State divergence confounds solver-class effects.
    % For a controlled comparison see analyze_samestate_gap.m (paired solves
    % from identical pre-control states).
    fprintf('\n--- TABLE objective_on_A_incumbent_D_opt: Objective at matched time indices (DIAGNOSTIC ONLY) ---\n');
    fprintf('%s\n', SEP);
    fprintf('Steps where A=incumbent, D=optimal: n=%d\n', sum(a_inc_d_opt));
    fprintf('  NOTE: A and D are on their own diverged closed-loop plant states.\n');
    fprintf('  State divergence confounds solver-class effects; see analyze_samestate_gap.\n');
    fprintf('  (Weighted contributions: J_obj = J_SOH_w + J_SOC_w + J_curt_w)\n');
    fprintf('%-6s %10s %10s %10s %10s\n', 'Var', 'J_obj', 'J_SOH_w', 'J_SOC_w', 'J_curt_w');
    fprintf('%s\n', sep);
    for v = variants
        vid = v{1};
        L   = R.(vid).log;
        J_SOH_w  = L.J_SOH_weighted(a_inc_d_opt);
        J_SOC_w  = L.J_SOC_weighted(a_inc_d_opt);
        J_curt_w = L.J_curt_weighted(a_inc_d_opt);
        J_obj    = L.J_obj(a_inc_d_opt);
        fprintf('%-6s %10.4f %10.4f %10.4f %10.4f\n', vid, ...
            mean(J_obj,    'omitnan'), ...
            mean(J_SOH_w,  'omitnan'), ...
            mean(J_SOC_w,  'omitnan'), ...
            mean(J_curt_w, 'omitnan'));
    end
    fprintf('%s\n', SEP);
    fprintf('\n\n\n');


    fprintf('=== Analysis complete (VI-A.3) ===\n');

catch ME
    fprintf(2, '\nERROR while running %s:\n%s\n', mfilename, ...
        getReport(ME, 'extended', 'hyperlinks', 'off'));
    rethrow(ME);
end


%% Helper: usable-step mask
%
% Manuscript correspondence (Section VI-A.3):
%   m.active -> K_act    (eq:KactDef)
%   m.opt    -> K_opt^f  (eq:KoptDef)
%   m.usable -> K_usable (eq:KusableDef): K_act minus Fail steps
function m = get_masks(L)
    m.active = ~L.rest_skip;
    m.opt    = L.optimality_proven & m.active;
    m.inc    = L.incumbent_timeout & m.active;
    m.usable = (m.opt | m.inc)     & m.active;
end


function print_delta_row(label, a, d)
    delta = d - a;
    ratio = d / a;
    fprintf('%-20s %12.6g %12.6g %12.6g %12.4g\n', ...
        label, a, d, delta, ratio);
end


