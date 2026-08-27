% run_samestate_rulebased.m
%
% Neutral-trajectory paired comparison with cycled discharge engagement
% (cyclic-shift variant of the rule-based driver).
%
% Motivation
%   A fixed-physical-order neutral driver would always
%   engages cells 1..m during discharge, which causes progressive SOC
%   imbalance in a direction that is entirely determined by physical cell
%   index.  Over a long run this biases the matched subset toward
%   early-in-cycle steps and can make the terminal SOC-spread constraint
%   infeasible for most of the trajectory.
%
%   This script rotates the discharge engagement set by one cell at the
%   start of each new discharge episode, so that over the full drive cycle
%   all cells share the discharge burden equally.  The controller remains
%   fully memoryless, SOC-agnostic, and SOH-agnostic: the rotation follows
%   physical cell index, with no reference to any quantity that either
%   Variant A or Variant D uses internally.
%
% Cycling convention
%   cycle_offset (0-indexed) increments by 1 at every active discharge
%   step (not just at episode boundaries).  The engaged set at offset d
%   is physical cells  {mod(d,Ns)+1, ..., mod(d+m-1,Ns)+1}  (1-indexed,
%   wrapping modulo Ns).  Over any Ns consecutive discharge steps, each
%   cell is engaged exactly m times, keeping SOC spread bounded.
%   discharge_episode_count is still tracked for summary logging but no
%   longer drives cycle_offset.
%
% Design
%   A deterministic rule-based controller (rule_based_step_cycled) drives
%   the plant.  At every non-rest step k, BOTH reference variants are solved
%   at the same plant state x_k — neither is applied.
%
%     A_ref : Variant A (no sorting, no monotone, 100-s time limit)
%     D_ref : Variant D (sorting on, monotone on,   1-s time limit)
%
% Additional logged fields
%   log.rb_cycle_offset(k)         — cycle_offset value used at step k
%   log.rb_discharge_episode(k)    — which discharge episode step k belongs to
%
% Saved output
%   results/Results_samestate_rulebased_YYYYMMDD.mat
%
% Prerequisites
%   No prior run required.  MATLAB path must be initialised (initProjectPaths).

clc; close all; clearvars;
rootDir = initProjectPaths(mfilename('fullpath'));

fprintf('\n>>> Entering run_samestate_rulebased\n');

env = prepareSimulationEnvironment(struct('print_banner', false));

%% -------------------------------------------------------------------------
%  Build simulation stack (shared plant / constants scaffold)
%% -------------------------------------------------------------------------
cfg       = default_config();
cfg_A_ref = cfg;
cfg_A_ref.timeLimit = 100;    % A_ref: long solver time limit

% Variant D (sorting + monotone, 1-s limit) — D_ref reference
sim           = buildSimulationStack(cfg, env);
constants_D   = sim.constants;
constants_D.enable_sorting  = true;
constants_D.enable_monotone = true;
yalmip('clear');
opt_D = buildOptimizers(constants_D);

% Variant A (no sorting/monotone, 100-s limit) — A_ref reference
solver_A    = buildSolverOptions(cfg_A_ref);
constants_A = buildConstantsBundle(cfg_A_ref, env, sim.chem, sim.raw, sim.models, ...
    sim.limits, sim.chg, sim.states, sim.driveCycle, sim.scale, solver_A);
constants_A.enable_sorting  = false;
constants_A.enable_monotone = false;
yalmip('clear');
opt_A = buildOptimizers(constants_A);

%% -------------------------------------------------------------------------
%  Initialise logging
%% -------------------------------------------------------------------------
driveCycle = sim.driveCycle;
runtime    = sim.runtime;
log_v      = sim.log;
x0         = sim.x0;
states     = sim.states;
Ns         = cfg.Ns;

log_v.z_cell_vec(:,1)   = x0.z(:);
log_v.i_RC_1_vec(:,1)   = x0.iRC1(:);
log_v.i_RC_2_vec(:,1)   = x0.iRC2(:);
log_v.T_cell_vec(:,1)   = x0.T(:);
log_v.EFC_cell_vec(:,1) = x0.EFC(:);
log_v.SOH_cell_vec(:,1) = x0.SOH(:);

