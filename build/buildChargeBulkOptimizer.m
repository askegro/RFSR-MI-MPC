% ------------------------------------------------------------------
% FUNCTION: buildChargeBulkOptimizer
% ------------------------------------------------------------------
% PURPOSE:
%   Builds a YALMIP optimizer object for MPC-based bulk charging control
%   of a Reconfigurable Battery System (RBS).
%
% CHARGING PHASE:
%   This optimizer handles the BULK (CC) charging phase where:
%   - All cells are engaged (no reconfiguration)
%   - All cells receive the same current
%   - Current tracks a reference profile (typically constant)
%   - Charging continues until voltage limit is reached
%
% CONTROL OBJECTIVE:
%   - Track a reference current profile (I_ref)
%   - Respect voltage, SOC, and thermal limits
%
% SIMPLIFICATIONS vs DISCHARGE OPTIMIZER:
%   - No cell switching (S_cell) — all cells engaged
%   - No McCormick relaxations — no bilinear terms
%   - No SOC/SOH balancing — all cells get same current
%   - Pre-computed OCV — passed in as parameter, not calculated
%
% BATTERY MODEL:
%   - 2nd-order RC equivalent circuit per cell
%   - OCV pre-computed externally (static across horizon)
%   - Lumped thermal dynamics with I²R heat generation
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
%                 [i_pack, v_cell] = opt(params)
%
% AUTHOR: [Your name]
% DATE:   [Date]
% ------------------------------------------------------------------
function opt = buildChargeBulkOptimizer(constants)
    

    %%% ================================================================
    %  SECTION 1: UNPACK CONSTANTS
    %%%  ================================================================
    %  Each constant on its own line for easy commenting/modification.
    %  Grouped by category for readability.
    cfg                 = constants.cfg;
    models              = constants.models;
    solver              = constants.solver;
    limits              = constants.limits;
    %scale               = constants.scale;

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
    i_pack_min = limits.i_pack_min;  % Max charging current (negative) [A]
    i_pack_max = 0;                     % No discharging allowed in bulk charge
    
    % --- Current tracking weight ---
    w_I = w.I;                % Weight for current tracking objective
    I_chg_max = limits.i_chg_max_mag;    % Scaling factor for current [A]
    
    % --- Display configuration info ---
    % fprintf('  [Charge Bulk] All cells engaged, tracking I_ref\n');
    % fprintf('  [Charge Bulk] Current bounds: [%.2f, %.2f] A\n', i_pack_min, i_pack_max);
    % fprintf('  [Charge Bulk] Using pre-computed OCV (static across horizon)\n');


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
    
    % --- Reference current over horizon ---
    I_ref_par = sdpvar(Np, 1);         % Reference current profile [A]
    
    % --- Pre-computed OCV ---
    % OCV is computed externally from current SOC and passed in.
    % This avoids nonlinearity but assumes OCV is static across horizon.
    % For short horizons or slow charging, this is acceptable.
    v_oc_prev_par = sdpvar(Ns, 1);            % Pre-computed OCV [V]
    
    % --- Cell health ---
    SOH_cell_prev_par = sdpvar(Ns, 1);        % Cell SOH values
    
    % --- Dummy parameters (for interface compatibility) ---
    % These are declared to maintain a consistent parameter interface
    % with other optimizers (e.g., discharge). They are NOT used in
    % this optimizer's constraints or objectives.
    %P_pack_req_par = sdpvar(Np, 1);    % (unused) Power request
    %i_pack_LB_par = sdpvar(Np, 1);     % (unused) Current lower bound
    %i_pack_HB_par = sdpvar(Np, 1);     % (unused) Current upper bound
    %S_cell_prev_par = sdpvar(Ns, 1);          % (unused) Previous engagement


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
    % NOTE: In bulk charging, all cells receive the same current.
    % There is no cell switching (S_cell) — all cells are engaged.
    i_pack = sdpvar(Np, 1);                  % Pack current [A] (same for all cells)
    v_cell = sdpvar(Ns, Np, 'full');         % Cell terminal voltages [V]


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
        i_pack_ell = i_pack(ell);
        v_cell_ell = v_cell(:,ell);
        
        % All cells receive the same current (all engaged)
        i_cell_ell = i_pack_ell * ones(Ns, 1);
        
        
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
        % 5.4: State dynamics
        % ----------------------------------------------------------
        % SOC: Coulomb counting (negative current increases SOC)
        % RC branches: Discrete-time first-order dynamics
        % Voltage: Kirchhoff's voltage law around cell
        %
        % NOTE: OCV is pre-computed and static across horizon.
        % This is an approximation valid for short horizons or slow charging.
        
        con = [con, z_cell(:,ell+1) == z_cell_ell - i_cell_ell * T_step ./ Q_cell_As];%#ok<AGROW> 
        con = [con, i_RC_1_cell(:,ell+1) == a1 * i_RC_1_cell_ell + b1 * i_cell_ell];%#ok<AGROW> 
        con = [con, i_RC_2_cell(:,ell+1) == a2 * i_RC_2_cell_ell + b2 * i_cell_ell];%#ok<AGROW> 
        con = [con, v_cell_ell == v_oc_prev_par - R0*i_cell_ell - R1*i_RC_1_cell_ell - R2*i_RC_2_cell_ell];%#ok<AGROW> 
        
        
        % ----------------------------------------------------------
        % 5.5: Thermal dynamics
        % ----------------------------------------------------------
        % Heat generation: Q_dot = I²R
        % All cells generate the same heat (same current)
        %
        % NOTE: i_pack_ell^2 is nonconvex but handled by the solver.
        % This works because it appears only in an equality constraint
        % with a linear temperature model.
        
        q_heat = R0 * i_pack_ell^2;           % Heat per cell [W]
        Qdot = q_heat * ones(Ns, 1);        % Same for all cells
        
        con = [con, T_cell(:,ell+1) == T_amb + a_th * (T_cell_ell - T_amb) + b_th * Qdot];%#ok<AGROW> 
        
        % Temperature limits
        con = [con, T_cell_min <= T_cell(:,ell+1)];%#ok<AGROW> 
        con = [con, T_cell(:,ell+1) <= T_cell_max];%#ok<AGROW> 
        
        
        % ----------------------------------------------------------
        % 5.6: Cell voltage constraints
        % ----------------------------------------------------------
        % Particularly important during charging to avoid overcharge
        
        con = [con, v_cell_min <= v_cell_ell];%#ok<AGROW> 
        con = [con, v_cell_ell <= v_cell_max];%#ok<AGROW> 
        
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
    %  OBJECTIVE: Track reference current profile
    %
    %  In bulk charging, the goal is to follow a prescribed current
    %  (typically constant CC phase). There is no cell selection
    %  freedom, so no SOC/SOH balancing objectives.
    %  ================================================================
    
    obj = 0;
    
    % ----------------------------------------------------------
    % 7.1: Current tracking cost
    % ----------------------------------------------------------
    % Minimize squared deviation from reference current (normalized)
    
    di = i_pack(:) - I_ref_par(:);
    di_norm = di ./ I_chg_max;
    obj_I = w_I * sum(di_norm.^2);
    obj = obj + obj_I;
    

    %%% ================================================================
    %  SECTION 8: BUILD OPTIMIZER
    %%%  ================================================================
    
    % Outputs: First-step control actions (for MPC)
    outs = { ...
        i_pack(1), ...          % Pack current (charging, negative)
        v_cell(:,1)};           % Cell voltages
    
    % Parameters: Inputs that change each MPC call
    % NOTE: Some parameters are for interface compatibility and not used.
    params = { ...
        z_cell_prev_par, ...        % Current SOC
        i_RC_1_cell_prev_par, ...   % Current RC1 state
        i_RC_2_cell_prev_par, ...   % Current RC2 state
        T_cell_prev_par, ...        % Current temperatures
        I_ref_par, ...              % Reference current profile
        v_oc_prev_par, ...          % Pre-computed OCV
        SOH_cell_prev_par};         % Cell SOH values
        % P_pack_req_par, ...         % (unused) Power request
        % i_pack_LB_par, ...          % (unused) Current lower bound
        % i_pack_HB_par, ...          % (unused) Current upper bound
        % S_cell_prev_par, ...        % (unused) Previous engagement    
    
    % Build the optimizer object
    opt = optimizer(con, obj, ops, params, outs);

end

