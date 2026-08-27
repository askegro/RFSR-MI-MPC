function result = tcst_run_variant(opts)
% TCST_RUN_VARIANT  Run one closed-loop simulation variant as a callable function.
%
% Options (all optional, fields of opts):
%   seed, sort_seed, soc_seed       RNG seeds
%   enable_sorting, enable_monotone variant switches
%   timeLimit, Ns, Np        model/solver overrides
%   Tsimtotal, simSteps             simulation-length overrides
%   progress_every_steps            progress-print cadence
%   variant_id                      label stored in output
%
% Output:
%   result.log, result.constants, result.cfg, result.runtime, result.variant

    if nargin < 1 || isempty(opts), opts = struct(); end

    rootDir = initProjectPaths(mfilename('fullpath')); %#ok<NASGU>

    task = getCurrentTask();
    worker_id = ternary(isempty(task), 0, task.ID);

    if ~isfield(opts,'seed'),            opts.seed = 1337; end
    if ~isfield(opts,'sort_seed'),       opts.sort_seed = 42; end
    if ~isfield(opts,'soc_seed'),        opts.soc_seed = 4242; end
    if ~isfield(opts,'enable_sorting'),  opts.enable_sorting = true; end
    if ~isfield(opts,'enable_monotone'), opts.enable_monotone = true; end
    if ~isfield(opts,'variant_id'),      opts.variant_id = 'custom'; end

    env = prepareSimulationEnvironment(struct( ...
        'seed', opts.seed, ...
        'sort_seed', opts.sort_seed, ...
        'soc_seed', opts.soc_seed, ...
        'clear_yalmip', true, ...
        'print_banner', false));

    cfg = default_config();
    if isfield(opts,'Ns'), cfg.Ns = opts.Ns; end
    if isfield(opts,'Np'), cfg.mpc.Np = opts.Np; end
    if isfield(opts,'timeLimit'), cfg.timeLimit = opts.timeLimit; end
    if isfield(opts,'Tsimtotal')
        cfg.Tsimtotal = opts.Tsimtotal;
        cfg.simSteps  = round(cfg.Tsimtotal / cfg.Tstep);
    end
    if isfield(opts,'simSteps')
        cfg.simSteps  = opts.simSteps;
        cfg.Tsimtotal = cfg.simSteps * cfg.Tstep;
    end
    if isfield(opts,'progress_every_steps')
        cfg.LOGGING.progress_every_steps = opts.progress_every_steps;
    end
    % Thread count per Gurobi solve. Set to 1 inside parfor workers.
    if isfield(opts,'gurobi_threads')
        cfg.solver.threads = opts.gurobi_threads;
    end

    % Set variant flags on cfg before building the stack so that
    % buildConstantsBundle propagates them into constants automatically.
    % This avoids a second buildOptimizers call on stale constants.
    cfg.mpc.enable_sorting  = opts.enable_sorting;
    cfg.mpc.enable_monotone = opts.enable_monotone;

    sim                  = buildSimulationStack(cfg, env, struct('build_optimizers', false));
    chem                 = sim.chem; %#ok<NASGU>
    raw                  = sim.raw; %#ok<NASGU>
    models               = sim.models; %#ok<NASGU>
    limits               = sim.limits; %#ok<NASGU>
    chg                  = sim.chg; %#ok<NASGU>
    driveCycle           = sim.driveCycle;
    states               = sim.states; %#ok<NASGU>
    stateInitID          = sim.stateInitID; %#ok<NASGU>
    id2name              = sim.id2name; %#ok<NASGU>
    sm                   = sim.sm; %#ok<NASGU>
    x0                   = sim.x0;
    scale                = sim.scale; %#ok<NASGU>
    solver               = sim.solver; %#ok<NASGU>
    constants            = sim.constants;   % flags already set via cfg.mpc

    runtime = sim.runtime;
    log     = sim.log;
    log.z_cell_vec(:,1)   = x0.z(:);
    log.i_RC_1_vec(:,1)   = x0.iRC1(:);
    log.i_RC_2_vec(:,1)   = x0.iRC2(:);
    log.T_cell_vec(:,1)   = x0.T(:);
    log.EFC_cell_vec(:,1) = x0.EFC(:);
    log.SOH_cell_vec(:,1) = x0.SOH(:);

    zeroNs       = zeros(cfg.Ns,1);
    onesNs       = ones(cfg.Ns,1);
    v_OC_anonFun = constants.models.ocv.func;
    optCompiled  = buildOptimizers(constants);

    % Warmup: one unrecorded controller_step to populate YALMIP's compiled-
    % optimizer cache before the measured loop begins. Uses the initial state
    % so the problem structure matches the real run. Runtime is not updated
    % (MATLAB structs are pass-by-value).
    controller_step(runtime, constants, optCompiled, driveCycle, 1, v_OC_anonFun(x0.z)); %#ok<NASGU>

    u_plant_k = struct('i_cell', zeroNs, 'i_cell_bal', zeroNs, ...
        'v_oc', zeroNs, 't_days', 0, 'SOH_cell', onesNs, ...
        'ep', runtime.episode, 'FLAG_CycUpdate_k', false);

    for k = 1:cfg.simSteps
        x_k            = runtime.x;
        y_prev         = runtime.meas;
        t_current      = (k-1) * cfg.Tstep;
        t_cal_days_k   = t_current / 86400;
        v_OC_k         = v_OC_anonFun(x_k.z);
        SOH_cell_vec_k = x_k.SOH;

        [reached, cell_idx, soh_value, reason_id] = checkEOL_fast(SOH_cell_vec_k, cfg.EOL);
        if reached
            log.eol_reached   = true;
            log.eol_cell_idx  = cell_idx;
            log.eol_step      = k;
            log.eol_soh_value = soh_value;
            log.eol_reason    = ternary(reason_id==1, "any_cell", "pack_mean");
            break;
        end

        t_step = tic;   % controller_wall: state machine + solver + plant advance

        [violPacked, lowIdx, vIdx] = packViolationCode_fast(x_k, y_prev, constants.limits);
        violIdx.low = lowIdx; violIdx.v = vIdx;

        smOld              = runtime.sm;
        currentEpisodeType = getEpisodeType(smOld.currentState, smOld.states);
        smNew              = evaluateStateTransitions(smOld, x_k, y_prev, constants, k, violPacked, violIdx);
        newEpisodeType     = getEpisodeType(smNew.currentState, smNew.states);
        FLAG_CycUpdate_k   = ~strcmp(newEpisodeType, currentEpisodeType);
        runtime.sm         = smNew;

        [runtime, p_pack_req, u_mpc, J_SOH, J_SOC, ~, ~, J_curt] = ... %#ok<ASGLU>
            controller_step(runtime, constants, optCompiled, driveCycle, k, v_OC_k);

        u_plant_k.S_cmd            = u_mpc.S;
        u_plant_k.i_pack_cmd       = u_mpc.i_pack_cmd;
        u_plant_k.i_cell_bal       = zeroNs;
        u_plant_k.v_oc             = v_OC_k;
        u_plant_k.t_days           = t_cal_days_k;
        u_plant_k.SOH_cell         = SOH_cell_vec_k;
        u_plant_k.ep               = runtime.episode;
        u_plant_k.FLAG_CycUpdate_k = FLAG_CycUpdate_k;
        u_plant_k.episodeType      = newEpisodeType;

        [x_new, y_k, ep, ~] = advancePlantState(x_k, u_plant_k, constants);
        if y_k.invalid
            fprintf('\n*** TERMINATING: invalid plant state at step %d ***\n', k);
            break;
        end

        [violPacked, lowIdx, ~] = packViolationCode_fast(x_k, y_k, constants.limits);
        runtime.meas = y_k;

        log.controller_wall(k)   = toc(t_step);   % legacy: full step (state machine + controller + plant)
        log.t_step_wall(k)       = log.controller_wall(k);
        log.t_ctrl_wall(k)       = u_mpc.controller_wall;   % controller only: prepare + solve + extract
        log.t_prepare(k)         = u_mpc.t_prepare;         % ranking, sort, param build
        log.t_extract(k)         = u_mpc.t_extract;         % solution unpack + unsort

        log.p_pack_req(k)        = p_pack_req;
        log.i_pack_cmd(k)        = u_mpc.i_pack_cmd;
        log.v_pack(k)            = u_mpc.v_pack;
        log.p_pack_cmd(k)        = u_mpc.i_pack_cmd * u_mpc.v_pack;
        log.p_pack_meas(k)       = y_k.p_pack_meas;  % plant-measured: v_pack_meas * i_pack_cmd
        log.v_pack_meas(k)       = y_k.v_pack_meas;  % plant-measured pack voltage
        log.S(:,k)               = u_mpc.S;
        log.solve_wall(k)        = u_mpc.solve_wall;
        log.solver_time(k)       = u_mpc.solver_time;
        log.problem_code(k)      = u_mpc.problem_code;
        log.fail_type(k)         = string(u_mpc.fail_type);
        log.termination_class(k) = string(u_mpc.termination_class);
        log.solution_source(k)   = string(u_mpc.solution_source);
        log.solution_usable(k)   = u_mpc.solution_usable;
        log.optimality_proven(k) = u_mpc.optimality_proven;
        log.used_incumbent(k)    = u_mpc.used_incumbent;
        log.used_fallback(k)     = u_mpc.used_fallback;
        log.timeout(k)           = (u_mpc.termination_class == "timeout");
        log.infeasible(k)        = (u_mpc.termination_class == "infeasible");
        log.hard_fail(k)         = (u_mpc.solution_source == "fallback_failure");
        log.non_timeout_fail(k)  = (u_mpc.used_fallback && u_mpc.termination_class ~= "timeout");
        log.rest_skip(k)         = (u_mpc.solution_source == "fallback_rest");
        log.incumbent_timeout(k) = (u_mpc.solution_source == "incumbent_timeout");
        log.mip_gap(k)           = u_mpc.mip_gap;
        log.obj_val(k)           = u_mpc.obj_val;
        log.node_count(k)        = u_mpc.node_count;
        log.best_bound(k)        = u_mpc.best_bound;
        log.incumbent_obj(k)     = u_mpc.incumbent_obj;
        log.n_engaged(k)         = u_mpc.n_engaged;
        if isfield(u_mpc, 'n_engaged_min_feasible')
            log.n_engaged_min_feasible(k) = u_mpc.n_engaged_min_feasible;
            log.Ns_min_stage_first(k)     = u_mpc.n_engaged_min_feasible;
        end
        if isfield(u_mpc, 'debug') && isfield(u_mpc.debug, 'discharge_params')
            dbg = u_mpc.debug.discharge_params;
            log.dbg_delta_required_first(k)          = dbg.delta_required(1);
            log.dbg_curtailment_budget_viol_first(k) = dbg.curtailment_budget_violation(1);
            log.dbg_i_pack_upper_first(k)            = dbg.i_pack_upper(1);
            log.dbg_lambda_slack_max_first(k)        = dbg.lambda_slack_max(1);
        end
        log.slack_mag(k)         = u_mpc.lambda_slack;
        log.status_str(k)        = string(u_mpc.status_str);

        log.J_SOH(k)  = J_SOH;
        log.J_SOC(k)  = J_SOC;
        log.J_curt(k) = J_curt;
        
        [J_obj, J_SOH_w, J_SOC_w, J_curt_w] = ...
            computeWeightedObjective(J_SOH, J_SOC, J_curt, constants.cfg);
        
        log.J_SOH_weighted(k)  = J_SOH_w;
        log.J_SOC_weighted(k)  = J_SOC_w;
        log.J_curt_weighted(k) = J_curt_w;
        log.J_obj(k)           = J_obj;
        
        log.J_sum_unweighted(k) = J_SOH + J_SOC + J_curt;
        
        log.J_SOH_raw(k)  = J_SOH;
        log.J_SOC_raw(k)  = J_SOC;
        log.J_curt_raw(k) = J_curt;

        log.dzT(k)               = u_mpc.dzT;
        log.dzT_max(k)           = u_mpc.dzT_max;
        log.score.rho_v(:,k)   = u_mpc.score.rho_v;
        log.score.rho_SOC(:,k)       = u_mpc.score.rho_SOC;
        log.score.rho_SOH(:,k)       = u_mpc.score.rho_SOH;
        log.score.raw(:,k)       = u_mpc.score.raw;
        log.score.smoothed(:,k)  = u_mpc.score.smoothed;
        log.rank_idx(:,k)        = u_mpc.rank_idx(:);
        if constants.enable_sorting
            log.exact_prefix(k) = u_mpc.exact_prefix;
            log.prefix_break(k) = u_mpc.prefix_break;
        end
        if k == 1
            log.switch_events(k) = 0;  % no prior state; zero switches by definition
        else
            log.switch_events(k) = countSwitchEvents(log.S(:,k-1), u_mpc.S);
        end
        log.v_cell_meas_vec(:,k) = y_k.v_cell_meas_vec;
        log.p_cell_loss_tot_vec(:,k) = y_k.p_cell_loss_tot_vec;
        log.z_cell_vec(:,k+1)    = x_new.z;
        log.i_RC_1_vec(:,k+1)    = x_new.iRC1;
        log.i_RC_2_vec(:,k+1)    = x_new.iRC2;
        log.T_cell_vec(:,k+1)    = x_new.T;
        log.EFC_cell_vec(:,k+1)  = x_new.EFC;
        log.SOH_cell_vec(:,k+1)  = x_new.SOH;
        log.viol_packed(k)       = violPacked;
        log.viol_idx(k)          = lowIdx;
        log.state(k)             = double(smNew.currentState);

        if cfg.LOGGING.progress_every_steps > 0 && mod(k, cfg.LOGGING.progress_every_steps) == 0
            fprintf('Step: %4d/%d | State: %-20s | z_cell=[%.3f,%.3f] | i_pack_cmd=%.3fA | p_pack_req=%.3fW\n', ...
                k, cfg.simSteps, string(smNew.name), min(x_k.z), max(x_k.z), u_mpc.i_pack_cmd, p_pack_req);
        end

        runtime.x               = x_new;
        runtime.prev.S          = u_mpc.S;
        runtime.prev.i_pack_cmd = u_mpc.i_pack_cmd;
        runtime.episode         = ep;
    end

    result = struct();
    result.log       = log;
    result.constants = constants;
    result.cfg       = cfg;
    result.runtime   = runtime;
    result.variant   = opts.variant_id;
    result.worker_id = worker_id;
end