% Extra fields for the two reference variants (not in buildLogging)
nSteps = cfg.simSteps;
log_v.ref_A_optimality_proven = false(1, nSteps);
log_v.ref_A_solve_wall        = nan(1, nSteps);
log_v.ref_A_solver_time       = nan(1, nSteps);
log_v.ref_A_mip_gap           = nan(1, nSteps);
log_v.ref_A_obj_val           = nan(1, nSteps);
log_v.ref_A_J_SOH             = nan(1, nSteps);
log_v.ref_A_J_SOC             = nan(1, nSteps);
log_v.ref_A_J_curt            = nan(1, nSteps);
log_v.ref_A_J_SOH_weighted    = nan(1, nSteps);
log_v.ref_A_J_SOC_weighted    = nan(1, nSteps);
log_v.ref_A_J_curt_weighted   = nan(1, nSteps);
log_v.ref_A_J_obj             = nan(1, nSteps);
log_v.ref_A_J_sum_unweighted  = nan(1, nSteps);
log_v.ref_A_slack_mag         = nan(1, nSteps);
log_v.ref_A_n_engaged         = nan(1, nSteps);
log_v.ref_A_node_count        = nan(1, nSteps);
log_v.ref_A_incumbent_timeout = false(1, nSteps);
log_v.ref_A_S                 = nan(Ns, nSteps);
log_v.ref_A_solution_usable   = false(1, nSteps);
log_v.ref_A_problem_code      = nan(1, nSteps);
log_v.ref_A_status_str        = repmat("", 1, nSteps);
log_v.ref_A_termination_class = repmat("", 1, nSteps);

log_v.ref_D_optimality_proven = false(1, nSteps);
log_v.ref_D_solve_wall        = nan(1, nSteps);
log_v.ref_D_solver_time       = nan(1, nSteps);
log_v.ref_D_mip_gap           = nan(1, nSteps);
log_v.ref_D_obj_val           = nan(1, nSteps);
log_v.ref_D_J_SOH             = nan(1, nSteps);
log_v.ref_D_J_SOC             = nan(1, nSteps);
log_v.ref_D_J_curt            = nan(1, nSteps);
log_v.ref_D_J_SOH_weighted    = nan(1, nSteps);
log_v.ref_D_J_SOC_weighted    = nan(1, nSteps);
log_v.ref_D_J_curt_weighted   = nan(1, nSteps);
log_v.ref_D_J_obj             = nan(1, nSteps);
log_v.ref_D_J_sum_unweighted  = nan(1, nSteps);
log_v.ref_D_slack_mag         = nan(1, nSteps);
log_v.ref_D_n_engaged         = nan(1, nSteps);
log_v.ref_D_node_count        = nan(1, nSteps);
log_v.ref_D_incumbent_timeout = false(1, nSteps);
log_v.ref_D_S                 = nan(Ns, nSteps);
log_v.ref_D_solution_usable   = false(1, nSteps);
log_v.ref_D_problem_code      = nan(1, nSteps);
log_v.ref_D_status_str        = repmat("", 1, nSteps);
log_v.ref_D_termination_class = repmat("", 1, nSteps);
log_v.ref_D_rank_idx          = nan(Ns, nSteps);
log_v.ref_D_score_raw         = nan(Ns, nSteps);
log_v.ref_D_score_rho_v       = nan(Ns, nSteps);
log_v.ref_D_score_rho_SOC     = nan(Ns, nSteps);
log_v.ref_D_score_rho_SOH     = nan(Ns, nSteps);

% Plant-driver logging
log_v.rb_i_pack_cmd        = nan(1, nSteps);
log_v.rb_v_pack            = nan(1, nSteps);
log_v.rb_S                 = nan(Ns, nSteps);

% Cycling-specific logging
log_v.rb_cycle_offset      = nan(1, nSteps);   % offset in use at step k
log_v.rb_discharge_episode = zeros(1, nSteps); % which episode number step k is in
log_v.rb_discharge_step    = zeros(1, nSteps); % cumulative discharge step count at step k

zeroNs = zeros(Ns, 1);
onesNs = ones(Ns,  1);
v_OC_anonFun = constants_D.models.ocv.func;

u_plant_k = struct('i_pack_cmd', 0, 'i_cell_bal', zeroNs, 'v_oc', zeroNs, ...
    't_days', 0, 'SOH_cell', onesNs, 'ep', runtime.episode, ...
    'FLAG_CycUpdate_k', false, 'S_cmd', zeroNs, 'episodeType', "");

