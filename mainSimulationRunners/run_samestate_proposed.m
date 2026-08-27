% FILE: mainSimulationRunners/run_samestate_proposed.m

clc; close all; clearvars;
rootDir = initProjectPaths(mfilename('fullpath'));

fprintf('\n>>> Entering run_samestate_proposed\n');
env = prepareSimulationEnvironment(struct('print_banner', false));

cfg   = default_config();
cfg_A = cfg; cfg_A.timeLimit = 100;

% Variant D stack (sorting + monotone on) — drives the plant
sim         = buildSimulationStack(cfg, env);
constants_D = sim.constants;
constants_D.enable_sorting  = true;
constants_D.enable_monotone = true;
yalmip('clear');
opt_D = buildOptimizers(constants_D);

% Variant A stack (no sorting/monotone, long time limit) — reference only
solver_A    = buildSolverOptions(cfg_A);
constants_A = buildConstantsBundle(cfg_A, env, sim.chem, sim.raw, sim.models, ...
    sim.limits, sim.chg, sim.states, sim.driveCycle, sim.scale, solver_A);
constants_A.enable_sorting  = false;
constants_A.enable_monotone = false;
yalmip('clear');
opt_A = buildOptimizers(constants_A);

driveCycle = sim.driveCycle;
runtime    = sim.runtime;
log_v      = sim.log;
x0         = sim.x0;
states     = sim.states;
log_v.z_cell_vec(:,1)   = x0.z(:);
log_v.i_RC_1_vec(:,1)   = x0.iRC1(:);
log_v.i_RC_2_vec(:,1)   = x0.iRC2(:);
log_v.T_cell_vec(:,1)   = x0.T(:);
log_v.EFC_cell_vec(:,1) = x0.EFC(:);
log_v.SOH_cell_vec(:,1) = x0.SOH(:);

zeroNs = zeros(cfg.Ns,1);
onesNs = ones(cfg.Ns,1);
v_OC_anonFun = constants_D.models.ocv.func;
u_plant_k = struct('i_cell', zeroNs, 'i_cell_bal', zeroNs, 'v_oc', zeroNs, ...
    't_days', 0, 'SOH_cell', onesNs, 'ep', runtime.episode, 'FLAG_CycUpdate_k', false);

fprintf('\n=== Running paired simulation: D applied, A@100s reference ===\n');

