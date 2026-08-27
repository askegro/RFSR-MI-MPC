function [runtime, p_pack_req, u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
    controller_step(runtime, constants, opt, profile, k, v_OC_k)
% CONTROLLER_STEP  Execute one MPC controller step.

    % --------------------------------------------------------------------
    %  Build step context and initialise outputs
    %  --------------------------------------------------------------------
    ctx = build_step_context(runtime, constants, profile, k, v_OC_k);
    [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = init_step_outputs(ctx);

    % --------------------------------------------------------------------
    %  Enforced REST-state shortcut
    %  --------------------------------------------------------------------
    if is_rest_state(ctx.currentState, ctx.states)
        u = apply_rest_skip_metadata(u);
        u = apply_zero_command(u, ctx.Ns, false);
        u.i_pack_nominal_from_power = 0;

        p_pack_req  = 0;
        runtime.mem = ctx.mem;
        return;
    end

    % --------------------------------------------------------------------
    %  Prepare active-mode optimizer inputs
    %  (timed: everything from here to end of unpack is online control work)
    %  --------------------------------------------------------------------
    t_ctrl = tic;

    t0 = tic;
    [mode_data, u] = prepare_active_mode(ctx, opt, u);
    u.t_prepare = toc(t0);

    % Store any mode-preparation memory updates immediately.
    runtime.mem = mode_data.mem_after_prepare;
    p_pack_req  = mode_data.p_pack_req;

    % --------------------------------------------------------------------
    %  Warm-start: inject previous binary solution as MIP hint (A_WS only)
    %
    %  Enabled by constants.cfg.WARM_START.enabled = true.
    %  Requires the discharge optimizer to have been built with
    %  ops.usex0 = 1 (warm-start path; not exercised by the shipped runners).
    %
    %  Mechanism:
    %    1. Retrieve previous-step S in physical cell order (runtime.prev.S).
    %    2. Permute to sorted (optimizer) coordinates using mode_data.idx.
    %    3. Assign to the YALMIP binvar handle for the active optimizer.
    %    4. YALMIP reads this assignment when usex0=1 and passes it to
    %       Gurobi as model.start (a per-variable MIP-start hint).
    %
    %  For Variant A_WS, enable_sorting=false so idx = (1:Ns)', meaning
    %  physical order == sorted order and no permutation is needed.
    %  --------------------------------------------------------------------
    if isfield(constants.cfg, 'WARM_START') && constants.cfg.WARM_START.enabled ...
            && isfield(mode_data, 'idx')
        prev_S_sorted = ctx.prevCmd.S(mode_data.idx(:));
        Np_ws = constants.cfg.mpc.Np;
        if ctx.currentState == ctx.states.DISCHARGE_HIGH
            ws_handle = constants.cfg.WARM_START.S_cell_handles.disHigh;
        else
            ws_handle = constants.cfg.WARM_START.S_cell_handles.disLow;
        end
        assign(ws_handle, repmat(prev_S_sorted, 1, Np_ws));
    end

    % --------------------------------------------------------------------
    %  Solve optimizer and classify result
    %  --------------------------------------------------------------------
    [sol, diagnostics, u] = call_optimizer(mode_data.active_optimizer, mode_data.optimizer_params, u);
    if isfield(constants.cfg, 'DEBUG') && ...
            isfield(constants.cfg.DEBUG, 'keep_diagnostics') && ...
            constants.cfg.DEBUG.keep_diagnostics
        u.raw_diagnostics = diagnostics;
    end
    solver_diag = extract_solver_diagnostics(diagnostics);
    u = copy_diagnostics(u, solver_diag);
    u = classify_solver_outcome(u, solver_diag, sol, mode_data.mode);

    % --------------------------------------------------------------------
    %  Safe fallback on unusable solution
    %  --------------------------------------------------------------------
    if ~u.solution_usable
        u = apply_failure_fallback_metadata(u);
        u = apply_zero_command(u, ctx.Ns, true);
        u.controller_wall = toc(t_ctrl);
        return;
    end

    % --------------------------------------------------------------------
    %  Unpack solution by mode
    %  --------------------------------------------------------------------
    t0 = tic;
    [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
        unpack_active_mode_solution(sol, mode_data, u, ctx);
    u.t_extract = toc(t0);

    % --------------------------------------------------------------------
    %  Final derived outputs
    %  --------------------------------------------------------------------
    u.n_engaged       = sum(u.S);
    u.controller_wall = toc(t_ctrl);
end



%% ========================================================================
%  Context and top-level flow helpers
% =========================================================================

function ctx = build_step_context(runtime, constants, profile, k, v_OC_k)
% BUILD_STEP_CONTEXT  Collect all step data into one struct.
%
% Purpose
%   Centralise state unpacking, shape normalisation, and constant extraction
%   so that downstream helpers operate on one consistent context struct.

    x_k = runtime.x;

    ctx = struct();

    % Step identity
    ctx.k = k;

    % Runtime state (normalised to column vectors)
    ctx.z_k    = x_k.z(:);
    ctx.iRC1_k = x_k.iRC1(:);
    ctx.iRC2_k = x_k.iRC2(:);
    ctx.T_k    = x_k.T(:);
    ctx.SOH_k  = x_k.SOH(:);
    ctx.v_OC_k = v_OC_k(:);

    % Runtime metadata
    ctx.prevCmd       = runtime.prev;
    ctx.sm            = runtime.sm;
    ctx.currentState  = runtime.sm.currentState;
    ctx.step_in_state = runtime.sm.step_in_state;
    ctx.v_pack_prev   = runtime.meas.v_pack_meas;

    % Persistent controller memory
    ctx.mem = init_mem(runtime);

    % Configuration
    ctx.cfg       = constants.cfg;
    ctx.Ns        = constants.cfg.Ns;
    ctx.Np = constants.cfg.mpc.Np;

    % State enum
    ctx.states = constants.states;

    % OCV table
    ctx.soc_bp = constants.models.ocv.ocv_pwl.soc_bp_optimal;
    ctx.v_bp   = constants.models.ocv.ocv_pwl.v_bp_optimal;

    % Electrical parameters
    ctx.R0  = constants.models.elec.R0;
    ctx.R1  = constants.models.elec.R1;
    ctx.R2  = constants.models.elec.R2;
    ctx.r_s = constants.models.elec.r_s;   % switch on-state resistance (Ohm)

    % Capacity / health-derived quantities
    ctx.Q_cell_As   = constants.models.cell.Q_cell_nom_As;
    ctx.Q_eff_As_k  = ctx.Q_cell_As .* ctx.SOH_k;
    ctx.SOH_inv_k = 1 ./ ctx.SOH_k;

    % Limits
    ctx.i_pack_min = constants.limits.i_pack_min;
    ctx.i_pack_max = constants.limits.i_pack_max;
    ctx.v_pack_min = constants.limits.v_pack_min;
    ctx.v_pack_max = constants.limits.v_pack_max;
    ctx.v_cell_max = constants.limits.v_cell_max;
    ctx.v_cell_min = constants.limits.v_cell_min;
    ctx.T_cell_max = constants.limits.T_cell_max;
    ctx.T_cell_min = constants.limits.T_cell_min;

    % Profile
    ctx.p_req_vec = profile.p_req_vec(:);

    % Full constants bundle, passed through when needed
    ctx.constants = constants;
end



% ----------------------------------------------------------------------- %
function [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = init_step_outputs(ctx)
% INIT_STEP_OUTPUTS  Create the default command struct and objective outputs.

    u = init_command(ctx.k, ctx.prevCmd, ctx.v_pack_prev, ctx.Ns);

    J_SOH     = NaN;
    J_SOC     = NaN;
    J_sw      = NaN;
    J_sw_prev = NaN;
    J_lambda    = NaN;
end



% ----------------------------------------------------------------------- %
function [mode_data, u] = prepare_active_mode(ctx, opt, u)
% PREPARE_ACTIVE_MODE  Build optimizer inputs for the active control mode.
%
% Returns
%   mode_data.mode              Mode label
%   mode_data.active_optimizer  Optimizer handle to call
%   mode_data.optimizer_params  Parameter cell for that optimizer
%   mode_data.p_pack_req        First-step requested pack power
%   mode_data.mem_after_prepare Memory state after any mode-specific updates
%
% Notes
%   Discharge mode additionally returns sorting diagnostics and updates
%   some user-facing fields in u.

    states = ctx.states;

    switch ctx.currentState

        case {states.DISCHARGE_HIGH, states.DISCHARGE_LOW}
            [mode_data, u] = prepare_discharge_mode(ctx, opt, u);

        case states.CHARGE_BULK
            [mode_data, u] = prepare_charge_bulk_mode(ctx, opt, u);

        case states.CHARGE_BALANCE
            [mode_data, u] = prepare_charge_balance_mode(ctx, opt, u);

        otherwise
            error('controller_step: unknown state %d', ctx.currentState);
    end
end



% ----------------------------------------------------------------------- %
function [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
        unpack_active_mode_solution(sol, mode_data, u, ctx)
% UNPACK_ACTIVE_MODE_SOLUTION  Mode-specific solution unpacking.

    switch mode_data.mode
        case "discharge"
            [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
                unpack_discharge_solution(sol, mode_data, u, ctx);

        case "charge_bulk"
            [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
                unpack_charge_bulk_solution(sol, u, ctx);

        case "charge_balance"
            [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
                unpack_charge_balance_solution(sol, u);

        otherwise
            error('controller_step: internal mode error');
    end
end



%% ========================================================================
%  Mode preparation helpers
% =========================================================================
function [mode_data, u] = prepare_discharge_mode(ctx, opt, u)
% PREPARE_DISCHARGE_MODE  Build runtime inputs for the discharge MPC.

    [P_ref_h, sgnP] = build_power_horizon(ctx.step_in_state, ctx.p_req_vec, ctx.Np, ...
                                          ctx.cfg.NUMERICS.TRACKING_POWER_EPS);

    discharge_in = struct( ...
        'z_k',          ctx.z_k,          ...
        'iRC1_k',       ctx.iRC1_k,       ...
        'iRC2_k',       ctx.iRC2_k,       ...
        'T_k',          ctx.T_k,          ...
        'SOH_k',        ctx.SOH_k,        ...
        'P_ref_h',      P_ref_h,          ...
        'sgnP',         sgnP,             ...
        'soc_bp',       ctx.soc_bp,       ...
        'v_bp',         ctx.v_bp,         ...
        'R0',           ctx.R0,           ...
        'R1',           ctx.R1,           ...
        'R2',           ctx.R2,           ...
        'r_s',          ctx.r_s,          ...   % switch on-state resistance (Ohm)
        'i_pack_min',   ctx.i_pack_min,   ...
        'i_pack_max',   ctx.i_pack_max,   ...
        'v_pack_min',   ctx.v_pack_min,   ...
        'v_pack_max',   ctx.v_pack_max,   ...
        'v_cell_max',   ctx.v_cell_max,   ...
        'v_cell_min',   ctx.v_cell_min,   ...
        'T_cell_max',   ctx.T_cell_max,   ...
        'T_cell_min',   ctx.T_cell_min,   ...
        'Q_eff_As_k',   ctx.Q_eff_As_k,   ...
        'SOH_inv_k',  ctx.SOH_inv_k,  ...
        'S_prev',       u.S,              ...
        'Tstep',        ctx.cfg.Tstep,    ...
        'Ns',           ctx.Ns,           ...
        'Np',    ctx.Np,    ...
        'mem',          ctx.mem,          ...
        'constants',    ctx.constants     ...
    );

    % [optimizer_params, p_pack_req, idx, score_dbg, dzT_max, mem_out] = ...
    %     prepare_discharge_params(discharge_in);
    [optimizer_params, p_pack_req, idx, score_dbg, dzT_max, mem_out, param_dbg] = ...
        prepare_discharge_params(discharge_in);    

    % Store score diagnostics in physical cell order.
    % Scores are computed in physical order by computeRankingScore and must
    % NOT be passed through unsort_vec (which inverts the sort permutation
    % for optimizer outputs that arrive in sorted order). Applying unsort_vec
    % here would corrupt the logged values without affecting the controller.
    u.score.rho_v    = score_dbg.rho_v;
    u.score.rho_SOC  = score_dbg.rho_SOC;
    u.score.rho_SOH  = score_dbg.rho_SOH;
    u.score.raw      = score_dbg.score_raw;
    u.score.smoothed = score_dbg.score_sm;
    u.dzT_max          = dzT_max;
    u.rank_idx         = idx(:);
    u.debug.discharge_params = param_dbg;    

    if ctx.currentState == ctx.states.DISCHARGE_HIGH
        active_optimizer = opt.disHigh;
    else
        active_optimizer = opt.disLow;
    end

    % First-step lower bound on engaged cells, for diagnostics
    u.n_engaged_min_feasible = optimizer_params{end}(1);

    mode_data = struct();
    mode_data.mode              = "discharge";
    mode_data.active_optimizer  = active_optimizer;
    mode_data.optimizer_params  = optimizer_params;
    mode_data.p_pack_req        = p_pack_req;
    mode_data.idx               = idx;
    mode_data.mem_after_prepare = mem_out;
end



% ----------------------------------------------------------------------- %
function [mode_data, u] = prepare_charge_bulk_mode(ctx, opt, u)
% PREPARE_CHARGE_BULK_MODE  Build inputs for the bulk-charge optimizer.

    I_ref_h = ctx.i_pack_min * ones(ctx.Np, 1);

    mode_data = struct( ...
        'mode',              "charge_bulk",  ...
        'active_optimizer',  opt.chgBulk,    ...
        'optimizer_params',  {{ctx.z_k, ctx.iRC1_k, ctx.iRC2_k, ctx.T_k, I_ref_h, ctx.v_OC_k, ctx.SOH_k}}, ...
        'p_pack_req',        0,              ...
        'mem_after_prepare', ctx.mem         ...
    );

    u.i_pack_nominal_from_power = u.i_pack_cmd;
end



% ----------------------------------------------------------------------- %
function [mode_data, u] = prepare_charge_balance_mode(ctx, opt, u)
% PREPARE_CHARGE_BALANCE_MODE  Build inputs for the balance-charge optimizer.

    mode_data = struct( ...
        'mode',              "charge_balance", ...
        'active_optimizer',  opt.chgBal,       ...
        'optimizer_params',  {{ctx.z_k, ctx.iRC1_k, ctx.iRC2_k, ctx.T_k, ctx.SOH_k, ctx.v_OC_k}}, ...
        'p_pack_req',        0,                ...
        'mem_after_prepare', ctx.mem           ...
    );

    u.i_pack_nominal_from_power = u.i_pack_cmd;
end



%% ========================================================================
%  Mode solution unpacking helpers
% =========================================================================
function [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
        unpack_discharge_solution(sol, mode_data, u, ctx)
% UNPACK_DISCHARGE_SOLUTION  Unpack discharge-MPC outputs.
%
% Output slot order matches buildDischargeOptimizer:
%   1  S_cell(:,1)       first-step switch decisions
%   2  i_pack(1)         first-step pack current
%   3  v_cell(:,1)       first-step cell voltages
%   4  v_cell_eng(:,1)   first-step engaged-cell voltages
%   5  v_pack(1)         first-step pack voltage
%   6  lambda_slack(1)   first-step curtailment slack lambda(ell)
%   7  J_SOH
%   8  J_SOC
%   9  J_sw
%  10  J_sw_prev
%  11  J_lambda
%  12  dzT_terminal

    CURT_TOL = ctx.cfg.NUMERICS.CURT_TOL;

    S_sorted        = round(double(sol{1}));
    i_pack1         = double(sol{2});
    v_cell_sorted   = double(sol{3});
    v_eng_sorted    = double(sol{4});
    v_pack1         = double(sol{5});
    lambda_slack1   = double(sol{6});   % curtailment slack lambda(1)

    % Remove solver feasibility-tolerance artifacts from nonnegative slack.
    if (lambda_slack1 < 0 && (abs(lambda_slack1) < CURT_TOL))
        lambda_slack1 = 0;
    end    

    J_SOH     = double(sol{7});
    J_SOC     = double(sol{8});
    J_sw      = double(sol{9});
    J_sw_prev = double(sol{10});
    J_lambda    = double(sol{11});
    u.dzT     = double(sol{12});

    % J_lambda is theoretically nonnegative; tiny negatives are solver tolerance residue.
    if (J_lambda < 0 && (abs(J_lambda) < CURT_TOL))
        J_lambda = 0;
    end    

    [u.exact_prefix, u.prefix_break] = isPrefixBinary(S_sorted);

    % Map sorted outputs back to physical cell order
    u.S      = unsort_vec(S_sorted,      mode_data.idx, ctx.Ns);
    u.v_cell = unsort_vec(v_cell_sorted, mode_data.idx, ctx.Ns);
    u.v_eng  = unsort_vec(v_eng_sorted,  mode_data.idx, ctx.Ns);

    u.i_pack_cmd  = i_pack1;
    u.v_pack      = v_pack1;
    u.lambda_slack = lambda_slack1;

    % Current implied by the requested first-step power
    u.i_pack_req = mode_data.p_pack_req / max(v_pack1, 1e-6);

    % Nominal no-curtailment current, protected for logging against tiny voltage
    u.i_pack_nominal_from_power = mode_data.p_pack_req / max(v_pack1, 1e-6);
end



% ----------------------------------------------------------------------- %
function [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
        unpack_charge_bulk_solution(sol, u, ctx)
% UNPACK_CHARGE_BULK_SOLUTION  Unpack bulk-charge solution.

    u.S            = ones(ctx.Ns, 1);
    u.i_pack_cmd   = double(sol{1});
    u.i_pack_req   = u.i_pack_cmd;
    u.lambda_slack = 0;
    u.i_pack_nominal_from_power = u.i_pack_cmd;

    [J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = deal(0);
end



% ----------------------------------------------------------------------- %
function [u, J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = ...
        unpack_charge_balance_solution(sol, u)
% UNPACK_CHARGE_BALANCE_SOLUTION  Unpack balance-charge solution.

    u.S            = round(double(sol{1}));
    u.i_pack_cmd   = double(sol{2});
    u.i_pack_req   = u.i_pack_cmd;
    u.lambda_slack = 0;
    u.i_pack_nominal_from_power = u.i_pack_cmd;

    [J_SOH, J_SOC, J_sw, J_sw_prev, J_lambda] = deal(0);
end



%% ========================================================================
%  Command / fallback helpers
% =========================================================================
function u = apply_rest_skip_metadata(u)
% APPLY_REST_SKIP_METADATA  Mark the step as intentionally skipped in REST.

    u.skip_mpc          = true;
    u.fail_type         = "rest_skip";
    u.status_str        = "SKIP_REST";
    u.termination       = "skipped";
    u.termination_class = "skipped";
    u.solution_source   = "fallback_rest";
    u.solution_usable   = true;
    u.optimality_proven = false;
    u.used_incumbent    = false;
    u.used_fallback     = true;
end



% ----------------------------------------------------------------------- %
function u = apply_failure_fallback_metadata(u)
% APPLY_FAILURE_FALLBACK_METADATA  Mark the command as a solver-failure fallback.

    u.used_fallback   = true;
    u.solution_source = "fallback_failure";
end



% ----------------------------------------------------------------------- %
function u = apply_zero_command(u, Ns, set_zero_pack_voltage)
% APPLY_ZERO_COMMAND  Overwrite command fields with a safe zero-current action.
%
% Inputs
%   Ns                    Number of series cells
%   set_zero_pack_voltage If true, overwrite u.v_pack with 0. If false,
%                         preserve the previous measured value already stored.

    u.S            = zeros(Ns, 1);
    u.i_pack_cmd   = 0;
    u.i_pack_req   = 0;
    u.lambda_slack = 0;
    u.n_engaged    = 0;

    if set_zero_pack_voltage
        u.v_pack = 0;
    end
end



%% ========================================================================
%  Existing local helpers
% =========================================================================
function mem = init_mem(runtime)
% INIT_MEM  Ensure controller memory fields exist.
%
% Purpose
%   The discharge parameter builder uses controller memory to smooth the
%   ranking score and to propagate the adaptive terminal-spread allowance.
%
% Returns
%   mem with the required fields initialised when missing:
%     - dz_T_max_prev
%     - score_prev

    if ~isfield(runtime, 'mem') || isempty(runtime.mem)
        mem = struct();
    else
        mem = runtime.mem;
    end
    if ~isfield(mem, 'dz_T_max_prev'), mem.dz_T_max_prev = []; end
    if ~isfield(mem, 'score_prev'),    mem.score_prev    = []; end
end



% ----------------------------------------------------------------------- %
function u = init_command(k, prevCmd, v_pack_prev, Ns)
% INIT_COMMAND  Create the default command struct for this step.
%
% Purpose
%   Seed the output struct with previous safe values, NaN diagnostics, and
%   preallocated per-cell diagnostic fields.

    u.k            = k;
    u.skip_mpc     = false;
    u.S            = prevCmd.S;
    u.i_pack_cmd   = prevCmd.i_pack_cmd;
    u.i_pack_req   = prevCmd.i_pack_cmd;
    u.v_pack       = v_pack_prev;
    u.lambda_slack = 0;               % curtailment slack lambda(ell)

    u.solve_wall      = 0;
    u.solver_time     = NaN;
    u.controller_wall = 0;
    u.t_prepare       = NaN;
    u.t_extract       = NaN;
    u.mip_gap       = NaN;
    u.obj_val       = NaN;
    u.status_str    = "N/A";
    u.termination   = "N/A";
    u.problem_code  = NaN;
    u.fail_type     = "none";
    u.node_count    = NaN;
    u.best_bound    = NaN;
    u.incumbent_obj = NaN;
    u.n_engaged     = NaN;
    u.debug = struct();
    u.raw_diagnostics = [];    

    u.v_cell = NaN(Ns, 1);
    u.v_eng  = NaN(Ns, 1);

    u.score.rho_v    = NaN(Ns, 1);
    u.score.rho_SOC  = NaN(Ns, 1);
    u.score.rho_SOH  = NaN(Ns, 1);
    u.score.raw        = NaN(Ns, 1);
    u.score.smoothed   = NaN(Ns, 1);
    u.rank_idx         = (1:Ns)';
    u.exact_prefix     = false;
    u.prefix_break     = NaN;

    u.dzT_max = NaN;
    u.dzT     = NaN;

    u.i_pack_nominal_from_power = NaN;
    u.n_engaged_min_feasible    = NaN;

    u.solution_usable   = false;
    u.optimality_proven = false;
    u.used_incumbent    = false;
    u.used_fallback     = false;
    u.solution_source   = "none";
    u.termination_class = "none";
end



% ----------------------------------------------------------------------- %
function [P_ref_h, sgnP] = build_power_horizon(step_in_state, p_req_vec, Np, p_eps)
% BUILD_POWER_HORIZON  Build a length-Np power-reference window.
%
% Purpose
%   Extract a horizon window from the requested pack-power profile.
%   The indexing wraps circularly inside P_REQ_VEC, and the last profile
%   value is held if the window overruns the vector end.
%
% Output conventions
%   P_ref_h  Np x 1 reference power vector
%   sgnP     Np x 1 sign vector:
%              +1 for discharge, and for |P_req| <= p_eps (the discharge
%                 convention at a zero request; see the definition of d_p)
%              -1 for charge
%
% Inputs
%   p_eps    Zero-power threshold [W], cfg.NUMERICS.TRACKING_POWER_EPS.

    p_req_vec = p_req_vec(:);

    idx_start = 1 + mod(step_in_state - 1, numel(p_req_vec));
    idx_end   = idx_start + Np - 1;

    if idx_end <= numel(p_req_vec)
        P_ref_h = p_req_vec(idx_start:idx_end);
    else
        P_ref_h = p_req_vec(idx_start:end);
        P_ref_h(end+1:Np) = p_req_vec(end);
    end

    P_ref_h = P_ref_h(:);

    sgnP = ones(Np, 1);
    sgnP(P_ref_h < -p_eps) = -1;
end



% ----------------------------------------------------------------------- %
function lambda_slack_max = build_lambda_slack_max(absP_ref_h, v_pack_min, delta_P)
% BUILD_LAMBDA_SLACK_MAX  Build curtailment upper bound lambda^max (A).
%
% lambda^max(ell) = delta_P * |P_req(ell)| / v_pack_min

    absP_ref_h = absP_ref_h(:);

    if delta_P <= 0 || delta_P >= 1
        error('delta_P must be in (0,1).');
    end

    if v_pack_min <= 0
        error('v_pack_min must be positive.');
    end

    lambda_slack_max = delta_P * absP_ref_h / v_pack_min;
end



% ----------------------------------------------------------------------- %
function [i_pack_upper, i_pack_lower, qUvec] = compute_pack_current_bounds( ...
        P_ref_h, v_pack_min, v_pack_max, i_pack_min, i_pack_max)
% COMPUTE_PACK_CURRENT_BOUNDS  Manuscript Appendix, eq:packCurrentBounds.
%
% Outputs
%   i_pack_upper  Np x 1 upper pack-current bound \bar{i}_{pack}(ell)
%   i_pack_lower  Np x 1 lower pack-current bound \underline{i}_{pack}(ell)
%   qUvec         Np x 1 upper bound on q_sq = i_pack^2
%
% Definition
%   P_req > 0: upper = min(P_req/v_pack_min, i_pack_max) + eps, lower = 0
%   P_req = 0: upper = 0, lower = 0
%   P_req < 0: upper = 0, lower = max(P_req/v_pack_max, i_pack_min) - eps

    epsI = 1e-6;
    P_ref_h = P_ref_h(:);
    Np_loc  = numel(P_ref_h);

    % Broadcast bounds to Np x 1 so logical-index slicing is size-consistent
    % regardless of whether a scalar or a per-stage vector was passed in.
    if isscalar(v_pack_min), v_pack_min = v_pack_min * ones(Np_loc, 1); end
    %if isscalar(v_pack_max), v_pack_max = v_pack_max * ones(Np_loc, 1); end
    v_pack_min = v_pack_min(:);
    %v_pack_max = v_pack_max(:);

    i_pack_upper = zeros(Np_loc, 1);
    i_pack_lower = zeros(Np_loc, 1);

    dis = P_ref_h > 0;
    chg = P_ref_h < 0;

    i_pack_upper(dis) = min(P_ref_h(dis) ./ v_pack_min(dis), i_pack_max) + epsI;
    i_pack_lower(chg) = max(P_ref_h(chg) ./ v_pack_min(chg), i_pack_min) - epsI;

    qUvec = max(i_pack_upper.^2, i_pack_lower.^2);
end



% ----------------------------------------------------------------------- %
function [params_now, p_pack_req, idx, score_dbg, dzT_max, mem_out, param_dbg] = ...
        prepare_discharge_params(d)
% PREPARE_DISCHARGE_PARAMS  Build runtime parameters for the discharge MPC.
%
% Purpose
%   Assemble the exact parameter cell expected by buildDischargeOptimizer.
%   This function also computes the cell-ranking permutation used to make
%   the optional monotone-stack constraint meaningful.
%
% Parameter slots produced
%     1- 4  z, iRC1, iRC2, T              (sorted)
%     5- 6  P_ref_h, sgnP
%     7- 8  m_ocv, b_ocv                  (sorted)
%     9-10  i_pack_upper, i_pack_lower    (manuscript: Eq. A1)
%       11  qUvec                         (upper bound on i_pack^2)
%       12  lambda_slack_max              (manuscript: lambda^max(ell))
%    13-14  Q_eff_As, SOH_inv           (sorted)
%       15  S_prev                        (sorted)
%       16  lambda_scale
%       17  dzT_max                       (manuscript: Delta_SOC_max)
%       18  Ns_min_stage
%
% Returns
%   params_now  Cell array in optimizer parameter order
%   p_pack_req  First-step requested pack power
%   idx         Sort permutation, best-to-worst cell
%   score_dbg   Per-cell score breakdown for diagnostics
%   dzT_max     Terminal SOC-spread allowance
%   mem_out     Updated controller memory


    %% --------------------------------------------------------------------
    %  Recover controller memory
    %  --------------------------------------------------------------------
    mem_out       = d.mem;
    dz_T_max_prev = d.mem.dz_T_max_prev;
    %score_prev    = d.mem.score_prev;

    sp = d.constants.cfg.mpc.socSpread;

    if isempty(dz_T_max_prev)
        dz_T_max_prev = sp.Delta_high;
    end



    %% --------------------------------------------------------------------
    %  Local affine OCV model
    %  --------------------------------------------------------------------
    [m_ocv, b_ocv] = ocv_affine_from_pwl(d.z_k, d.soc_bp, d.v_bp);

    % Current per-cell OCV estimate and worst-cell OCV
    v_ocv0_k  = m_ocv .* d.z_k + b_ocv;
    v_ocv_min = min(v_ocv0_k);

    absP_ref_h = abs(d.P_ref_h);
    dis_step   = d.sgnP > 0;



    %% --------------------------------------------------------------------
    %  Lambda normalisation
    %  --------------------------------------------------------------------
    %  Used so that the same slack magnitude
    %  is weighted consistently across discharge and charge stages.
    d_mode      = (d.sgnP + 1) / 2;
    I_scale     = d_mode * d.i_pack_max + (1 - d_mode) * abs(d.i_pack_min);
    lambda_scale = 1 ./ I_scale;



    %% --------------------------------------------------------------------
    %  Adaptive terminal SOC-spread limit (Delta_SOC_max)
    %  --------------------------------------------------------------------
    %  Tighten the terminal spread as the weakest cell SOC falls. A small
    %  memory term prevents abrupt tightening from one step to the next.
    tau = min(max((min(d.z_k) - sp.z_low) / ...
                  (sp.z_high - sp.z_low), 0), 1);
    
    dzT_max = sp.Delta_low + ...
              (sp.Delta_high - sp.Delta_low) * tau;
    
    dzT_max = max(dzT_max, dz_T_max_prev - sp.slew_rate * d.Tstep);



    %% --------------------------------------------------------------------
    %  Per-stage minimum engaged-cell count (voltage and power feasibility)
    %  --------------------------------------------------------------------
    %  Two independent lower bounds are combined:
    %    1. Voltage feasibility: Ns_min_voltage
    %    2. Power feasibility:   Ns_min_power
    %  The maximum is the tightest valid lower bound without solving the
    %  optimization problem.
    %
    %  NOTE: Ns_min_power must be computed here, before Ns_ref below uses it.
    Ns_min_voltage = ceil(d.v_pack_min / d.v_cell_max);
    i_hw_vec       = d.i_pack_max * ones(d.Np, 1);
    i_hw_vec(d.sgnP < 0) = abs(d.i_pack_min);
    Ns_min_power   = ceil(absP_ref_h ./ (d.v_cell_max * i_hw_vec));
    Ns_min_stage   = min(max(max(Ns_min_voltage, Ns_min_power), 0), d.Ns);



    %% --------------------------------------------------------------------
    %  Cell-ranking score for sorting
    %  --------------------------------------------------------------------
    %  The optimizer sees only the sorted cell order.  Cells are ranked by
    %  their marginal cost of engagement — the negative gradient of the
    %  single-step MPC cost J with respect to S_i:
    %
    %      rho_i  =  -dJ/dS_i  =  rho_SOH_i  +  rho_SOC_i  +  rho_v_i
    %
    %  This is gradient-exact: for a linear objective the gradient-ranked
    %  prefix is the provably optimal solution to the binary relaxation
    %  (Proposition 1).  For the nonlinear SOC and curtailment terms the
    %  gradient is the tightest first-order approximation.
    %
    %  No cross-sectional normalisation (N(·)) or gamma weights are needed;
    %  the objective weights w_SOH, w_SOC, w_lambda set the relative scale
    %  of the three components automatically.  See computeRankingScore.m.

    % Coarse representative first-step current for scoring.
    Ns_ref = max(max(Ns_min_voltage, Ns_min_power(1)), 1);


    % --- Component 1: loaded terminal-voltage preference -----------------
    if dis_step(1)
        v_ocv_ref = v_ocv_min;
        i_hw      = d.i_pack_max;
    else
        v_ocv_ref = max(v_ocv0_k);
        i_hw      = abs(d.i_pack_min);
    end

    i_exp = min(absP_ref_h(1) / max(v_ocv_ref * Ns_ref, 1e-6), i_hw);

    % Estimated loaded terminal voltage for each cell (clamped to safe range).
    % Passed to computeRankingScore for the voltage gradient component (rho_v).
    if dis_step(1)
        v_term = v_ocv0_k - d.R0*i_exp - d.R1*d.iRC1_k - d.R2*d.iRC2_k;
    else
        v_term = v_ocv0_k + d.R0*abs(i_exp) - d.R1*d.iRC1_k - d.R2*d.iRC2_k;
    end
    v_term = min(max(v_term, d.v_cell_min), d.v_cell_max);


    % --- Gradient-exact ranking score ------------------------------------
    % rho_i = -dJ/dS_i = rho_SOH_i + rho_SOC_i + rho_v_i
    %
    % No cross-sectional normalisation (N(·)) and no gamma weights needed:
    % the objective weights w_SOH, w_SOC, w_lambda directly set the
    % relative magnitudes of the three components.  See computeRankingScore.m
    % for the full derivation from the MPC cost function.
    [score, rho_SOH, rho_SOC, rho_v] = computeRankingScore( ...
        d.z_k, d.SOH_inv_k, d.Q_eff_As_k, v_term, i_exp, ...
        dis_step(1), dzT_max, d.P_ref_h(1), Ns_ref, lambda_scale(1), d.constants.cfg);


    % --- Temporal smoothing (DISABLED — uncomment block to re-enable) ----
    % if isempty(score_prev) || numel(score_prev) ~= d.Ns
    %     score_prev = score;
    % end
    % score_sm = 0.5 * score_prev + 0.5 * score;
    score_sm = score;   % pass-through: raw gradient score used directly
    %score_prev = score; % keep mem current in case smoothing is re-enabled

    % Store score components for diagnostics before sharpening.
    % Names kept consistent with log.score fields in tcst_run_variant.m.


    %% --------------------------------------------------------------------
    %  Sort cells best-to-worst
    %  --------------------------------------------------------------------
    % Softmax sharpening (DISABLED — uncomment block to re-enable).
    % With gradient-exact scores the raw magnitudes are physically meaningful;
    % sharpening can be re-introduced once the score scale is validated.
    % beta           = 5.0;
    % score_sm_sharp = exp(beta * score_sm);
    % score_sm_sharp = score_sm_sharp / sum(score_sm_sharp);
    % score_sm       = score_sm_sharp;

    if isfield(d.constants, 'enable_sorting') && d.constants.enable_sorting
        [~, idx] = sort(score_sm, 'descend');
    else
        idx = (1:d.Ns)';
    end

    % Apply sort permutation to all cell-indexed runtime data
    z_k_s       = d.z_k(idx);
    iRC1_k_s    = d.iRC1_k(idx);
    iRC2_k_s    = d.iRC2_k(idx);
    T_k_s       = d.T_k(idx);
    m_ocv_s     = m_ocv(idx);
    b_ocv_s     = b_ocv(idx);
    Q_eff_As_s  = d.Q_eff_As_k(idx);
    SOH_inv_s = d.SOH_inv_k(idx);
    S_prev_s    = d.S_prev(idx);



    %% --------------------------------------------------------------------
    %  Tighter per-stage pack-voltage lower bound
    %  --------------------------------------------------------------------
    %  Used to tighten the Big-M current bound relative to the scalar system
    %  floor v_pack_min. The resistive drop per cell uses (R0 + r_s) to
    %  account for the series switch drop in the updated pack voltage equation.
    RC_drop_k1   = d.R1 * max(abs(d.iRC1_k)) + d.R2 * max(abs(d.iRC2_k));

    v_pack_lower = zeros(d.Np, 1);
    for ell = 1:d.Np
        if dis_step(ell)
            R_drop       = (d.R0 + d.r_s) * d.i_pack_max + (ell == 1) * RC_drop_k1;
            v_cell_lower = max(v_ocv_min - R_drop, d.v_cell_min);
        else
            % Charge: resistive term raises voltage above OCV — no correction.
            v_cell_lower = v_ocv_min;
        end
        v_pack_lower(ell) = max(Ns_min_stage(ell) * v_cell_lower, d.v_pack_min);
    end



    %% --------------------------------------------------------------------
    %  Big-M and quadratic-envelope bounds
    %  --------------------------------------------------------------------
    [i_pack_upper, i_pack_lower, qUvec] = compute_pack_current_bounds( ...
        d.P_ref_h, v_pack_lower, d.v_pack_max, d.i_pack_min, d.i_pack_max);



    %% --------------------------------------------------------------------
    %  Curtailment bound and first-step logging quantity
    %  --------------------------------------------------------------------
    delta_P         = d.constants.cfg.mpc.delta_P_curtail;

    if isfield(d.constants.cfg, 'DEBUG') && ...
            isfield(d.constants.cfg.DEBUG, 'delta_P_curtail_override') && ...
            isfinite(d.constants.cfg.DEBUG.delta_P_curtail_override)
        delta_P = d.constants.cfg.DEBUG.delta_P_curtail_override;
    end

    lambda_slack_max = build_lambda_slack_max(absP_ref_h, d.v_pack_min, delta_P);
    p_pack_req       = d.P_ref_h(1);

% Feasibility diagnostic for tightened current bound vs curtailment budget.
delta_required = max(0, 1 - d.v_pack_min ./ v_pack_lower);

param_dbg = struct();
param_dbg.P_ref_h          = d.P_ref_h;
param_dbg.sgnP             = d.sgnP;
param_dbg.absP_ref_h       = absP_ref_h;
param_dbg.Ns_min_stage     = Ns_min_stage;
param_dbg.v_pack_min       = d.v_pack_min;
param_dbg.v_pack_lower     = v_pack_lower;
param_dbg.delta_P_allowed  = delta_P;
param_dbg.delta_required   = delta_required;
param_dbg.curtailment_budget_violation = ...
    (d.P_ref_h > 0) & (delta_required > delta_P);
param_dbg.i_pack_upper     = i_pack_upper;
param_dbg.i_pack_lower     = i_pack_lower;
param_dbg.qUvec            = qUvec;
param_dbg.lambda_slack_max = lambda_slack_max;
param_dbg.dzT_max          = dzT_max;    


    %% --------------------------------------------------------------------
    %  Diagnostic outputs
    %  --------------------------------------------------------------------
    score_dbg = struct( ...
        'rho_v',      rho_v,      ...
        'rho_SOC',    rho_SOC,    ...
        'rho_SOH',    rho_SOH,    ...
        'score_raw',  score,      ...
        'score_sm',   score_sm    ...
    );



    %% --------------------------------------------------------------------
    %  Update controller memory
    %  --------------------------------------------------------------------
    mem_out.dz_T_max_prev = dzT_max;
    mem_out.score_prev    = score_sm;



    %% --------------------------------------------------------------------
    %  Pack optimizer parameter cell
    %  --------------------------------------------------------------------
    %  Order must match buildDischargeOptimizer exactly.
    params_now = { ...
        z_k_s, iRC1_k_s, iRC2_k_s, T_k_s,    ...  %  1– 4
        d.P_ref_h, d.sgnP,                     ...  %  5– 6
        m_ocv_s, b_ocv_s,                      ...  %  7– 8
        i_pack_upper, i_pack_lower, qUvec,      ...  %  9–11
        lambda_slack_max,                       ...  % 12  lambda^max(ell)
        Q_eff_As_s, SOH_inv_s,               ...  % 13–14
        S_prev_s, lambda_scale, dzT_max,         ...  % 15–17
        Ns_min_stage};                               % 18

end



% normalize_score_component removed: gradient-exact scoring in
% computeRankingScore.m renders cross-sectional normalisation unnecessary.