% analyze_solver_certification.m

clc;

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));  % parent of postProcess
addpath(projectRoot);

rootDir = initProjectPaths(thisFile);

%% Load latest ablation result and configure output capture
latestFile = findLatestResultFile(fullfile(rootDir, 'results', 'Results_nominal_wltc_*.mat'), ...
    'Run mainSimulationRunners/run_nominal_wltc.m first.');

try
    fprintf('=== ANALYZE VI-A.1: Runtime + Reliability (Variants A and D) ===\n\n');

    SEP  = repmat('=', 1, 66);
    sep  = repmat('-', 1, 66);

    data = load(latestFile);
    fprintf('Loaded %s\n\n', latestFile);

    if isfield(data, 'cfg') && isfield(data.cfg, 'NUMERICS') && ...
            isfield(data.cfg.NUMERICS, 'TRACKING_POWER_EPS')
        P_EPS = data.cfg.NUMERICS.TRACKING_POWER_EPS;
    else
        P_EPS = 1e-9;
    end

    R        = data.Results;
    variants = {'A', 'D'};
    cfg = data.cfg;

    % Precompute masks
    for v = variants
        vid = v{1};
        M.(vid) = get_masks(R.(vid).log);
    end


    %% =========================================================================
    %  SECTION 1: Solve classification (Table runtime_classification)
    %% =========================================================================
    % 'Opt[%]' column here is manuscript eta_opt (eq:etaOptMetric) = |K_opt^f|/|K_act|.
    fprintf('--- TABLE runtime_classification: Solve classification over the nominal WLTC cycle ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-6s %8s %8s %8s \n', ...
        'Var.','Opt[%]','TO+Inc[%]','Fail[%]');
    fprintf('%s\n', sep);

    for v = variants
        vid = v{1};
        L   = R.(vid).log;
        m   = M.(vid);

        sw    = L.solver_time;
        p_req = L.p_pack_req;
        p_del = L.p_pack_meas;                      % plant-measured delivered power
        nz    = m.active & (abs(p_req) > P_EPS);
        rel   = abs(p_req - p_del) ./ (max(abs(p_req), P_EPS));

        fprintf('%-6s %8.2f %8.2f %8.2f\n', vid, ...
            100*m.n_opt/m.n_act, ...
            100*m.n_inc/m.n_act, ...
            100*m.n_hf/m.n_act  ...
            );
    end
    fprintf('%s\n', SEP);
    fprintf('\n');
    fprintf('\n');


    %% =========================================================================
    %  SECTION 2: Solver efficiency (all active calls)
    %
    %  This table is intended for the manuscript. All timing and node-count
    %  statistics below are computed over the same population: all active
    %  closed-loop solver calls, including certified-optimal solves,
    %  incumbent-timeout solves, and hard-fail solves. This avoids mixing
    %  timing statistics over all calls with node-count statistics over only
    %  certified-optimal calls.
    %% =========================================================================
    % Reproduces manuscript Table III (tab:runtime_timing). Columns map to
    % t_50/t_95/t_max, Root[%], n^node_50/n^node_95/n^node_max over K_act.
    fprintf('--- TABLE runtime_timing (tab:runtime_timing): Solver-time And Branch-and-Bound Statistics For The Nominal WLTC Cycle ---\n');
    fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:runtime_timing>>>\n');
    fprintf('%s\n', SEP);
    rtLabel = struct('A', 'Baseline', 'D', 'Proposed');  % manuscript Table III "Controller" column
    fprintf('%-10s %8s %8s %8s %8s %10s %10s %10s\n', ...
        'Controller', 't_50[ms]', 't_95[ms]', 't_max[ms]', 'Root[%]', ...
        'n^node_50', 'n^node_95', 'n^node_max');
    fprintf('%s\n', sep);

    for v = variants
        vid    = v{1};
        L      = R.(vid).log;
        m      = M.(vid);
        % solver_time = Gurobi internal r.runtime (excludes YALMIP overhead).
        % Use solver_time, not solve_wall, for manuscript timing statistics.
        sw_act = 1e3 * L.solver_time(m.active);
        nc_act = L.node_count(m.active);

        % Definition: a root-node solve has node_count <= 1. The statistic is
        % computed over all active calls, not only certified-optimal calls.
        root_share = 100 * mean(nc_act <= 1, 'omitnan');

        fprintf('%-10s %8.1f %8.1f %8.1f %8.1f %10.0f %10.0f %10.0f\n', rtLabel.(vid), ...
            prctile(sw_act,50), ...
            prctile(sw_act,95), ...
            max(sw_act), ...
            root_share, ...
            prctile(nc_act,50), ...
            prctile(nc_act,95), ...
            max(nc_act));
    end
    fprintf('%s\n', sep);
    % Speedup row (Baseline/Proposed): column-wise speedup ratios for t_50, t_95, t_max
    sw_A_rt = R.A.log.solver_time(M.A.active);
    sw_D_rt = R.D.log.solver_time(M.D.active);
    fprintf('%-10s %8s %8s %8s %8s %10s %10s %10s\n', 'Speedup', ...
        sprintf('%.1fx', median(sw_A_rt)/median(sw_D_rt)), ...
        sprintf('%.1fx', prctile(sw_A_rt,95)/prctile(sw_D_rt,95)), ...
        sprintf('%.1fx', max(sw_A_rt)/max(sw_D_rt)), ...
        '--', '--', '--', '--');
    fprintf('%s\n', SEP);
    fprintf('<<<MANUSCRIPT_TABLE_END tab:runtime_timing>>>\n');
    fprintf('\n');

    % -------------------------------------------------------------------------
    % Consistency check: t_max vs TimeLimit
    %
    % Gurobi's TimeLimit is a soft checkpoint checked at B&B node boundaries,
    % not a hard interrupt. A node that STARTS before the limit and FINISHES
    % after it still returns status=Optimal with r.runtime > TimeLimit. This
    % means solver_time can legitimately exceed cfg.timeLimit even for
    % certified-optimal steps. The check below prints the solve class of the
    % maximum-time step so this can be verified from the logs.
    % -------------------------------------------------------------------------
    sw_A_all  = R.A.log.solver_time(M.A.active);
    [tmax_A, idx_tmax_A] = max(sw_A_all);
    active_idx_A = find(M.A.active);
    step_tmax_A  = active_idx_A(idx_tmax_A);
    if M.A.opt(step_tmax_A)
        class_tmax_A = 'certified-optimal';
    elseif M.A.inc(step_tmax_A)
        class_tmax_A = 'incumbent-timeout';
    else
        class_tmax_A = 'hard-fail';
    end
    fprintf('--- Consistency check: t_max vs TimeLimit (%.0f ms) ---\n', 1e3*cfg.timeLimit);
    fprintf('  Variant A: t_max = %.1f ms at step %d, classified as: %s\n', ...
        1e3*tmax_A, step_tmax_A, class_tmax_A);
    fprintf('  Overrun = %.1f ms above TimeLimit.\n', 1e3*tmax_A - 1e3*cfg.timeLimit);
    fprintf('  NOTE: Gurobi enforces TimeLimit at B&B node boundaries, not mid-node.\n');
    fprintf('  For certified-optimal: the final proof-closing node ran past the limit.\n');
    fprintf('  For incumbent-timeout: a single expensive node was in progress when the\n');
    fprintf('  limit was crossed; Gurobi completed it before checking the clock and\n');
    fprintf('  returning the best incumbent. Both cases are expected Gurobi behaviour.\n\n');

    % Optional diagnostic: certified-optimal calls only. Keep this in the
    % command output for traceability, but do not use it as the main manuscript
    % table unless the caption explicitly says that node statistics exclude
    % timeout/incumbent calls.
    fprintf('\n--- TABLE solver_efficiency_opt_only: Solver nodes on certified-optimal calls only (diagnostic) ---\n');
    fprintf('%s\n', SEP);
    fprintf('%-6s %10s %10s %10s %10s\n', ...
        'Var','root[%]','nodes_50','nodes_95','nodes_max');
    fprintf('%s\n', sep);

    for v = variants
        vid    = v{1};
        L      = R.(vid).log;
        m      = M.(vid);
        nc_opt = L.node_count(m.opt);

        if isempty(nc_opt)
            fprintf('%-6s %10s %10s %10s %10s\n', vid, 'NaN', 'NaN', 'NaN', 'NaN');
        else
            fprintf('%-6s %10.1f %10.0f %10.0f %10.0f\n', vid, ...
                100*mean(nc_opt <= 1, 'omitnan'), ...
                prctile(nc_opt,50), ...
                prctile(nc_opt,95), ...
                max(nc_opt));
        end
    end
    fprintf('%s\n', SEP);
    fprintf('\n');
    fprintf('\n');



    %% =========================================================================
    %  SECTION 2b: End-to-end controller timing
    %
    %  Reports per-component wall times logged since the timing refactor:
    %    t_prepare   ranking, sort, parameter build (prepare_active_mode)
    %    solve_wall  YALMIP overhead + Gurobi solve (call_optimizer)
    %    t_extract   solution unpack + unsort (unpack_active_mode_solution)
    %    t_ctrl_wall total controller time = t_prepare + solve_wall + t_extract
    %
    %  solve_wall vs solver_time: the difference is YALMIP modelling overhead.
    %  t_ctrl_wall is the quantity that must stay below the 1-s sampling period.
    %
    %  Skipped gracefully when loading results produced before the timing refactor.
    %% =========================================================================
    has_timing = isfield(R.A.log, 't_ctrl_wall') && isfield(R.D.log, 't_ctrl_wall');

    if ~has_timing
        fprintf('--- SECTION 3b: End-to-end timing fields not found in this result file.\n');
        fprintf('    Re-run the experiment to populate t_ctrl_wall, t_prepare, t_extract.\n\n');
    else
        % Five rows matching the manuscript Table tab:end_to_end_timing.
        % "Model update" = YALMIP modelling overhead = solve_wall - solver_time.
        % "Solver call"  = Gurobi internal time      = solver_time.
        % Times are converted to milliseconds for direct LaTeX insertion.
        fprintf('--- TABLE end_to_end_timing: End-to-end control-update timing breakdown over the nominal WLTC cycle (active steps only) ---\n');
        fprintf('%s\n', SEP);
        fprintf('%-6s  %-22s  %9s  %9s  %9s\n', 'Var', 'Component', 't_50[ms]', 't_p95[ms]', 't_max[ms]');
        fprintf('%s\n', sep);

        for v = variants
            vid = v{1};
            L   = R.(vid).log;
            m   = M.(vid);
            act = m.active;

            % Helper: extract active finite values in ms
            getms = @(f) 1e3 * L.(f)(act & isfinite(L.(f)));

            % Row 1: Pre-processing (t_prepare = prepare_active_mode wall time).
            % For Variant D: ranking score computation + sort + parameter build.
            % For Variant A: ranking score computation + parameter build only
            %   (enable_sorting=false, so sort is skipped; idx = identity).
            % Row label is implementation-neutral to be accurate for both variants.
            if isfield(L, 't_prepare')
                vals = getms('t_prepare');
                fprintf('%-6s  %-22s  %9.2f  %9.2f  %9.2f\n', vid, 'Pre-processing', ...
                    prctile(vals,50), prctile(vals,95), max(vals));
            else
                fprintf('%-6s  %-22s  %9s  %9s  %9s\n', vid, 'Pre-processing', 'n/a','n/a','n/a');
            end

            % Row 2: Model update (YALMIP overhead = solve_wall - solver_time)
            if isfield(L, 'solve_wall') && isfield(L, 'solver_time')
                both_finite = act & isfinite(L.solve_wall) & isfinite(L.solver_time);
                yalmip_oh   = 1e3 * (L.solve_wall(both_finite) - L.solver_time(both_finite));
                fprintf('%-6s  %-22s  %9.2f  %9.2f  %9.2f\n', vid, 'Model update (YALMIP)', ...
                    prctile(yalmip_oh,50), prctile(yalmip_oh,95), max(yalmip_oh));
            else
                fprintf('%-6s  %-22s  %9s  %9s  %9s\n', vid, 'Model update (YALMIP)', 'n/a','n/a','n/a');
            end

            % Row 3: Solver call (Gurobi internal time)
            if isfield(L, 'solver_time')
                vals = getms('solver_time');
                fprintf('%-6s  %-22s  %9.2f  %9.2f  %9.2f\n', vid, 'Solver call (Gurobi)', ...
                    prctile(vals,50), prctile(vals,95), max(vals));
            else
                fprintf('%-6s  %-22s  %9s  %9s  %9s\n', vid, 'Solver call (Gurobi)', 'n/a','n/a','n/a');
            end

            % Row 4: Solution extraction
            if isfield(L, 't_extract')
                vals = getms('t_extract');
                fprintf('%-6s  %-22s  %9.2f  %9.2f  %9.2f\n', vid, 'Solution extraction', ...
                    prctile(vals,50), prctile(vals,95), max(vals));
            else
                fprintf('%-6s  %-22s  %9s  %9s  %9s\n', vid, 'Solution extraction', 'n/a','n/a','n/a');
            end

            % Row 5: Total control update
            if isfield(L, 't_ctrl_wall')
                vals = getms('t_ctrl_wall');
                fprintf('%-6s  %-22s  %9.2f  %9.2f  %9.2f\n', vid, 'Total control update', ...
                    prctile(vals,50), prctile(vals,95), max(vals));
            else
                fprintf('%-6s  %-22s  %9s  %9s  %9s\n', vid, 'Total control update', 'n/a','n/a','n/a');
            end

            % Row 6: YALMIP model-update as % of total (step-wise, percentiles of the ratio)
            if isfield(L, 'solve_wall') && isfield(L, 'solver_time') && isfield(L, 't_ctrl_wall')
                both_ok = act & isfinite(L.solve_wall) & isfinite(L.solver_time) & ...
                          isfinite(L.t_ctrl_wall) & L.t_ctrl_wall > 0;
                yalmip_frac = 100 * (L.solve_wall(both_ok) - L.solver_time(both_ok)) ./ L.t_ctrl_wall(both_ok);
                fprintf('%-6s  %-22s  %9.2f  %9.2f  %9.2f\n', '', 'YALMIP/Total [%]', ...
                    prctile(yalmip_frac,50), prctile(yalmip_frac,95), max(yalmip_frac));
            end

            % Row 7: Non-solver overhead as % of total (step-wise, percentiles of the ratio)
            if isfield(L, 't_ctrl_wall') && isfield(L, 'solver_time')
                both_ok = act & isfinite(L.t_ctrl_wall) & isfinite(L.solver_time) & L.t_ctrl_wall > 0;
                nonsolver_frac = 100 * (L.t_ctrl_wall(both_ok) - L.solver_time(both_ok)) ./ L.t_ctrl_wall(both_ok);
                fprintf('%-6s  %-22s  %9.2f  %9.2f  %9.2f\n', '', 'Non-solver/Total [%]', ...
                    prctile(nonsolver_frac,50), prctile(nonsolver_frac,95), max(nonsolver_frac));
            end

            fprintf('%s\n', sep);
        end
        fprintf('%s\n', SEP);
        fprintf('\n');
        fprintf('\n');

        % % Budget check: flag if any variant ever exceeds the 1-s sampling period
        % Tstep_ms = 1e3 * cfg.Tstep;
        % fprintf('--- Budget check (sampling period Tstep = %.0f ms) ---\n', Tstep_ms);
        % for v = variants
        %     vid  = v{1};
        %     L    = R.(vid).log;
        %     m    = M.(vid);
        %     vals = 1e3 * L.t_ctrl_wall(m.active);
        %     vals = vals(isfinite(vals));
        %     n_over = sum(vals > Tstep_ms);
        %     fprintf('  Variant %s: t_max = %.1f ms, steps exceeding budget = %d / %d (%.1f%%)\n', ...
        %         vid, max(vals), n_over, numel(vals), 100*n_over/max(numel(vals),1));
        % end
        % fprintf('\n');
    end
    


    %% =========================================================================
    %  SECTION 3: Incumbent quality (Variant A only)
    %% =========================================================================
    fprintf('--- TABLE incumbent_A: Variant~A timeout-incumbent diagnostics over the nominal WLTC cycle. ---\n');
    L_A = R.A.log;
    m_A = M.A;
    gap     = L_A.mip_gap;
    gap_inc = gap(m_A.inc);
    gap_inc = gap_inc(isfinite(gap_inc));

    % --- Panel 1: MIP gap distribution ---
    fprintf('%s\n', SEP);
    fprintf('  Incumbent MIP gap distribution\n');
    fprintf('%s\n', sep);
    fprintf('%-14s %10s %10s\n', 'Gap bin', 'Count', 'Share[%]');
    fprintf('%s\n', sep);
    if ~isempty(gap_inc)
        n_inc  = length(gap_inc);
        edges  = [0 1 5 10 50 100] / 100;
        labels = {'[0,1)%', '[1,5)%', '[5,10)%', '[10,50)%', '[50,100)%'};
        for i = 1:length(labels)
            n = sum(gap_inc >= edges(i) & gap_inc < edges(i+1));
            fprintf('%-14s %10d %10.1f\n', labels{i}, n, 100*n/n_inc);
        end
        fprintf('%s\n', sep);
        fprintf('%-14s %10.3f\n', 'Median gap [%]', median(gap_inc)*100);
        fprintf('%-14s %10.2f\n', 'Maximum gap [%]', max(gap_inc)*100);
    else
        fprintf('No finite incumbent-gap entries found for Variant A.\n');
    end

    % --- Panel 2: Requested power by solve class ---
    fprintf('%s\n', sep);
    fprintf('  Requested power by Variant A solve class\n');
    fprintf('%s\n', sep);
    fprintf('%-14s %10s %10s\n', 'Class', 'Mean [W]', 'Median [W]');
    fprintf('%s\n', sep);
    p_req_A  = abs(L_A.p_pack_req);
    classes  = {'Opt.', 'TO+Inc.', 'Fail'};
    masks_A  = {m_A.opt, m_A.inc, m_A.hf};
    for i = 1:3
        vals = p_req_A(masks_A{i});
        if isempty(vals)
            fprintf('%-14s %10s %10s\n', classes{i}, '-', '-');
        else
            fprintf('%-14s %10.1f %10.1f\n', classes{i}, mean(vals), median(vals));
        end
    end
    fprintf('%s\n', SEP);
    fprintf('\n');
    fprintf('\n');


    %% =========================================================================
    %  SECTION 4: Burst persistence evidence (Variant A)
    %
    %  These statistics support the manuscript claim that non-certified bursts
    %  persist because the operating regime changes slowly: a step that is hard
    %  to certify tends to be followed by equally hard steps.
    %% =========================================================================
    fprintf('--- TABLE clustering_evidence: Evidence for burst persistence of non-certified steps in Variant~A. ---\n');

    % --- Panel 1: Burst statistics ---
    bad_idx = find(m_A.inc | m_A.hf);
    fprintf('%s\n', SEP);
    fprintf('  Non-certified burst statistics (Variant A)\n');
    fprintf('%s\n', sep);
    if length(bad_idx) > 1
        gaps       = diff(bad_idx);
        tmp        = find(gaps > 1);
        breaks     = [0; tmp(:); length(bad_idx)];
        burst_lens = diff(breaks);
        fprintf('%-38s %6d\n', 'Total bursts',                  length(burst_lens));
        fprintf('%-38s %6d\n', 'Bursts >= 5 consecutive steps', sum(burst_lens >= 5));
        fprintf('%-38s %6d\n', 'Maximum burst length [steps]',  max(burst_lens));
    else
        fprintf('  Fewer than 2 non-certified steps; burst analysis skipped.\n');
    end

    % --- Panel 2: Temporal-persistence statistics ---
    p_req_all = L_A.p_pack_req;
    p_req_act = p_req_all(m_A.active);
    p_req_act = p_req_act(:);   % ensure column vector for corr()

    % Lag-1 autocorrelations over the active-step sequence
    ac_p    = corr(p_req_act(1:end-1),      p_req_act(2:end));
    ac_absp = corr(abs(p_req_act(1:end-1)), abs(p_req_act(2:end)));

    % Median maximum per-cell SOC change over one active step
    % z_cell_vec is n_cells x (T+1); act_idx are 1-based step indices within T
    z_A     = L_A.z_cell_vec;
    act_idx = find(m_A.active);
    dz      = abs(z_A(:, act_idx + 1) - z_A(:, act_idx));   % n_cells x n_active
    max_dz_per_step = max(dz, [], 1) * 100;                  % max over cells [pp]
    med_max_dz      = median(max_dz_per_step);

    fprintf('%s\n', sep);
    fprintf('  Cycle temporal-persistence statistics\n');
    fprintf('%s\n', sep);
    fprintf('%-38s %6.3f\n', 'rho_1(p_req)',          ac_p);
    fprintf('%-38s %6.3f\n', 'rho_1(|p_req|)',         ac_absp);
    fprintf('%-38s %6.4f\n', 'med. max dSOC/step [pp]', med_max_dz);
    fprintf('%s\n', SEP);
    fprintf('\n');
    fprintf('\n');



    %% =========================================================================
    %  SECTION 7: Figure suggestions
    %  Run these figure scripts after this analysis to regenerate all
    %  Section VI-A.1 figures from the current result file.
    %% =========================================================================
    fprintf('=== Figures to run for Section VI-A.1 ===\n');
    fprintf('%s\n', sep);
    fprintf('  1. figureGeneration/figure_solve_time_cdf.m\n');
    fprintf('     Empirical CDF of per-step solver times (A vs D),\n');
    fprintf('     with the solver time-limit marked.\n\n');
    fprintf('  2. figureGeneration/figure_power_solveclass.m\n');
    fprintf('     Requested pack power and baseline-controller solve class\n');
    fprintf('     over the WLTC cycle (manuscript Fig. 3).\n\n');
    fprintf('  Or run figureGeneration/generate_all_manuscript_figures.m to\n');
    fprintf('  regenerate all three manuscript figures in one call.\n');
    fprintf('%s\n\n', sep);

    fprintf('\n=== Analysis complete (VI-A.1) ===\n');

catch ME
    fprintf(2, '\nERROR while running %s:\n%s\n', mfilename, ...
        getReport(ME, 'extended', 'hyperlinks', 'off'));
    rethrow(ME);
end

%% Helper: extract logical masks for a variant
%
% Manuscript correspondence (Sections V and VI-A.1):
%   m.active   -> K_act     (active steps, eq:KactDef): p_req(k) != 0
%   m.opt      -> K_opt^f   (eq:KoptDef): certified-optimal steps ("Optimal")
%   m.inc      -> "TO+Inc." steps: timeout with a feasible incumbent
%   m.hf       -> "Fail" steps: no feasible incumbent found
%   m.usable   -> K_usable  (eq:KusableDef): K_act minus Fail steps
%   m.n_act    -> |K_act|
%   m.n_opt    -> |K_opt^f|;  eta_opt (eq:etaOptMetric) = m.n_opt / m.n_act
%   m.n_usable -> |K_usable|
function m = get_masks(L)
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

