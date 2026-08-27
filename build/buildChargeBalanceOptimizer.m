% ------------------------------------------------------------------
% FUNCTION: buildChargeBalanceOptimizer
% ------------------------------------------------------------------
% PURPOSE:
%   Builds a YALMIP optimizer object for MPC-based charge balancing
%   control of a Reconfigurable Battery System (RBS).
%
% CHARGING PHASE:
%   This optimizer handles the BALANCE (CV/termination) charging phase where:
%   - Cells can be individually engaged or bypassed
%   - Cells closer to target SOC can be bypassed
%   - Remaining cells continue charging toward target
%   - Goal is to bring all cells to the same final SOC
%
% CONTROL OBJECTIVE:
%   - Drive all cell SOCs toward a target final SOC (z_final)
%   - Use cell switching to balance SOC across pack
%   - Respect voltage, SOC, and thermal limits
%
% KEY DIFFERENCE FROM BULK CHARGING:
%   - Cell switching enabled (S_cell binary variable)
%   - This is where RBS benefits appear during charging
%   - Cells that reach target can be bypassed while others continue
%
% BATTERY MODEL:
%   - 2nd-order RC equivalent circuit per cell
%   - OCV pre-computed externally (static across horizon)
%   - Lumped thermal dynamics with I²R heat generation (McCormick relaxed)
%
% CURRENT CONVENTION:
%   - Charging current is NEGATIVE (i_pack < 0)
%   - i_pack_min is the maximum charging rate (most negative)
%   - i_pack_max is forced to 0 (no discharging in this mode)
%
% INPUTS:
%   Ns          - Number of cells in the pack
%   Np   - Prediction horizon length (number of timesteps)
%   constants   - Struct containing all physical and tuning parameters
%   ops         - YALMIP solver options (sdpsettings)
%
% OUTPUTS:
%   opt         - YALMIP optimizer object, callable as:
%                 [S_cell, i_pack, v_cell] = opt(params)
%
% AUTHOR: [Your name]
% DATE:   [Date]
% ------------------------------------------------------------------
function opt = buildChargeBalanceOptimizer(constants)
    

    %%% ================================================================
    %  SECTION 1: UNPACK CONSTANTS
    %%%  ================================================================
    %  Each constant on its own line for easy commenting/modification.
    %  Grouped by category for readability.
    cfg                 = constants.cfg;
    models              = constants.models;
    solver              = constants.solver;
    limits              = constants.limits;
    scale               = constants.scale;
    chg                 = constants.chg;

    mpc                 = cfg.mpc;    
    w                   = cfg.w;    
    elec                = models.elec;
    therm               = models.therm;
    cell                = models.cell;
    %aging               = models.aging;

    Ns                  = cfg.Ns;         % number of cells
    Np           = mpc.Np; % MPC horizon length
    %ocv_pwl             = models.ocv.ocv_pwl;
    ops                 = solver.ops;
    
    % --- Timing ---
    T_step              = cfg.Tstep;  % MPC timestep [s]   

    % --- Cell capacity ---
    Q_cell_As           = cell.Q_cell_nom_As;  % Cell capacity [A·s]     
    
    % --- Cell voltage limits [V] ---
    v_cell_min          = limits.v_cell_min;
    v_cell_max          = limits.v_cell_max;
    
    % --- SOC limits [0-1] ---
    z_cell_min          = limits.z_cell_min;
    z_cell_max          = limits.z_cell_max;
    
    % --- Cell temperature limits [degC] ---
    T_cell_min          = limits.T_cell_min;  
    T_cell_max          = limits.T_cell_max;     

    % --- Equivalent circuit resistances [Ohm] ---
    R0                  = elec.R0;  % Ohmic resistance
    R1                  = elec.R1;  % RC branch 1 resistance
    R2                  = elec.R2;  % RC branch 2 resistance

    % --- Electrical model parameters ---
    a1                  = elec.a1;
    a2                  = elec.a2;
    b1                  = elec.b1;
    b2                  = elec.b2;
    
    % --- Thermal model parameters ---
    T_amb               = therm.T_amb;        % Ambient temperature [°C or K]
    a_th                = therm.a_th;          % Thermal state decay coefficient
    b_th                = therm.b_th;          % Thermal input gain
    
    % --- Current limits ---
    % NOTE: Charging current is negative by convention.
    % i_pack_min is the maximum charging rate (most negative value).
    % i_pack_max is forced to 0 to prevent discharging in this mode.
    i_pack_min          = limits.i_pack_min;  % Max charging current (negative) [A]
    i_pack_max          = 0;                     % No discharging allowed
    
    % --- SOC balancing target ---
    z_final = chg.SOC_target;  % Target final SOC [0-1]
    
    % --- Objective weights and scaling ---
    w_socBalTerm_cv = w.socBalTerm_cv;  % Weight for SOC balancing
    z_scale         = scale.z;          % SOC scaling factor
    
    % --- Display configuration info ---
    % fprintf('  [Charge Balance] Cell switching enabled, targeting SOC = %.2f\n', z_final);
    % fprintf('  [Charge Balance] Current bounds: [%.2f, %.2f] A\n', i_pack_min, i_pack_max);
    % fprintf('  [Charge Balance] Using pre-computed OCV (static across horizon)\n');


    %%% ================================================================
    %  SECTION 2: DEFINE PARAMETERS (updated each MPC call)
    %%%  ================================================================
    %  These are inputs to the optimizer, representing current state
    %  and forecast information.
    
    % --- Cell states at previous timestep ---
    z_cell_prev_par = sdpvar(Ns, 1);          % SOC of each cell
    i_RC_1_cell_prev_par = sdpvar(Ns, 1);     % RC branch 1 current
    i_RC_2_cell_prev_par = sdpvar(Ns, 1);     % RC branch 2 current
    T_cell_prev_par = sdpvar(Ns, 1);          % Cell temperatures
    
    % --- Pre-computed OCV ---
    % OCV is computed externally from current SOC and passed in.
    % This avoids nonlinearity but assumes OCV is static across horizon.
    v_oc_prev_par = sdpvar(Ns, 1);            % Pre-computed OCV [V]
    
    % --- Cell health (currently unused, kept for interface compatibility) ---
    % TODO: Could be used to weight SOC targets by cell health
    SOH_cell_prev_par = sdpvar(Ns, 1);        % Cell SOH values (unused)


    %%% ================================================================
    %  SECTION 3: DEFINE DECISION VARIABLES
    %%%  ================================================================
    
    % --- State trajectories (Ns cells × Np+1 timesteps) ---
    % Extra column for terminal state at k = Np+1
    z_cell = sdpvar(Ns, Np+1, 'full');       % SOC trajectory
    i_RC_1_cell = sdpvar(Ns, Np+1, 'full');  % RC1 current trajectory
    i_RC_2_cell = sdpvar(Ns, Np+1, 'full');  % RC2 current trajectory
    T_cell = sdpvar(Ns, Np+1, 'full');       % Temperature trajectory
    
    % --- Control and algebraic variables ---
    S_cell = binvar(Ns, Np, 'full');         % Cell engagement (binary): 1=engaged, 0=bypassed
    i_pack = sdpvar(Np, 1);                  % Pack current [A]
    i_cell = sdpvar(Ns, Np, 'full');         % Individual cell currents [A]
    v_cell = sdpvar(Ns, Np, 'full');         % Cell terminal voltages [V]
    
    % --- Thermal auxiliary variables ---
    q_lin_cell = sdpvar(1, Np, 'full');      % Linearized i² for heat generation
    y_thermal = sdpvar(Ns, Np, 'full');      % Product: q_lin * S_cell (McCormick)


    %%% ================================================================
    %  SECTION 4: INITIAL CONDITIONS
    %%%  ================================================================
    
    con = [];
    
    % Tie first column of state trajectories to parameter inputs
    con = [con, z_cell(:,1) == z_cell_prev_par];
    con = [con, i_RC_1_cell(:,1) == i_RC_1_cell_prev_par];
    con = [con, i_RC_2_cell(:,1) == i_RC_2_cell_prev_par];
    con = [con, T_cell(:,1) == T_cell_prev_par];
    

    %%% ================================================================
    %  SECTION 5: DYNAMICS AND CONSTRAINTS OVER HORIZON
    %%%  ================================================================
    
    for ell = 1:Np
        
        % ----------------------------------------------------------
        % 5.1: Extract variables for timestep k
        % ----------------------------------------------------------
        
        % States at k
        z_cell_ell = z_cell(:,ell);
        i_RC_1_cell_ell = i_RC_1_cell(:,ell);
        i_RC_2_cell_ell = i_RC_2_cell(:,ell);
        T_cell_ell = T_cell(:,ell);
        
        % Controls and algebraic at k
        S_cell_ell = S_cell(:,ell);
        i_pack_ell = i_pack(ell);
        i_cell_ell = i_cell(:,ell);
        v_cell_ell = v_cell(:,ell);
        
        % Thermal auxiliary
        q_lin_cell_ell = q_lin_cell(ell);
        y_thermal_ell = y_thermal(:,ell);
        
        
        % ----------------------------------------------------------
        % 5.2: SOC constraints
        % ----------------------------------------------------------
        % Keep SOC within safe operating limits
        
        con = [con, z_cell_min <= z_cell_ell];%#ok<AGROW>
        con = [con, z_cell_ell <= z_cell_max];%#ok<AGROW>
        
        
        % ----------------------------------------------------------
        % 5.3: Pack current constraints
        % ----------------------------------------------------------
        % Current must stay within bounds.
        % i_pack_min < 0 (max charging rate)
        % i_pack_max = 0 (no discharging)
        
        con = [con, i_pack_min <= i_pack_ell];%#ok<AGROW>
        con = [con, i_pack_ell <= i_pack_max];%#ok<AGROW>
        
        
        % ----------------------------------------------------------
        % 5.4: Cell current switching logic (Big-M formulation)
        % ----------------------------------------------------------
        % If S_cell = 1 (engaged):  i_cell = i_pack
        % If S_cell = 0 (bypassed): i_cell = 0
        %
        % Implemented via four inequalities that create this either/or behavior.
        % For charging: i_pack_min < 0, i_pack_max = 0
        
        con = [con, i_cell_ell >= i_pack_min * S_cell_ell];%#ok<AGROW>
        con = [con, i_cell_ell <= i_pack_max * S_cell_ell];%#ok<AGROW>
        con = [con, i_cell_ell >= i_pack_ell - i_pack_max * (1 - S_cell_ell)];%#ok<AGROW>
        con = [con, i_cell_ell <= i_pack_ell - i_pack_min * (1 - S_cell_ell)];%#ok<AGROW>
        
        
        % ----------------------------------------------------------
        % 5.5: State dynamics
        % ----------------------------------------------------------
        % SOC: Coulomb counting (negative current increases SOC)
        % RC branches: Discrete-time first-order dynamics
        % Voltage: Kirchhoff's voltage law around cell
        %
        % NOTE: OCV is pre-computed and static across horizon.
        
        con = [con, z_cell(:,ell+1) == z_cell_ell - i_cell_ell * T_step ./ Q_cell_As];%#ok<AGROW>
        con = [con, i_RC_1_cell(:,ell+1) == a1 * i_RC_1_cell_ell + b1 * i_cell_ell];%#ok<AGROW>
        con = [con, i_RC_2_cell(:,ell+1) == a2 * i_RC_2_cell_ell + b2 * i_cell_ell];%#ok<AGROW>
        con = [con, v_cell_ell == v_oc_prev_par - R0*i_cell_ell - R1*i_RC_1_cell_ell - R2*i_RC_2_cell_ell];%#ok<AGROW>
        
        
        % ----------------------------------------------------------
        % 5.6: Thermal dynamics
        % ----------------------------------------------------------
        % Heat generation: Q_dot = I²R (approximated via secant relaxation)
        % Temperature update: Lumped thermal model
        %
        % McCormick envelope handles the bilinear y_thermal = q_lin × S_cell
        
        % Bounds on i² based on current limits
        qL = min(i_pack_min^2, i_pack_max^2);
        qU = max(i_pack_min^2, i_pack_max^2);
        
        % Secant (chord) relaxation of i_pack²
        con = [con, q_lin_cell_ell >= (i_pack_min + i_pack_max) * i_pack_ell - i_pack_min * i_pack_max];%#ok<AGROW>
        con = [con, qL <= q_lin_cell_ell];%#ok<AGROW>
        con = [con, q_lin_cell_ell <= qU];%#ok<AGROW>
        
        % McCormick envelope for y_thermal = q_lin_cell * S_cell
        % When S=1: y_thermal = q_lin_cell
        % When S=0: y_thermal = 0
        con = [con, 0 <= y_thermal_ell];%#ok<AGROW>
        con = [con, y_thermal_ell <= qU * S_cell_ell];%#ok<AGROW>
        con = [con, y_thermal_ell <= q_lin_cell_ell * ones(Ns,1)];%#ok<AGROW>
        con = [con, y_thermal_ell >= q_lin_cell_ell - qU * (1 - S_cell_ell)];%#ok<AGROW>
        
        % Heat generation (using 2*R0 as effective thermal resistance)
        thermal_R0 = 2 * R0;
        Qdot = thermal_R0 * y_thermal_ell;
        
        % Temperature state update
        con = [con, T_cell(:,ell+1) == T_amb + a_th * (T_cell_ell - T_amb) + b_th * Qdot];%#ok<AGROW>
        
        % Temperature limits
        con = [con, T_cell_min <= T_cell(:,ell+1)];%#ok<AGROW>
        con = [con, T_cell(:,ell+1) <= T_cell_max];%#ok<AGROW>
        
        
        % ----------------------------------------------------------
        % 5.7: Cell voltage constraints
        % ----------------------------------------------------------
        % Particularly important during CV phase to avoid overcharge
        
        con = [con, v_cell_min <= v_cell_ell];%#ok<AGROW>
        con = [con, v_cell_ell <= v_cell_max];%#ok<AGROW>
        
        
        % ----------------------------------------------------------
        % 5.8: Number of engaged cells bounds (INTENTIONALLY OMITTED)
        % ----------------------------------------------------------
        % NOTE: Unlike discharge optimizer, there is no Ns_min constraint.
        % This allows all cells to be bypassed when they reach target SOC.
        % The optimizer naturally engages cells that need charging and
        % bypasses cells that have reached the target.
        
    end  % end horizon loop
    

    %%% ================================================================
    %  SECTION 6: TERMINAL CONSTRAINTS
    %%%  ================================================================
    %  Constraints on final state (k = Np + 1)
    
    % Terminal SOC bounds
    con = [con, z_cell_min <= z_cell(:, Np+1)];
    con = [con, z_cell(:, Np+1) <= z_cell_max];
    
    % Terminal temperature bounds
    con = [con, T_cell_min <= T_cell(:, Np+1)];
    con = [con, T_cell(:, Np+1) <= T_cell_max];
    

    %%% ================================================================
    %  SECTION 7: OBJECTIVE FUNCTION
    %%%  ================================================================
    %
    %  OBJECTIVE: Drive all cells to target SOC (z_final)
    %
    %  The objective penalizes deviation of terminal SOC from target.
    %  This naturally creates the balancing behavior:
    %  - Cells below target: engaged to continue charging
    %  - Cells at target: can be bypassed
    %  - Result: all cells converge to z_final
    %
    %  NOTE: There is no explicit current tracking or minimum current.
    %  The optimizer charges cells because that's the only way to
    %  reduce the SOC deviation penalty.
    %  ================================================================
    
    obj = 0;
    
    % ----------------------------------------------------------
    % 7.1: Terminal SOC balancing cost
    % ----------------------------------------------------------
    % Penalize deviation of terminal SOC from target (z_final).
    % All cells should reach the same final SOC.
    %
    % This is the ONLY objective — the optimizer will:
    % - Engage cells that are below z_final (to charge them)
    % - Bypass cells that have reached z_final (to stop charging them)
    % - Naturally balance the pack toward uniform SOC
    
    z_term = z_cell(:, Np+1);
    z_target = z_final;
    dz = z_term - z_target;
    dz_norm = dz ./ z_scale;
    
    obJ_SOC = w_socBalTerm_cv * sum(dz_norm.^2) / Ns;
    obj = obj + obJ_SOC;
    

    %%% ================================================================
    %  SECTION 8: BUILD OPTIMIZER
    %%%  ================================================================
    
    % Outputs: First-step control actions (for MPC)
    outs = { ...
        S_cell(:,1), ...        % Cell engagement decisions
        i_pack(1), ...          % Pack current (charging, negative)
        v_cell(:,1)};           % Cell voltages
    
    % Parameters: Inputs that change each MPC call
    params = { ...
        z_cell_prev_par, ...        % Current SOC
        i_RC_1_cell_prev_par, ...   % Current RC1 state
        i_RC_2_cell_prev_par, ...   % Current RC2 state
        T_cell_prev_par, ...        % Current temperatures
        SOH_cell_prev_par, ...      % Cell SOH values (currently unused)
        v_oc_prev_par};             % Pre-computed OCV
    
    % Build the optimizer object
    opt = optimizer(con, obj, ops, params, outs);

end