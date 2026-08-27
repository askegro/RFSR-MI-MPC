% FILE: mainSimulationRunners/run_robustness_sweeps.m
%
% Produces the data for manuscript Section VI-B (Robustness and Sensitivity
% Studies); the sweep design itself is specified in Section V-E.
% Runs three targeted sweeps in one pass:
%
%   C.2 Heterogeneity sweep : N=20, Np=10, 4 cases
%                             (WLTC_Low, WLTC_Med, WLTC_High, HighPower)
%   C.3 Pack size sweep     : WLTC_Med, Np=10, N=16/20/24
%   C.4 Horizon sweep       : WLTC_Med, N=20, Np=4/6/8/10
%
% Variant A = baseline (sorting off, monotone off).
% Variant D = proposed (sorting on, monotone on).
% Results are keyed as: N{N}_Np{Np}_{case}_{variant}_{weights}
% and saved as Results_robustness_sweeps_YYYYMMDD.mat (today's date stamp).
%
% C.1 Monte Carlo is in lightweightWrappers/run_montecarlo_ics.m.

% Only clear the workspace when run as the entry point, not when called
% from a wrapper script (e.g. run_VC_all) that owns timing variables.
if ~exist('t_pipeline','var')
    clc; close all; clearvars;
end

if exist('yalmip', 'file') == 2, yalmip('clear'); end

%% Reproducible RNG
rng(1337, 'twister');
env_base      = struct();
env_base.sSOH = RandStream('Threefry', 'Seed', 42);
env_base.sSOC = RandStream('Threefry', 'Seed', 4242);



%% Paths
rootDir = initProjectPaths(mfilename('fullpath'));

fprintf('\n>>> Entering run_robustness_sweeps\n');



%% Base config — all sweeps modify a copy of this
cfg_base = default_config();



%% Sweep dimensions

% Heterogeneity / drive-cycle cases
rob_cases = struct( ...
    'id',       {'WLTC_Low',  'WLTC_Med',  'WLTC_High', 'HighPower'}, ...
    'soc_std',  {0.0005,       0.001,       0.01,        0.001     }, ...
    'soh_std',  {0.005,        0.01,        0.015,        0.005     }, ...
    'dc_type',  {'wltc',       'wltc',      'wltc',       'constant'}, ...
    'P_const',  {NaN,          NaN,         NaN,          200.0     }, ...
    'simSteps', {1800,         1800,        1800,         600       }  ...
);

% Pack sizes
pack_sizes = struct( ...
    'id', {'N16', 'N20', 'N24'}, ...
    'Ns', {16,    20,    24   }  ...
);

% Prediction horizons
horizons = struct( ...
    'id',        {'Np4', 'Np6', 'Np8', 'Np10'}, ...
    'Np', {4,     6,     8,     10     }  ...
);

% Reference weight label — used only for result key naming (suffix '_balanced').
% The C.5 weight sweep has been removed; ranking weights are derived from the
% MPC objective (gradient-exact ranking) and are not independently tunable.
sw_ref = struct('id', 'balanced');

% Index of the reference / default settings within each dimension
REF_CASE = 2;   % WLTC_Med
REF_PACK = 2;   % N=20
REF_HOR  = 4;   % Np=10

% Variants — A is the baseline, D is the full method
rob_variants = struct( ...
    'id',              {'A',   'D'  }, ...
    'enable_sorting',  {false, true }, ...
    'enable_monotone', {false, true }  ...
);



%% Results container
RobResults = struct();



%% ========================================================================
%  Build flat job list across all three sweeps, then run in parallel.
%
%  Each element of `jobs` is a plain struct (no handles, no objects) that
%  fully describes one simulation: pack size, horizon, drive-cycle case,
%  and variant flags.  The parfor worker builds every heavy object (models,
%  constants, YALMIP optimizer) from scratch so no shared state is needed.
%
%  HOW TO CONTROL WORKER COUNT
%    Before running this script call, e.g.:  parpool(6)
%    If no pool exists, MATLAB starts one automatically (uses all cores).
%    Rule of thumb: N_workers = floor(physical_cores * 0.75).
%    Each worker uses 1 Gurobi thread (set inside run_one).
% =========================================================================

Ns_ref = pack_sizes(REF_PACK).Ns;
Np_ref = horizons(REF_HOR).Np;
rc_ref = rob_cases(REF_CASE);

jobs = struct('Ns',{}, 'Np',{}, 'case_id',{}, ...
              'soc_std',{}, 'soh_std',{}, 'dc_type',{}, ...
              'P_const',{}, 'simSteps',{}, ...
              'enable_sorting',{}, 'enable_monotone',{}, ...
              'variant_id',{}, 'weights_id',{}, 'key',{});
ji = 0;

% --- Sweep 1: Heterogeneity (N=20, Np=10, vary case, both variants) ---
for c = 1:numel(rob_cases)
    for v = 1:numel(rob_variants)
        ji = ji + 1;
        jobs(ji).Ns              = Ns_ref;
        jobs(ji).Np              = Np_ref;
        jobs(ji).case_id         = rob_cases(c).id;
        jobs(ji).soc_std         = rob_cases(c).soc_std;
        jobs(ji).soh_std         = rob_cases(c).soh_std;
        jobs(ji).dc_type         = rob_cases(c).dc_type;
        jobs(ji).P_const         = rob_cases(c).P_const;
        jobs(ji).simSteps        = rob_cases(c).simSteps;
        jobs(ji).enable_sorting  = rob_variants(v).enable_sorting;
        jobs(ji).enable_monotone = rob_variants(v).enable_monotone;
        jobs(ji).variant_id      = rob_variants(v).id;
        jobs(ji).weights_id      = sw_ref.id;
        jobs(ji).key             = sprintf('N%d_Np%d_%s_%s_%s', ...
                                       Ns_ref, Np_ref, rob_cases(c).id, ...
                                       rob_variants(v).id, sw_ref.id);
    end
end

% --- Sweep 2: Pack size (vary N, fix WLTC_Med, Np=10, skip N=20) ---
for p = 1:numel(pack_sizes)
    if pack_sizes(p).Ns == Ns_ref, continue; end
    for v = 1:numel(rob_variants)
        ji = ji + 1;
        jobs(ji).Ns              = pack_sizes(p).Ns;
        jobs(ji).Np              = Np_ref;
        jobs(ji).case_id         = rc_ref.id;
        jobs(ji).soc_std         = rc_ref.soc_std;
        jobs(ji).soh_std         = rc_ref.soh_std;
        jobs(ji).dc_type         = rc_ref.dc_type;
        jobs(ji).P_const         = rc_ref.P_const;
        jobs(ji).simSteps        = rc_ref.simSteps;
        jobs(ji).enable_sorting  = rob_variants(v).enable_sorting;
        jobs(ji).enable_monotone = rob_variants(v).enable_monotone;
        jobs(ji).variant_id      = rob_variants(v).id;
        jobs(ji).weights_id      = sw_ref.id;
        jobs(ji).key             = sprintf('N%d_Np%d_%s_%s_%s', ...
                                       pack_sizes(p).Ns, Np_ref, rc_ref.id, ...
                                       rob_variants(v).id, sw_ref.id);
    end
end

% --- Sweep 3: Prediction horizon (vary Np, fix WLTC_Med, N=20, skip Np=10) ---
for h = 1:numel(horizons)
    if horizons(h).Np == Np_ref, continue; end
    for v = 1:numel(rob_variants)
        ji = ji + 1;
        jobs(ji).Ns              = Ns_ref;
        jobs(ji).Np              = horizons(h).Np;
        jobs(ji).case_id         = rc_ref.id;
        jobs(ji).soc_std         = rc_ref.soc_std;
        jobs(ji).soh_std         = rc_ref.soh_std;
        jobs(ji).dc_type         = rc_ref.dc_type;
        jobs(ji).P_const         = rc_ref.P_const;
        jobs(ji).simSteps        = rc_ref.simSteps;
        jobs(ji).enable_sorting  = rob_variants(v).enable_sorting;
        jobs(ji).enable_monotone = rob_variants(v).enable_monotone;
        jobs(ji).variant_id      = rob_variants(v).id;
        jobs(ji).weights_id      = sw_ref.id;
        jobs(ji).key             = sprintf('N%d_Np%d_%s_%s_%s', ...
                                       Ns_ref, horizons(h).Np, rc_ref.id, ...
                                       rob_variants(v).id, sw_ref.id);
    end
end

n_jobs = ji;
fprintf('\nTotal jobs: %d  (workers: %d)  — starting parfor...\n\n', ...
        n_jobs, max(1, parpool_size_safe()));



%% ========================================================================
%  Execute all jobs in parallel
% =========================================================================
results_cells = cell(1, n_jobs);
parfor ji = 1:n_jobs   %#ok<FVAL>
    fprintf('[VC_robustness] Job %3d / %d  starting: %s\n', ji, n_jobs, jobs(ji).key);
    results_cells{ji} = run_one(jobs(ji), cfg_base);
    fprintf('[VC_robustness] Job %3d / %d  done:     %s\n', ji, n_jobs, jobs(ji).key);
end



%% ========================================================================
%  Assemble RobResults
% =========================================================================
for ji = 1:n_jobs
    r   = results_cells{ji};
    key = r.key;
    RobResults.(key).log     = r.log;
    RobResults.(key).cfg     = r.cfg;
    RobResults.(key).case_id = r.case_id;
    RobResults.(key).variant = r.variant_id;
    RobResults.(key).Ns      = r.Ns;
    RobResults.(key).Np      = r.Np;
    RobResults.(key).weights = r.weights_id;
end



%% ========================================================================
%  Save
% =========================================================================
resultsDir = ensureResultsDir(rootDir);
out_name = fullfile(resultsDir, "Results_robustness_sweeps_" + string(datetime('now','Format','yyyyMMdd')) + ".mat");
save(out_name, 'RobResults', 'rob_cases', 'pack_sizes', ...
     'horizons', 'rob_variants', 'cfg_base');
fprintf('\nAll sweeps complete. Saved %s\n', out_name);



%%% =========================================================================
%  Local helpers
% =========================================================================

% =========================================================================
%  Helper: run one job from spec, fully self-contained for parfor safety.
%  Builds models, constants, and YALMIP optimizer from scratch.
%  Uses 1 Gurobi thread — one per parfor worker.
% =========================================================================
function result = run_one(spec, cfg_base)
% RUN_ONE  Build from scratch and run one simulation job.
%   spec     — lightweight job descriptor (plain struct, parfor-safe)
%   cfg_base — base config from calling workspace (broadcast, read-only)

    fprintf('  [run_one] %s  (variant=%s, N=%d, Np=%d, sorting=%d, monotone=%d)\n', ...
        spec.key, spec.variant_id, spec.Ns, spec.Np, ...
        spec.enable_sorting, spec.enable_monotone);

    % --- Apply job-specific settings to a fresh copy of cfg ---
    cfg                      = cfg_base;
    cfg.Ns                   = spec.Ns;
    cfg.mpc.Np               = spec.Np;
    % Set variant flags on cfg.mpc so buildConstantsBundle propagates them
    % into constants.cfg automatically (same pattern as tcst_run_variant).
    cfg.mpc.enable_sorting   = spec.enable_sorting;
    cfg.mpc.enable_monotone  = spec.enable_monotone;
    cfg.init.soc_std         = spec.soc_std;
    cfg.init.soh_std         = spec.soh_std;
    cfg.z_cell_init_spread   = spec.soc_std;   % keep aliases in sync
    cfg.SOH_cell_init_spread = spec.soh_std;
    cfg.driveCycle.type      = spec.dc_type;
    cfg.driveCycle.P_const   = spec.P_const;
    cfg.simSteps             = spec.simSteps;
    cfg.solver.threads       = 1;   % one Gurobi thread per parfor worker

    % --- Fresh, fixed-seed RNG streams (match sequential behaviour) ---
    env = struct();
    env.sSOH = RandStream('Threefry', 'Seed', 42);
    env.sSOC = RandStream('Threefry', 'Seed', 4242);

    % --- Build all simulation objects from scratch ---
    [chem, raw]                  = buildChemistry(cfg);
    models                       = buildModels(cfg, chem, raw);
    models.ocv.ocv_pwl           = buildOCVpwl(cfg, chem);
    limits                       = buildLimits(cfg, models, raw.constraints);
    models.pwl.invVpack          = buildInvVpackPWLAuto(limits.v_pack_min, limits.v_pack_max, ...
                                                        cfg.Ns, cfg.limits.inv_vpack_max_err_mV);
    chg                          = buildChargingParams(cfg, chem, limits);
    [states, ~, stateInitID, id2name] = buildStateMachineEnum(cfg);   %#ok<ASGLU>
    sm                           = buildStateMachine(states, stateInitID, ...
                                                      cfg.stateMachineParams, chg, id2name);

    % Adjust simSteps for HighPower case (needs models, so done here)
    if strcmp(spec.dc_type, 'constant') && ~isnan(spec.P_const)
        cfg.simSteps = safe_highpower_steps(spec.P_const, cfg.Ns, ...
                           models.cell, limits, cfg.Tstep, spec.simSteps);
    end

    x0         = buildInitialState(cfg, env, models);
    driveCycle = buildDriveCycle(cfg, limits, models);
    scale      = buildScales(limits, driveCycle);
    solver     = buildSolverOptions(cfg);
    constants  = buildConstantsBundle(cfg, env, chem, raw, models, limits, chg, ...
                                       states, driveCycle, scale, solver);
    constants.enable_sorting  = spec.enable_sorting;
    constants.enable_monotone = spec.enable_monotone;

    yalmip('clear');
    opt = buildOptimizers(constants);

    % --- Simulation loop ---
    Ns     = cfg.Ns;
    zeroNs = zeros(Ns, 1);

    v_OC_fun = constants.models.ocv.func;

    u_plant_k = struct( ...
        'S_cmd',            zeroNs,  ...
        'i_pack_cmd',       0,       ...
        'i_cell_bal',       zeroNs,  ...
        'v_oc',             zeroNs,  ...
        't_days',           0,       ...
        'SOH_cell',         ones(Ns,1), ...
        'ep',               [],      ...
        'FLAG_CycUpdate_k', false,   ...
        'episodeType',      ""       ...
    );

    runtime = buildRuntimeInit(cfg, sm, x0, constants.models);
    log_out = buildLogging(cfg);
    log_out.z_cell_vec(:,1)   = x0.z(:);
    log_out.i_RC_1_vec(:,1)   = x0.iRC1(:);
    log_out.i_RC_2_vec(:,1)   = x0.iRC2(:);
    log_out.T_cell_vec(:,1)   = x0.T(:);
    log_out.EFC_cell_vec(:,1) = x0.EFC(:);
    log_out.SOH_cell_vec(:,1) = x0.SOH(:);

    for k = 1:cfg.simSteps

        x_k    = runtime.x;
        y_prev = runtime.meas;
        t_k    = (k - 1) * cfg.Tstep;
        t_days = t_k / 86400;

        v_OC_k         = v_OC_fun(x_k.z);
        SOH_cell_vec_k = x_k.SOH;

        [reached, cell_idx, soh_value, reason_id] = checkEOL_fast(SOH_cell_vec_k, cfg.EOL);
        if reached
            log_out.eol_reached   = true;
            log_out.eol_cell_idx  = cell_idx;
            log_out.eol_step      = k;
            log_out.eol_soh_value = soh_value;
            log_out.eol_reason    = ternary(reason_id == 1, "any_cell", "pack_mean");
            break;
        end

        [violPacked, lowIdx, vIdx]  = packViolationCode_fast(x_k, y_prev, constants.limits);
        violIdx_k = struct('low', lowIdx, 'v', vIdx);

        smOld              = runtime.sm;
        currentEpisodeType = getEpisodeType(smOld.currentState, smOld.states);
        smNew              = evaluateStateTransitions(smOld, x_k, y_prev, ...
                                 constants, k, violPacked, violIdx_k);
        newEpisodeType     = getEpisodeType(smNew.currentState, smNew.states);
        FLAG_CycUpdate_k   = ~strcmp(newEpisodeType, currentEpisodeType);
        runtime.sm         = smNew;

        [runtime, p_pack_req, u_mpc, J_SOH, J_SOC, ~, ~, J_curt] = ...
            controller_step(runtime, constants, opt, driveCycle, k, v_OC_k);

        u_plant_k.S_cmd            = u_mpc.S;
        u_plant_k.i_pack_cmd       = u_mpc.i_pack_cmd;
        u_plant_k.i_cell_bal       = zeroNs;
        u_plant_k.v_oc             = v_OC_k;
        u_plant_k.t_days           = t_days;
        u_plant_k.SOH_cell         = SOH_cell_vec_k;
        u_plant_k.ep               = runtime.episode;
        u_plant_k.FLAG_CycUpdate_k = FLAG_CycUpdate_k;
        u_plant_k.episodeType      = newEpisodeType;

        [x_new, y_k, ep, ~] = advancePlantState(x_k, u_plant_k, constants);
        if y_k.invalid
            fprintf('[%s/%s] Invalid plant state at step %d — aborting.\n', ...
                    spec.case_id, spec.variant_id, k);
            break;
        end

        [violPacked, lowIdx, ~] = packViolationCode_fast(x_k, y_k, constants.limits);
        runtime.meas = y_k;

        log_out.p_pack_req(k)           = p_pack_req;
        log_out.i_pack_cmd(k)           = u_mpc.i_pack_cmd;
        log_out.v_pack(k)               = u_mpc.v_pack;
        log_out.p_pack_cmd(k)           = u_mpc.i_pack_cmd * u_mpc.v_pack;
        log_out.p_pack_meas(k)          = y_k.p_pack_meas;  % plant-measured: v_pack_meas * i_pack_cmd
        log_out.v_pack_meas(k)          = y_k.v_pack_meas;  % plant-measured pack voltage
        log_out.S(:, k)                 = u_mpc.S;
        log_out.solve_wall(k)           = u_mpc.solve_wall;
        log_out.solver_time(k)          = u_mpc.solver_time;
        log_out.t_ctrl_wall(k)          = u_mpc.controller_wall;   % controller only: prepare + solve + extract
        log_out.t_prepare(k)            = u_mpc.t_prepare;         % ranking, sort, param build
        log_out.t_extract(k)            = u_mpc.t_extract;         % solution unpack + unsort
        log_out.problem_code(k)         = u_mpc.problem_code;
        log_out.fail_type(k)            = string(u_mpc.fail_type);
        log_out.termination_class(k)    = string(u_mpc.termination_class);
        log_out.solution_source(k)      = string(u_mpc.solution_source);
        log_out.solution_usable(k)      = u_mpc.solution_usable;
        log_out.optimality_proven(k)    = u_mpc.optimality_proven;
        log_out.used_incumbent(k)       = u_mpc.used_incumbent;
        log_out.used_fallback(k)        = u_mpc.used_fallback;
        log_out.timeout(k)              = (u_mpc.termination_class == "timeout");
        log_out.infeasible(k)           = (u_mpc.termination_class == "infeasible");
        log_out.hard_fail(k)            = (u_mpc.solution_source == "fallback_failure");
        log_out.non_timeout_fail(k)     = (u_mpc.used_fallback && ...
                                           u_mpc.termination_class ~= "timeout");
        log_out.rest_skip(k)            = (u_mpc.solution_source == "fallback_rest");
        log_out.incumbent_timeout(k)    = (u_mpc.solution_source == "incumbent_timeout");
        log_out.mip_gap(k)              = u_mpc.mip_gap;
        log_out.obj_val(k)              = u_mpc.obj_val;
        log_out.node_count(k)           = u_mpc.node_count;
        log_out.best_bound(k)           = u_mpc.best_bound;
        log_out.incumbent_obj(k)        = u_mpc.incumbent_obj;
        log_out.n_engaged(k)            = u_mpc.n_engaged;
        if isfield(u_mpc, 'n_engaged_min_feasible')
            log_out.n_engaged_min_feasible(k) = u_mpc.n_engaged_min_feasible;
            log_out.Ns_min_stage_first(k)     = u_mpc.n_engaged_min_feasible;
        end
        log_out.slack_mag(k)            = u_mpc.lambda_slack;
        log_out.status_str(k)           = string(u_mpc.status_str);

        % Unweighted normalized components returned by the optimizer.
        log_out.J_SOH(k)  = J_SOH;
        log_out.J_SOC(k)  = J_SOC;
        log_out.J_curt(k) = J_curt;
        
        % True weighted objective contributions.
        [J_obj, J_SOH_w, J_SOC_w, J_curt_w] = ...
            computeWeightedObjective(J_SOH, J_SOC, J_curt, constants.cfg);
        
        log_out.J_SOH_weighted(k)  = J_SOH_w;
        log_out.J_SOC_weighted(k)  = J_SOC_w;
        log_out.J_curt_weighted(k) = J_curt_w;
        log_out.J_obj(k)           = J_obj;
        
        % Diagnostic only; not the optimizer objective.
        log_out.J_sum_unweighted(k) = J_SOH + J_SOC + J_curt;
        
        % Backward-compatible aliases.
        log_out.J_SOH_raw(k)  = J_SOH;
        log_out.J_SOC_raw(k)  = J_SOC;
        log_out.J_curt_raw(k) = J_curt;

        log_out.dzT(k)                  = u_mpc.dzT;
        log_out.dzT_max(k)              = u_mpc.dzT_max;
        log_out.score.rho_v(:, k)       = u_mpc.score.rho_v;
        log_out.score.rho_SOC(:, k)     = u_mpc.score.rho_SOC;
        log_out.score.rho_SOH(:, k)     = u_mpc.score.rho_SOH;
        log_out.score.raw(:, k)         = u_mpc.score.raw;
        log_out.score.smoothed(:, k)    = u_mpc.score.smoothed;
        log_out.rank_idx(:, k)          = u_mpc.rank_idx(:);
        if constants.enable_sorting
            log_out.exact_prefix(k) = u_mpc.exact_prefix;
            log_out.prefix_break(k) = u_mpc.prefix_break;
        end
        if k == 1
            log_out.switch_events(k) = 0;  % no prior state; zero switches by definition
        else
            log_out.switch_events(k) = countSwitchEvents(log_out.S(:,k-1), u_mpc.S);
        end
        log_out.v_cell_meas_vec(:, k)    = y_k.v_cell_meas_vec;
        log_out.p_cell_loss_tot_vec(:,k) = y_k.p_cell_loss_tot_vec;
        log_out.z_cell_vec(:, k+1)       = x_new.z;
        log_out.i_RC_1_vec(:, k+1)       = x_new.iRC1;
        log_out.i_RC_2_vec(:, k+1)       = x_new.iRC2;
        log_out.T_cell_vec(:, k+1)       = x_new.T;
        log_out.EFC_cell_vec(:, k+1)     = x_new.EFC;
        log_out.SOH_cell_vec(:, k+1)     = x_new.SOH;
        log_out.state(k)                 = double(smNew.currentState);
        log_out.viol_packed(k)           = violPacked;
        log_out.viol_idx(k)              = lowIdx;

        if cfg.LOGGING.progress_every_steps > 0 && ...
                mod(k, cfg.LOGGING.progress_every_steps) == 0
            fprintf('  [%s/%s] Step %4d/%d | %-18s | z=[%.3f,%.3f]\n', ...
                spec.case_id, spec.variant_id, k, cfg.simSteps, ...
                string(smNew.name), min(x_k.z), max(x_k.z));
        end

        runtime.x               = x_new;
        runtime.prev.S          = u_mpc.S;
        runtime.prev.i_pack_cmd = u_mpc.i_pack_cmd;
        runtime.episode         = ep;

    end % k loop

    result.log        = log_out;
    result.cfg        = cfg;
    result.case_id    = spec.case_id;
    result.variant_id = spec.variant_id;
    result.Ns         = spec.Ns;
    result.Np         = spec.Np;
    result.weights_id = spec.weights_id;
    result.key        = spec.key;
end % run_one



% ----------------------------------------------------------------------- %
function steps = safe_highpower_steps(P_const, Ns, cell_model, limits, Tstep, max_steps)
% SAFE_HIGHPOWER_STEPS  Conservative step count before SOC floor is hit.
%
%   Estimates how many steps at constant P_const the pack can sustain
%   before any cell hits z_cell_min. Returns min(estimate, max_steps).
%
%   Conservative: assumes all cells start at mean SOC, all engaged.
    z_init       = limits.z_cell_max * 0.9;   % conservative starting SOC
    Q_As         = cell_model.Q_cell_nom_As;
    v_nom        = cell_model.v_cell_nom;
    i_per_cell   = P_const / (v_nom * Ns);    % rough current per cell
    dz_per_step  = i_per_cell * Tstep / Q_As;
    z_floor      = limits.z_cell_min + 0.02;  % small margin
    headroom     = z_init - z_floor;
    if dz_per_step <= 0
        steps = max_steps;
    else
        steps = min(floor(headroom / dz_per_step), max_steps);
    end
    steps = max(steps, 100);   % always run at least 100 steps
end



% ----------------------------------------------------------------------- %
function n = parpool_size_safe()
% PARPOOL_SIZE_SAFE  Returns current pool size, or 0 if no pool is open.
    try
        p = gcp('nocreate');
        if isempty(p), n = 0; else, n = p.NumWorkers; end
    catch
        n = 0;
    end
end



                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              