%% -------------------------------------------------------------------------
%  Cycle-offset tracking
%% -------------------------------------------------------------------------
cycle_offset            = 0;      % 0-indexed, current rotation of discharge set
discharge_episode_count = 0;      % increments at each new discharge episode (summary only)
discharge_step_count    = 0;      % increments at every discharge step; drives cycle_offset
prev_episode_type       = "NONE"; % sentinel: guaranteed != "DISCHARGE" on step 1

% Number of cells engaged by the rule-based driver on each discharge step.
% Set above Ns_min_voltage_safe (13 for this pack) so that the MPC always
% has a feasible cardinality available regardless of cell voltages.
n_engage_rb = 17;

fprintf('\n=== Running neutral-trajectory paired simulation (CYCLED) ===\n');
fprintf('    Plant driver : rule-based, cycled discharge engagement\n');
fprintf('    A_ref        : Variant A, 100-s limit (not applied)\n');
fprintf('    D_ref        : Variant D,   1-s limit (not applied)\n\n');

%% -------------------------------------------------------------------------
%  Main simulation loop
%% -------------------------------------------------------------------------
for k = 1:nSteps

    x_k          = runtime.x;
    y_prev       = runtime.meas;
    t_current    = (k-1) * cfg.Tstep;
    t_cal_days_k = t_current / 86400;
    v_OC_k       = v_OC_anonFun(x_k.z);
    SOH_k        = x_k.SOH;

    % --- EOL check ---
    [reached, cell_idx, soh_val, reason_id] = checkEOL_fast(SOH_k, cfg.EOL);
    if reached
        log_v.eol_reached   = true;
        log_v.eol_cell_idx  = cell_idx;
        log_v.eol_step      = k;
        log_v.eol_soh_value = soh_val;
        log_v.eol_reason    = ternary(reason_id==1, "any_cell", "pack_mean");
        break;
    end

    % --- State machine transition ---
    [violPacked, lowIdx, vIdx] = packViolationCode_fast(x_k, y_prev, constants_D.limits);
    violIdx.low = lowIdx;
    violIdx.v   = vIdx;

    smOld              = runtime.sm;
    currentEpisodeType = getEpisodeType(smOld.currentState, smOld.states);
    smNew              = evaluateStateTransitions(smOld, x_k, y_prev, constants_D, k, violPacked, violIdx);
    newEpisodeType     = getEpisodeType(smNew.currentState, smNew.states);
    FLAG_CycUpdate_k   = ~strcmp(newEpisodeType, currentEpisodeType);
    runtime.sm         = smNew;

    is_rest = is_rest_state(smNew.currentState, smNew.states);

    % --- Offset update: increment every discharge step ---
    % cycle_offset advances by 1 at each active discharge step so that the
    % engaged cell set rotates continuously within and across episodes.
    % discharge_episode_count tracks episode boundaries for summary logging
    % only; it no longer controls cycle_offset.
    if newEpisodeType == "DISCHARGE" && prev_episode_type ~= "DISCHARGE"
        discharge_episode_count = discharge_episode_count + 1;
        if cfg.LOGGING.progress_every_steps > 0
            fprintf('  >> Discharge episode %d started at step %d\n', ...
                discharge_episode_count, k);
        end
    end
    if newEpisodeType == "DISCHARGE"
        discharge_step_count = discharge_step_count + 1;
        cycle_offset = mod(discharge_step_count - 1, Ns);
        % Step 1 → offset 0 → cells {1..m}
        % Step 2 → offset 1 → cells {2..m+1}  ...wraps at Ns
    end
    prev_episode_type = newEpisodeType;  % update EVERY step (incl. rest)

    % --- Rule-based plant command (cycled) ---
    [i_pack_rb, S_rb, p_pack_req, v_pack_rb] = ...
        rule_based_step_cycled(x_k, smNew, constants_D, driveCycle, cycle_offset, n_engage_rb);

    % --- Reference solves (non-applied, both at x_k) ---
    if ~is_rest
        runtime_ref         = runtime;
        runtime_ref.x       = x_k;
        runtime_ref.meas    = y_prev;
        runtime_ref.prev    = runtime.prev;
        runtime_ref.sm      = smNew;
        runtime_ref.mem     = struct('dz_T_max_prev', [], 'score_prev', []);

        % A_ref: unrestricted, 100-s limit
        [~, ~, u_A, J_SOH_A, J_SOC_A, ~, ~, J_curt_A] = ...  %#ok<ASGLU>
            controller_step(runtime_ref, constants_A, opt_A, driveCycle, k, v_OC_k);

        log_v.ref_A_optimality_proven(k) = u_A.optimality_proven;
        log_v.ref_A_solve_wall(k)        = u_A.solve_wall;
        log_v.ref_A_solver_time(k)       = u_A.solver_time;
        log_v.ref_A_mip_gap(k)           = u_A.mip_gap;
        log_v.ref_A_obj_val(k)           = u_A.obj_val;

        log_v.ref_A_J_SOH(k)             = J_SOH_A;
        log_v.ref_A_J_SOC(k)             = J_SOC_A;
        log_v.ref_A_J_curt(k)            = J_curt_A;

        [ref_A_J_obj, ref_A_J_SOH_w, ref_A_J_SOC_w, ref_A_J_curt_w] = ...
            computeWeightedObjective(J_SOH_A, J_SOC_A, J_curt_A, cfg_A_ref);
        
        log_v.ref_A_J_SOH_weighted(k)  = ref_A_J_SOH_w;
        log_v.ref_A_J_SOC_weighted(k)  = ref_A_J_SOC_w;
        log_v.ref_A_J_curt_weighted(k) = ref_A_J_curt_w;
        log_v.ref_A_J_obj(k)           = ref_A_J_obj;
        log_v.ref_A_J_sum_unweighted(k)= J_SOH_A + J_SOC_A + J_curt_A;

        log_v.ref_A_slack_mag(k)         = u_A.lambda_slack;
        log_v.ref_A_n_engaged(k)         = u_A.n_engaged;
        log_v.ref_A_node_count(k)        = u_A.node_count;
        log_v.ref_A_incumbent_timeout(k) = u_A.used_incumbent;
        log_v.ref_A_S(:,k)               = u_A.S;
        log_v.ref_A_solution_usable(k)   = u_A.solution_usable;
        log_v.ref_A_problem_code(k)      = u_A.problem_code;
        log_v.ref_A_status_str(k)        = u_A.status_str;
        log_v.ref_A_termination_class(k) = u_A.termination_class;

        % D_ref: sorting + monotone, 1-s limit
        [~, ~, u_D, J_SOH_D, J_SOC_D, ~, ~, J_curt_D] = ...  %#ok<ASGLU>
            controller_step(runtime_ref, constants_D, opt_D, driveCycle, k, v_OC_k);

        log_v.ref_D_optimality_proven(k) = u_D.optimality_proven;
        log_v.ref_D_solve_wall(k)        = u_D.solve_wall;
        log_v.ref_D_solver_time(k)       = u_D.solver_time;
        log_v.ref_D_mip_gap(k)           = u_D.mip_gap;
        log_v.ref_D_obj_val(k)           = u_D.obj_val;

        log_v.ref_D_J_SOH(k)             = J_SOH_D;
        log_v.ref_D_J_SOC(k)             = J_SOC_D;
        log_v.ref_D_J_curt(k)            = J_curt_D;

        [ref_D_J_obj, ref_D_J_SOH_w, ref_D_J_SOC_w, ref_D_J_curt_w] = ...
            computeWeightedObjective(J_SOH_D, J_SOC_D, J_curt_D, cfg);
        
        log_v.ref_D_J_SOH_weighted(k)  = ref_D_J_SOH_w;
        log_v.ref_D_J_SOC_weighted(k)  = ref_D_J_SOC_w;
        log_v.ref_D_J_curt_weighted(k) = ref_D_J_curt_w;
        log_v.ref_D_J_obj(k)           = ref_D_J_obj;
        log_v.ref_D_J_sum_unweighted(k)= J_SOH_D + J_SOC_D + J_curt_D;        

        log_v.ref_D_slack_mag(k)         = u_D.lambda_slack;
        log_v.ref_D_n_engaged(k)         = u_D.n_engaged;
        log_v.ref_D_node_count(k)        = u_D.node_count;
        log_v.ref_D_incumbent_timeout(k) = u_D.used_incumbent;
        log_v.ref_D_S(:,k)               = u_D.S;
        log_v.ref_D_solution_usable(k)   = u_D.solution_usable;
        log_v.ref_D_problem_code(k)      = u_D.problem_code;
        log_v.ref_D_status_str(k)        = u_D.status_str;
        log_v.ref_D_termination_class(k) = u_D.termination_class;
        log_v.ref_D_rank_idx(:,k)        = u_D.rank_idx;
        log_v.ref_D_score_raw(:,k)       = u_D.score.raw;
        log_v.ref_D_score_rho_v(:,k)     = u_D.score.rho_v;
        log_v.ref_D_score_rho_SOC(:,k)   = u_D.score.rho_SOC;
        log_v.ref_D_score_rho_SOH(:,k)   = u_D.score.rho_SOH;
    end

    % --- Advance plant with rule-based command ---
    u_plant_k.S_cmd            = S_rb;
    u_plant_k.i_pack_cmd       = i_pack_rb;
    u_plant_k.i_cell_bal       = zeroNs;
    u_plant_k.v_oc             = v_OC_k;
    u_plant_k.t_days           = t_cal_days_k;
    u_plant_k.SOH_cell         = SOH_k;
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

    % --- Log plant-driver fields ---
    log_v.p_pack_req(k)  = p_pack_req;
    log_v.i_pack_cmd(k)  = i_pack_rb;
    log_v.v_pack(k)      = v_pack_rb;
    log_v.p_pack_cmd(k)  = i_pack_rb * v_pack_rb;
    log_v.S(:,k)         = S_rb;
    log_v.rest_skip(k)   = is_rest;
    log_v.state(k)       = double(smNew.currentState);
    log_v.viol_packed(k) = violPacked;
    log_v.viol_idx(k)    = lowIdx;

    log_v.rb_i_pack_cmd(k) = i_pack_rb;
    log_v.rb_v_pack(k)     = v_pack_rb;
    log_v.rb_S(:,k)        = S_rb;

    % --- Cycling-specific logging ---
    log_v.rb_cycle_offset(k)      = cycle_offset;
    log_v.rb_discharge_episode(k) = discharge_episode_count;
    log_v.rb_discharge_step(k)    = discharge_step_count;

    % --- Log cell states ---
    log_v.v_cell_meas_vec(:,k)     = y_k.v_cell_meas_vec;
    log_v.p_cell_loss_tot_vec(:,k) = y_k.p_cell_loss_tot_vec;
    log_v.z_cell_vec(:,k+1)        = x_new.z;
    log_v.i_RC_1_vec(:,k+1)        = x_new.iRC1;
    log_v.i_RC_2_vec(:,k+1)        = x_new.iRC2;
    log_v.T_cell_vec(:,k+1)        = x_new.T;
    log_v.EFC_cell_vec(:,k+1)      = x_new.EFC;
    log_v.SOH_cell_vec(:,k+1)      = x_new.SOH;

    if cfg.LOGGING.progress_every_steps > 0 && mod(k, cfg.LOGGING.progress_every_steps) == 0
        fprintf('Step: %4d/%d | State: %-20s | z_cell=[%.3f,%.3f] | i_pack_rb=%.3fA | p_req=%.3fW | offset=%d (dis_step=%d)\n', ...
            k, nSteps, string(smNew.name), min(x_k.z), max(x_k.z), i_pack_rb, p_pack_req, cycle_offset, discharge_step_count);
    end

    runtime.x               = x_new;
    runtime.prev.S          = S_rb;
    runtime.prev.i_pack_cmd = i_pack_rb;
    runtime.episode         = ep;