for k = 1:cfg.simSteps
    x_k            = runtime.x;
    y_prev         = runtime.meas;
    t_current      = (k-1) * cfg.Tstep;
    t_cal_days_k   = t_current / 86400;
    v_OC_k         = v_OC_anonFun(x_k.z);
    SOH_cell_vec_k = x_k.SOH;

    [reached, cell_idx, soh_value, reason_id] = checkEOL_fast(SOH_cell_vec_k, cfg.EOL);
    if reached
        log_v.eol_reached   = true;
        log_v.eol_cell_idx  = cell_idx;
        log_v.eol_step      = k;
        log_v.eol_soh_value = soh_value;
        log_v.eol_reason    = ternary(reason_id==1, "any_cell", "pack_mean");
        break;
    end

    [violPacked, lowIdx, vIdx] = packViolationCode_fast(x_k, y_prev, constants_D.limits);
    violIdx.low = lowIdx; violIdx.v = vIdx;

    smOld              = runtime.sm;
    currentEpisodeType = getEpisodeType(smOld.currentState, smOld.states);
    smNew              = evaluateStateTransitions(smOld, x_k, y_prev, constants_D, k, violPacked, violIdx);
    newEpisodeType     = getEpisodeType(smNew.currentState, smNew.states);
    FLAG_CycUpdate_k   = ~strcmp(newEpisodeType, currentEpisodeType);
    runtime.sm         = smNew;

    % Applied controller: D.
    [runtime, p_pack_req, u_mpc, J_SOH, J_SOC, J_sw, J_sw_prev, J_curt] = ... %#ok<ASGLU>
        controller_step(runtime, constants_D, opt_D, driveCycle, k, v_OC_k);

    % Reference controller: A at the same state. Do not apply or propagate.
    is_rest = is_rest_state(smNew.currentState, smNew.states);
    if ~is_rest
        runtime_ref = runtime;
        runtime_ref.x = x_k;
        runtime_ref.meas = y_prev;
        runtime_ref.prev = runtime.prev;
        runtime_ref.sm = smNew;
        % Sync D's accumulated terminal-constraint memory so A_ref solves
        % the same problem instance (same dzT_max) as D at this step.
        runtime_ref.mem = struct('dz_T_max_prev', runtime.mem.dz_T_max_prev, ...
                                 'score_prev', []);

        [~, ~, u_ref, J_SOH_ref, J_SOC_ref, J_sw_ref, J_sw_prev_ref, J_curt_ref] = ... %#ok<ASGLU>
            controller_step(runtime_ref, constants_A, opt_A, driveCycle, k, v_OC_k);

        log_v.ref_solve_wall(k)        = u_ref.solve_wall;
        log_v.ref_solver_time(k)       = u_ref.solver_time;
        log_v.ref_optimality_proven(k) = u_ref.optimality_proven;
        log_v.ref_mip_gap(k)           = u_ref.mip_gap;
        log_v.ref_obj_val(k)           = u_ref.obj_val;

        log_v.ref_J_SOH(k)             = J_SOH_ref;
        log_v.ref_J_SOC(k)             = J_SOC_ref;
        log_v.ref_J_sw_prev(k)         = J_sw_prev_ref;
        log_v.ref_J_curt(k)            = J_curt_ref;

        [ref_J_obj, ref_J_SOH_w, ref_J_SOC_w, ref_J_curt_w] = ...
            computeWeightedObjective(J_SOH_ref, J_SOC_ref, J_curt_ref, constants_A.cfg);
        
        log_v.ref_J_SOH_weighted(k)  = ref_J_SOH_w;
        log_v.ref_J_SOC_weighted(k)  = ref_J_SOC_w;
        log_v.ref_J_curt_weighted(k) = ref_J_curt_w;
        log_v.ref_J_obj(k)           = ref_J_obj;
        log_v.ref_J_sum_unweighted(k)= J_SOH_ref + J_SOC_ref + J_curt_ref;        

        log_v.ref_S(:,k)               = u_ref.S;
        log_v.ref_n_engaged(k)         = u_ref.n_engaged;
        log_v.ref_node_count(k)        = u_ref.node_count;
        log_v.ref_incumbent_timeout(k) = u_ref.used_incumbent;
        log_v.ref_slack_mag(k) = u_ref.lambda_slack;        
    end

    u_plant_k.S_cmd            = u_mpc.S;
    u_plant_k.i_pack_cmd       = u_mpc.i_pack_cmd;
    u_plant_k.i_cell_bal       = zeroNs;
    u_plant_k.v_oc             = v_OC_k;
    u_plant_k.t_days           = t_cal_days_k;
    u_plant_k.SOH_cell         = SOH_cell_vec_k;
    u_plant_k.ep               = runtime.episode;
    u_plant_k.FLAG_CycUpdate_k = FLAG_CycUpdate_k;
    u_plant_k.episodeType      = newEpisodeType;

    [x_new, y_k, ep, ~] = advancePlantState(x_k, u_plant_k, constants_D);
    if y_k.invalid
        fprintf('\n*** TERMINATING: invalid plant state at step %d ***\n', k);
        break;
    end

    [violPacked, lowIdx, ~] = packViolationCode_fast(x_k, y_k, constants_D.limits);
    runtime.meas = y_k;

    log_v.p_pack_req(k)        = p_pack_req;
    log_v.i_pack_cmd(k)        = u_mpc.i_pack_cmd;
    log_v.v_pack(k)            = u_mpc.v_pack;
    log_v.p_pack_cmd(k)        = u_mpc.i_pack_cmd * u_mpc.v_pack;
    log_v.p_pack_meas(k)       = y_k.p_pack_meas;  % plant-measured: v_pack_meas * i_pack_cmd
    log_v.v_pack_meas(k)       = y_k.v_pack_meas;  % plant-measured pack voltage
    log_v.S(:,k)               = u_mpc.S;
    log_v.solve_wall(k)        = u_mpc.solve_wall;
    log_v.solver_time(k)       = u_mpc.solver_time;
    log_v.t_ctrl_wall(k)       = u_mpc.controller_wall;   % controller only: prepare + solve + extract
    log_v.t_prepare(k)         = u_mpc.t_prepare;         % ranking, sort, param build
    log_v.t_extract(k)         = u_mpc.t_extract;         % solution unpack + unsort
    log_v.problem_code(k)      = u_mpc.problem_code;
    log_v.fail_type(k)         = string(u_mpc.fail_type);
    log_v.termination_class(k) = string(u_mpc.termination_class);
    log_v.solution_source(k)   = string(u_mpc.solution_source);
    log_v.solution_usable(k)   = u_mpc.solution_usable;
    log_v.optimality_proven(k) = u_mpc.optimality_proven;
    log_v.used_incumbent(k)    = u_mpc.used_incumbent;
    log_v.used_fallback(k)     = u_mpc.used_fallback;
    log_v.timeout(k)           = (u_mpc.termination_class == "timeout");
    log_v.infeasible(k)        = (u_mpc.termination_class == "infeasible");
    log_v.hard_fail(k)         = (u_mpc.solution_source == "fallback_failure");
    log_v.non_timeout_fail(k)  = (u_mpc.used_fallback && u_mpc.termination_class ~= "timeout");
    log_v.rest_skip(k)         = (u_mpc.solution_source == "fallback_rest");
    log_v.incumbent_timeout(k) = (u_mpc.solution_source == "incumbent_timeout");
    log_v.mip_gap(k)           = u_mpc.mip_gap;
    log_v.obj_val(k)           = u_mpc.obj_val;
    log_v.node_count(k)        = u_mpc.node_count;
    log_v.best_bound(k)        = u_mpc.best_bound;
    log_v.incumbent_obj(k)     = u_mpc.incumbent_obj;
    log_v.n_engaged(k)         = u_mpc.n_engaged;
    if isfield(u_mpc, 'n_engaged_min_feasible')
        log_v.n_engaged_min_feasible(k) = u_mpc.n_engaged_min_feasible;
        log_v.Ns_min_stage_first(k)     = u_mpc.n_engaged_min_feasible;
    end
    log_v.slack_mag(k)         = u_mpc.lambda_slack;
    log_v.status_str(k)        = string(u_mpc.status_str);

    log_v.J_SOH(k)             = J_SOH;
    log_v.J_SOC(k)             = J_SOC;
    log_v.J_curt(k)            = J_curt;
    log_v.J_SOH_raw(k)         = J_SOH;
    log_v.J_SOC_raw(k)         = J_SOC;
    log_v.J_curt_raw(k)        = J_curt;

    [J_obj, J_SOH_w, J_SOC_w, J_curt_w] = ...
        computeWeightedObjective(J_SOH, J_SOC, J_curt, constants_D.cfg);
    
    log_v.J_SOH_weighted(k)  = J_SOH_w;
    log_v.J_SOC_weighted(k)  = J_SOC_w;
    log_v.J_curt_weighted(k) = J_curt_w;
    log_v.J_obj(k)           = J_obj;
    log_v.J_sum_unweighted(k)= J_SOH + J_SOC + J_curt;    

    log_v.dzT(k)               = u_mpc.dzT;
    log_v.dzT_max(k)           = u_mpc.dzT_max;
    log_v.score.rho_v(:,k)   = u_mpc.score.rho_v;
    log_v.score.rho_SOC(:,k)       = u_mpc.score.rho_SOC;
    log_v.score.rho_SOH(:,k)       = u_mpc.score.rho_SOH;
    log_v.score.raw(:,k)       = u_mpc.score.raw;
    log_v.score.smoothed(:,k)  = u_mpc.score.smoothed;
    log_v.rank_idx(:,k)        = u_mpc.rank_idx(:);
    if constants_D.enable_sorting
        log_v.exact_prefix(k) = u_mpc.exact_prefix;
        log_v.prefix_break(k) = u_mpc.prefix_break;
    end
    if k == 1
        log_v.switch_events(k) = 0;  % no prior state; zero switches by definition
    else
        log_v.switch_events(k) = countSwitchEvents(log_v.S(:,k-1), u_mpc.S);
    end
    log_v.v_cell_meas_vec(:,k) = y_k.v_cell_meas_vec;
    log_v.p_cell_loss_tot_vec(:,k) = y_k.p_cell_loss_tot_vec;
    log_v.z_cell_vec(:,k+1)    = x_new.z;
    log_v.i_RC_1_vec(:,k+1)    = x_new.iRC1;
    log_v.i_RC_2_vec(:,k+1)    = x_new.iRC2;
    log_v.T_cell_vec(:,k+1)    = x_new.T;
    log_v.EFC_cell_vec(:,k+1)  = x_new.EFC;
    log_v.SOH_cell_vec(:,k+1)  = x_new.SOH;
    log_v.viol_packed(k)       = violPacked;
    log_v.viol_idx(k)          = lowIdx;
    log_v.state(k)             = double(smNew.currentState);

    if cfg.LOGGING.progress_every_steps > 0 && mod(k, cfg.LOGGING.progress_every_steps) == 0
        fprintf('Step: %4d/%d | State: %-20s | z_cell=[%.3f,%.3f] | i_pack_cmd=%.3fA | p_pack_req=%.3fW\n', ...
            k, cfg.simSteps, string(smNew.name), min(x_k.z), max(x_k.z), u_mpc.i_pack_cmd, p_pack_req);
    end

    runtime.x               = x_new;
    runtime.prev.S          = u_mpc.S;
    runtime.prev.i_pack_cmd = u_mpc.i_pack_cmd;
    runtime.episode         = ep;
end

Results = struct();
Results.D.log       = log_v;
Results.D.cfg       = cfg;
Results.D.constants = constants_D;
Results.D.runtime   = runtime;
Results.note        = 'D drives plant; A@100s is logged as ref_* at D states.';

resultsDir = ensureResultsDir(rootDir);
out_name = fullfile(resultsDir, "Results_samestate_proposed_" + string(datetime('now','Format','yyyyMMdd')) + ".mat");
save(out_name, 'Results', '-v7.3');
fprintf('Saved %s\n', out_name);
