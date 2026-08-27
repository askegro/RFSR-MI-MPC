function log = buildLogging(cfg)

    Ns = cfg.Ns;
    nSteps = cfg.simSteps;
    
    log = struct();
    
    % -------------------------
    % State machine logging (per step)
    % -------------------------    
    log.state = nan(1,nSteps);
    
    % -------------------------
    % Requests + control decisions (per step)
    % -------------------------     
    log.i_pack_cmd  = nan(1,nSteps);
    log.p_pack_cmd  = nan(1,nSteps);
    log.p_pack_req  = nan(1,nSteps);
    log.S           = nan(Ns,nSteps);
    
    % Slack
    log.slack_mag               = nan(1,nSteps);  
    log.i_pack_req              = nan(1,nSteps);    
    log.v_pack              = nan(1,nSteps);          % MPC optimizer first-step predicted pack voltage
    log.v_pack_meas         = nan(1,nSteps);          % plant-measured pack voltage (actual closed-loop)
    log.p_pack_meas         = nan(1,nSteps);          % plant-measured delivered pack power = v_pack_meas * i_pack_cmd

    % -------------------------
    % Power limits (per step)
    % ------------------------- 
    %log.p_pack_lim_dis_max      = nan(1, nSteps);
    %log.p_pack_lim_chg_max      = nan(1, nSteps);    

    % -------------------------
    % Cell-level quantities (per step)
    % -------------------------    
    log.v_cell_meas_vec     = nan(Ns,nSteps);
    log.p_cell_loss_tot_vec = nan(Ns,nSteps);
    
    % -------------------------
    % Per-cell states
    % -------------------------    
    log.z_cell_vec = nan(Ns,nSteps+1);
    log.i_RC_1_vec              = nan(Ns, nSteps+1);
    log.i_RC_2_vec              = nan(Ns, nSteps+1);    
    log.T_cell_vec = nan(Ns,nSteps+1);
    log.EFC_cell_vec            = nan(Ns, nSteps+1);    
    log.SOH_cell_vec            = nan(Ns, nSteps+1);    
    
    % -------------------------
    % Solver / solution status (per step)
    % -------------------------   
    log.problem_code      = nan(1,nSteps); 
    log.fail_type         = strings(1,nSteps);
    log.termination_class = strings(1,nSteps);
    log.solution_source   = strings(1,nSteps);

    log.solution_usable   = false(1,nSteps);
    log.optimality_proven = false(1,nSteps);
    log.used_incumbent    = false(1,nSteps);
    log.used_fallback     = false(1,nSteps);

    log.node_count        = nan(1,nSteps);
    log.best_bound        = NaN(1,nSteps);
    log.incumbent_obj     = NaN(1,nSteps);
    log.n_engaged         = NaN(1,nSteps);
    log.n_engaged_min_feasible = NaN(1,nSteps);   % first-stage Ns_min_stage(1)
    log.Ns_min_stage_first = NaN(1,nSteps);       % alias for manuscript diagnostics

    % -------------------------
    % Discharge-params diagnostics (first horizon stage only)
    % Populated from u_mpc.debug.discharge_params when available.
    % Use to diagnose curtailment-budget violations and infeasibility in
    % anomalous cells (e.g. small-N, large-Np, variant D).
    % -------------------------
    log.dbg_delta_required_first         = NaN(1, nSteps);   % (v_pack_lower - v_pack_min) / v_pack_lower at stage 1
    log.dbg_curtailment_budget_viol_first = false(1, nSteps); % true when delta_required(1) > delta_P (discharge step)
    log.dbg_i_pack_upper_first           = NaN(1, nSteps);   % i_pack_upper(1): Big-M upper current bound
    log.dbg_lambda_slack_max_first       = NaN(1, nSteps);   % lambda_slack_max(1): curtailment budget (A)

    log.timeout           = false(1,nSteps);
    log.infeasible        = false(1,nSteps);
    log.hard_fail         = false(1,nSteps);
    log.non_timeout_fail  = false(1,nSteps);
    log.rest_skip         = false(1,nSteps);
    log.incumbent_timeout = false(1,nSteps);

    log.solve_wall        = nan(1,nSteps);
    log.solver_time       = nan(1,nSteps);
    log.controller_wall   = nan(1,nSteps);  % legacy: full outer step (state machine + controller + plant)
    log.t_step_wall       = nan(1,nSteps);  % full outer step wall time (same as controller_wall, kept separately for clarity)
    log.t_ctrl_wall       = nan(1,nSteps);  % controller-only: prepare + solve + extract (excludes plant)
    log.t_prepare         = nan(1,nSteps);  % ranking, sort, param build (inside prepare_active_mode)
    log.t_extract         = nan(1,nSteps);  % solution unpack + unsort (inside unpack_active_mode_solution)
    log.mip_gap           = nan(1,nSteps);
    log.status_str        = strings(1,nSteps);
    log.obj_val           = nan(1,nSteps);
 
    
    % ------------------------------------------------------------------------
    % Violation tracking
    % ------------------------------------------------------------------------    
    log.viol_packed = zeros(1,nSteps,'uint16');
    log.viol_idx    = zeros(1,nSteps,'uint16');
  
    
    % -------------------------
    % EOL termination
    % -------------------------    
    log.eol_reached   = false;
    log.eol_step      = uint32(0);
    log.eol_reason    = "";
    log.eol_cell_idx  = uint32(0);
    log.eol_soh_value = NaN;
    
    % Unweighted normalized objective components returned by the optimizer.
    log.J_SOH  = nan(1,nSteps);
    log.J_SOC  = nan(1,nSteps);
    log.J_curt = nan(1,nSteps);
    
    % Weighted objective contributions.
    log.J_SOH_weighted  = nan(1,nSteps);
    log.J_SOC_weighted  = nan(1,nSteps);
    log.J_curt_weighted = nan(1,nSteps);
    log.J_obj           = nan(1,nSteps);
    
    % Diagnostic scratch field: raw J_SOH + J_SOC + J_curt (unweighted sum).
    % The three components are normalized to independent scales; their
    % unweighted sum is NOT a meaningful quantity and must NOT appear in
    % comparison tables.  Use log.J_obj (= J_SOH_weighted + J_SOC_weighted
    % + J_curt_weighted) for all objective comparisons.
    log.J_sum_unweighted = nan(1,nSteps);
    
    % Backward-compatible aliases. These are the same as J_SOH, J_SOC, J_curt.
    log.J_SOH_raw  = nan(1,nSteps);
    log.J_SOC_raw  = nan(1,nSteps);
    log.J_curt_raw = nan(1,nSteps);

    log.score.rho_v  = NaN(Ns, nSteps);
    log.score.rho_SOC      = NaN(Ns, nSteps);    
    log.score.rho_SOH      = NaN(Ns, nSteps);

    log.score.raw      = NaN(Ns, nSteps);
    log.score.smoothed = NaN(Ns, nSteps);    
    log.rank_idx        = NaN(Ns, nSteps);
    log.exact_prefix    = false(1, nSteps);
    log.prefix_break    = NaN(1, nSteps);
    log.switch_events   = NaN(1, nSteps);

    log.dzT             = NaN(1,nSteps);
    log.dzT_max         = NaN(1,nSteps);

    % -------------------------
    % Reference solver (A, long time limit, same state as B)
    % Logged only — not applied to plant
    % -------------------------
    log.ref_solve_wall        = nan(1, nSteps);
    log.ref_solver_time       = nan(1, nSteps);
    log.ref_optimality_proven = false(1, nSteps);
    log.ref_mip_gap           = nan(1, nSteps);
    log.ref_obj_val           = nan(1, nSteps);
    log.ref_J_SOH             = nan(1, nSteps);
    log.ref_J_SOC             = nan(1, nSteps);
    log.ref_J_sw_prev         = nan(1, nSteps);
    log.ref_J_curt            = nan(1, nSteps);
    log.ref_S                 = nan(Ns, nSteps);
    log.ref_n_engaged         = nan(1, nSteps);
    log.ref_node_count        = nan(1, nSteps);
    log.ref_incumbent_timeout = false(1, nSteps);    

end