end

%% -------------------------------------------------------------------------
%  Summary
%% -------------------------------------------------------------------------
fprintf('\nCycled neutral driver summary:\n');
fprintf('  Total discharge episodes : %d\n', discharge_episode_count);
fprintf('  Total discharge steps    : %d\n', discharge_step_count);
fprintf('  Full offset rotations    : %d  (remainder: %d / %d)\n', ...
    floor(discharge_step_count / Ns), mod(discharge_step_count, Ns), Ns);

%% -------------------------------------------------------------------------
%  Save
%% -------------------------------------------------------------------------
Results = struct();
Results.log        = log_v;
Results.cfg        = cfg;
Results.constants  = constants_D;
Results.runtime    = runtime;
Results.note       = [ ...
    'Cycled rule-based driver: discharge engagement set rotated by 1 cell per discharge step. ' ...
    'A_ref (100s) and D_ref (1s) logged as non-applied references at same neutral state. ' ...
    sprintf('Total discharge steps: %d. Total episodes: %d. Full rotations: %d. n_engage_rb: %d.', ...
        discharge_step_count, discharge_episode_count, floor(discharge_step_count / Ns), n_engage_rb)];

resultsDir = ensureResultsDir(rootDir);
out_name = fullfile(resultsDir, "Results_samestate_rulebased_" + ...
    string(datetime('now', 'Format', 'yyyyMMdd')) + ".mat");
save(out_name, 'Results', '-v7.3');
%fprintf('\nSaved