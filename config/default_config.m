% FILE: rbs_sim/config/default_config.m
% Pure configuration knobs. NO chemistry objects. NO derived coefficients.
function cfg = default_config()
    
    cfg = struct();
    
    % -------------------------------------------------------------------------
    % Chemistry & data
    % -------------------------------------------------------------------------
    cfg.CHEMISTRY_TYPE     = 'LFP';     % 'LFP' or 'NMC'
    cfg.USE_EMPIRICAL_DATA = true;      % Use empirical cell data if available
    
    % -------------------------------------------------------------------------
    % Pack configuration
    % -------------------------------------------------------------------------
    cfg.Ns = 20;    % [-] Number of cells in series
    cfg.Np = 1;     % [-] Number of parallel strings
    
    % -------------------------------------------------------------------------
    % Switch hardware
    % -------------------------------------------------------------------------
    % Effective on-state resistance of each switch unit [Ohm].
    % Used consistently in both plant and optimizer models.
    cfg.r_s = 1e-3;   % [Ohm] Switch on-state resistance (series = bypass)
    
    % -------------------------------------------------------------------------
    % Timing
    % -------------------------------------------------------------------------
    cfg.Tstep     = 1.0;                                % [s] Sample time
    cfg.Tsimtotal = 1800; %1 * 3600;                    % [s] Simulation time 
    cfg.simSteps  = round(cfg.Tsimtotal / cfg.Tstep);   % [-] Number of simulation steps
    cfg.timeLimit = 1.0;   % seconds
    
    % -------------------------------------------------------------------------
    % Initial conditions
    % -------------------------------------------------------------------------
    % SOC initial distribution
    cfg.z_cell_init_mean   = 0.8;       % [-] Mean initial SOC
    cfg.z_cell_init_spread = 0.001;     % [-] Initial SOC std deviation
    
    cfg.SOH_cell_init_mean   = 0.98;    % [-] Mean initial SOH
    cfg.SOH_cell_init_spread = 0.01;    % [-] Initial SOH std deviation 
    
    % -------------------------------------------------------------------------
    % State machine initial state
    % -------------------------------------------------------------------------
    cfg.stateInit_name      = 'DISCHARGE_HIGH';
    
    % -------------------------------------------------------------------------
    % EOL termination configuration
    % -------------------------------------------------------------------------
    cfg.EOL = struct();
    cfg.EOL.threshold = 0.80;       % [-] SOH threshold for EOL
    cfg.EOL.mode      = "any_cell"; % "any_cell" or "pack_mean"
    cfg.EOL.use_partial_episode_cyc_for_check = false;
    switch cfg.EOL.mode
        case "any_cell",  cfg.EOL.mode_id = uint8(1);
        case "pack_mean", cfg.EOL.mode_id = uint8(2);
    end    
    
    % -------------------------------------------------------------------------
    % Charging config (user knobs only; no derived V thresholds)
    % -------------------------------------------------------------------------
    %
    % Unified structure for both CC_CV and FAST_TO_SOC strategies.
    %
    % VOLTAGE HIERARCHY (low to high):
    %   V_ENTER     - Enter CV/VLIM mode when v_max reaches this
    %   V_REGULATE  - PI controller setpoint
    %   V_WARN      - Log warning above this
    %   V_CEILING   - Absolute maximum (datasheet), never exceed
    %
    % STRATEGY DIFFERENCES:
    %   CC_CV:       V_REGULATE derived from OCV(SOC_target)
    %                Exit condition: current taper
    %
    %   FAST_TO_SOC: V_REGULATE = V_CEILING - offset (fixed margin below ceiling)
    %                Exit condition: SOC reaches target (or voltage drops -> return to CC)
    %    
    cfg.CHARGING = struct();
    
    % Strategy Selection 
    % Options:
    %   'AUTO'        -> NMC: CC-CV, LFP: FAST_TO_SOC (ceiling limiter)
    %   'CC_CV'       -> Force conventional CC->CV
    %   'FAST_TO_SOC' -> Force CC bulk + voltage ceiling limiter + stop at SOC target    
    cfg.CHARGING.strategy_requested = 'FAST_TO_SOC';

    % AUTO Resolution (chemistry -> preferred strategy) 
    cfg.CHARGING.AUTO_map.LFP = 'FAST_TO_SOC';  % LFP: flat OCV, exit on SOC
    cfg.CHARGING.AUTO_map.NMC = 'CC_CV';        % NMC: sloped OCV, exit on taper
    
    % Target SOC (affects both strategies differently) 
    cfg.CHARGING.SOC_target = 0.9;              % Target SOC for charging

    % Margins (common to both strategies)
    cfg.CHARGING.enter_margin_V = 0.010;        % Enter CV/VLIM at V_REGULATE - margin
    cfg.CHARGING.warn_margin_V  = 0.030;        % Warn at V_CEILING - margin
    
    % CC_CV Strategy Parameters
    cfg.CHARGING.CC_CV.margin_above_OCV_V = 0.000; % V_REGULATE = OCV(SOC_target) + margin
    cfg.CHARGING.CC_CV.taper_frac         = 0.05;  % Exit when |I| < 5% of I_chg_max
    cfg.CHARGING.CC_CV.taper_hold_s       = 60;    % Hold taper condition for 60s
    cfg.CHARGING.CC_CV.min_dwell_s        = 10;    % Min time in CV before exit check
    
    % FAST_TO_SOC Strategy Parameters
    cfg.CHARGING.FAST_TO_SOC.offset_below_ceiling_V = 0.010; % V_REGULATE = V_CEILING - offset
    cfg.CHARGING.FAST_TO_SOC.exit_margin_V          = 0.020; % Return to CC if v < V_REGULATE - margin
    cfg.CHARGING.FAST_TO_SOC.min_dwell_s            = 5;     % Anti-chatter dwell time
    
    % CC Phase
    cfg.CHARGING.CC_min_dwell_s = 10; % Min time in CC before entering CV/VLIM
    
    % PI Controller
    cfg.CHARGING.Kp       = 25.0;
    cfg.CHARGING.Ki       = 0.25;
    cfg.CHARGING.tau_filt = 2.0;
    cfg.CHARGING.slew_up  = 0.15;
    cfg.CHARGING.slew_dn  = 0.25;
    
    % -------------------------------------------------------------------------
    % Passive balancing knobs
    % -------------------------------------------------------------------------
    cfg.BALANCING_CONFIG = struct();

    % Master Enable/Disable
    cfg.BALANCING_CONFIG.enabled = false;

    % Hardware Parameters
    cfg.BALANCING_CONFIG.i_balance_max = 0.150; % Max bleed current [A] (MOSFET limit)
    cfg.BALANCING_CONFIG.R_balance = 40;         % Balancing resistor [Ohms]
    
    % Activation Thresholds 
    cfg.BALANCING_CONFIG.soc_threshold_pct  = 1.0; % Activate when SOC spread > 1%
    cfg.BALANCING_CONFIG.soc_hysteresis_pct = 0.5; % Deactivate at threshold - 0.5%
    
    % Strategy:
    %   'above_mean'   -> bleed cells above mean SOC by mean_offset_pct
    %   'top_n'        -> bleed top fraction top_n_frac
    %   'above_target' -> bleed any cell above above_target_soc
    cfg.BALANCING_CONFIG.strategy        = 'above_mean'; % Balance cells above mean SOC
    cfg.BALANCING_CONFIG.mean_offset_pct = 0.1;          % Balance if SOC > mean + 0.1%
    cfg.BALANCING_CONFIG.top_n_frac      = 0.20;         % for 'top_n'
    cfg.BALANCING_CONFIG.above_target_soc = 0.70;        % for 'above_target'
    
    % When balancing is allowed (OR logic)
    cfg.BALANCING_CONFIG.balance_during_charge_cc = false; % During CC charge (wastes energy)
    cfg.BALANCING_CONFIG.balance_during_charge_cv = true;  % During CV charge (most effective)
    cfg.BALANCING_CONFIG.balance_during_rest       = true;  % During rest periods
    
    % Thermal Coupling 
    cfg.BALANCING_CONFIG.thermal_coupling = true; % Add balancing heat to cell thermal model
    
    % Per-Cell Hysteresis
    cfg.BALANCING_CONFIG.cell_hysteresis_pct = 0.1; % per-cell SOC hysteresis (percentage points)
    cfg.BALANCING_CONFIG.top_n_margin        = 1;   % extra ranks allowed to "stick" ON

    
    % -------------------------------------------------------------------------
    % Drive cycle
    % -------------------------------------------------------------------------
    cfg.DriveCycleFile    = 'data/WLTC_Class3b.mat';
    cfg.N_cycles_required = 1;
    cfg.PlotFigures       = false;
    
    switch upper(cfg.CHEMISTRY_TYPE)
        case 'LFP'
            cfg.CellChemistry = 'FILE';
            cfg.CellParamFile = 'data/lfp_cell_data.mat';
        case 'NMC'
            cfg.CellChemistry = 'FILE';
            cfg.CellParamFile = 'data/nmc_cell_data.mat';
        otherwise
            error('Unsupported chemistry type: %s', cfg.CHEMISTRY_TYPE);
    end
    
    % -------------------------------------------------------------------------
    % State machine thresholds (heuristics / transitions)
    % -------------------------------------------------------------------------
    cfg.stateMachineParams = struct();
    cfg.stateMachineParams.SOC_THR_DISHIGH_DISLOW      = 0.40;
    cfg.stateMachineParams.SOC_THR_DISHIGH_DISLOW_HYST = 0.02;
    cfg.stateMachineParams.SOC_THR_DISLOW_REST         = 0.20;
    
    cfg.stateMachineParams.SOC_THR_CHGLOW_CHGHIGH      = 0.75;
    cfg.stateMachineParams.SOC_THR_CHGLOW_CHGHIGH_HYST = 0.02;
    cfg.stateMachineParams.SOC_THR_CHGHIGH_REST        = 0.9;
    cfg.stateMachineParams.SOC_THR_CHGHIGH_REST_BAL    = 0.001;
    
    cfg.stateMachineParams.REST_DISC_END = 300;
    cfg.stateMachineParams.REST_CHG_END  = 300;
    
    % -------------------------------------------------------------------------
    % Warning margins
    % -------------------------------------------------------------------------
    cfg.WARNING_MARGINS = struct();
    cfg.WARNING_MARGINS.soc = 0.02;
    cfg.WARNING_MARGINS.v   = 0.01;
    cfg.WARNING_MARGINS.T   = 3.0;
    
    % -------------------------------------------------------------------------
    % Numerics
    % -------------------------------------------------------------------------
    cfg.NUMERICS = struct();
    cfg.NUMERICS.eps_div0    = 1e-9;
    cfg.NUMERICS.eps_compare = 1e-12;
    cfg.NUMERICS.TRACKING_POWER_EPS = 1e-9;
    cfg.NUMERICS.CURT_TOL = 1e-7;
    
    % ------------------------------------------------------------------------
    % Logging
    % ------------------------------------------------------------------------
    cfg.LOGGING = struct();
    cfg.LOGGING.progress_every_steps  = 50;
    cfg.LOGGING.cv_debug_every_steps  = 0;
    cfg.LOGGING.print_discharge_entry = true;
    cfg.LOGGING.print_episode_close   = true;
    
    % ------------------------------------------------------------------------
    % Delta-spread estimation (Section VI-A.2)
    % ------------------------------------------------------------------------
    cfg.delta_spread.m_min    = [];   % lowest cardinality in the manuscript grid (N=20 specific)
    % cfg.delta_spread.nSamples retired: delta_m is now computed by exact
    % enumeration over all C(N,m) patterns via tcst_compute_delta_exact.

    % ------------------------------------------------------------------------
    % Metrics thresholds
    % ------------------------------------------------------------------------
    cfg.METRICS = struct();
    cfg.METRICS.high_C_threshold = 1.0;
    cfg.METRICS.T_threshold_C    = 45;
    
    % -------------------------------------------------------------------------
    % Weights + MPC horizon + solver knobs
    % -------------------------------------------------------------------------
    cfg.w = struct();
    % Stage-cost weights, manuscript Eq. (14):
    %   J_total = w_SOH * J_SOH(ell) + w_SOC * J_SOC(ell) + w_lambda * lambda(ell)
    cfg.w.SOH         = 10;       % w_SOH    (SOH-weighted engagement)
    cfg.w.SOC         = 4;     % w_SOC    (inter-step SOC imbalance)
    cfg.w.lambda      = 1000;   % w_lambda (power-curtailment slack)
    % --- Legacy terms (commented out; not in manuscript Eq. 14) ----------
    %   Switching terms (within-horizon and previous-step) — see V-B audit
    %   item #1: switching commented out, retained in archive for traceback.
    % cfg.w.swNs_hor    = 0.02;     % Switching within horizon
    % cfg.w.swNs_prev   = 0.2;      % Switching from previous step
    %   Cardinality term — not used by current optimizer objective.
    % cfg.w.card        = 0.05;     % Cardinality weight

    cfg.w.socBalTerm_cv = 200.0;  % Terminal SOC (CV/balance mode)
    cfg.w.I             = 10000.0; % Current tracking
    cfg.w.v             = 100000.0; % Voltage tracking (CV mode)

    % -------------------------------------------------------------------------
    % Pack limits knobs
    % -------------------------------------------------------------------------
    cfg.limits = struct();
    cfg.limits.v_pack_min_frac      = 0.7;  % [-]  v_pack_min = v_cell_nom * Ns * frac
    cfg.limits.n_inv_vpack_bp       = 12;   % [-]  Legacy: fixed SOS2 bp count (ignored when inv_vpack_max_err_mV is set)
    cfg.limits.inv_vpack_max_err_mV = 2.0;  % [mV] Pack-level voltage-equivalent error budget for 1/v_pack PWL.
                                            %      Controls bp count via buildInvVpackPWLAuto.
                                            %      Looser than OCV (0.5 mV/cell) because:
                                            %        (a) error only corrupts one power constraint, not state prediction;
                                            %        (b) receding horizon corrects it every step.
                                            %      Relative current error at 55 V: tol/(Ns*v) = 2e-3*Ns/(Ns*55) = 0.036%
                                            %      Run run_pwl_tol_sweep.m to validate this choice.

    % -------------------------------------------------------------------------
    % OCV piecewise-linear approximation knobs
    % -------------------------------------------------------------------------
    cfg.ocv = struct();
    cfg.ocv.max_error_mV = 0.5;   % [mV]  Target max PWL approximation error per cell
    cfg.ocv.max_points   = 30;    % [-]   Breakpoint count cap

    cfg.mpc = struct();
    cfg.mpc.Np             = 10;   % [-] Prediction horizon length N_p (steps)
    cfg.mpc.soh_normalize  = false;
    cfg.mpc.enable_sorting  = true;   % default ON
    cfg.mpc.enable_monotone = true;   % default ON

    cfg.mpc.delta_P_curtail = 0.01;   % 1% maximum power curtailment

    cfg.mpc.socSpread.Delta_low = 0.03;
    cfg.mpc.socSpread.Delta_high = 0.06;
    cfg.mpc.socSpread.z_low = 0.25;
    cfg.mpc.socSpread.z_high = 0.40;
    cfg.mpc.socSpread.slew_rate = 0.005;

    % Ranking score component flags.
    % Set use_rho_v = false to zero out the voltage/curtailment gradient
    % component and use only rho_SOH + rho_SOC for cell ordering.
    % Default true preserves existing behaviour (Variants A and D).
    cfg.ranking.use_rho_v = true;

    cfg.solver = struct();
    cfg.solver.name    = 'gurobi';
    % Gurobi thread count per solve.
    %   For single sequential runs:  set to 4 (B&B benefits up to ~4 threads).
    %   Inside parfor workers:       set to 1 (each worker owns its cores).
    %   0 = let Gurobi decide (uses all cores — do NOT use inside parfor).
    cfg.solver.threads = 4;

    % -------------------------------------------------------------------------
    % Initial condition clamp bounds (match hard SOC limits from chemistry)
    % -------------------------------------------------------------------------
    cfg.limits.z_min = 0.05;    % [-]  SOC lower clamp in buildInitialState
    cfg.limits.z_max = 1.00;    % [-]  SOC upper clamp in buildInitialState

    % -------------------------------------------------------------------------
    % Initial condition spread (aliased for buildInitialState)
    % Bug-2 fix: buildInitialState reads cfg.init.soc_std / cfg.init.soh_std,
    % but default_config previously only set cfg.z_cell_init_spread /
    % cfg.SOH_cell_init_spread.  The two names are kept in sync here.
    % -------------------------------------------------------------------------
    cfg.init = struct();
    cfg.init.soc_std = cfg.z_cell_init_spread;    % 0.001
    cfg.init.soh_std = cfg.SOH_cell_init_spread;  % 0.01

    % -------------------------------------------------------------------------
    % Drive-cycle descriptor (read by buildDriveCycle)
    % Bug-3 fix: buildDriveCycle reads cfg.driveCycle.type but default_config
    % previously only defined cfg.DriveCycleFile / cfg.N_cycles_required.
    % Default is the nominal WLTC Class-3 run; P_const is only used when
    % type == 'constant'.
    % -------------------------------------------------------------------------
    cfg.driveCycle = struct();
    cfg.driveCycle.type    = 'wltc';   % nominal drive cycle ('wltc' | 'constant' | 'diagnostic')
    cfg.driveCycle.P_const = NaN;      % [W] used only when type == 'constant'

    % -------------------------------------------------------------------------
    % Debug / ablation knobs
    % -------------------------------------------------------------------------
    cfg.DEBUG = struct();
    
    % Options:
    %   "full"      : original objective
    %   "zero"      : Objective = 0, and diagnostic objective outputs forced to 0
    %   "no_soc"    : keep SOH + curtailment objective, remove SOC objective
    %   "soc_const" : replace (dz / Delta_SOCterm_max_par)^2 by constant scaling
    cfg.DEBUG.discharge_objective_mode = "full";
    
    % If finite, overrides cfg.mpc.delta_P_curtail inside discharge parameter build.
    % Use 0.10 or 0.99 for diagnostics.
    cfg.DEBUG.delta_P_curtail_override = NaN;
    
    % Save first-step raw YALMIP diagnostics in u_mpc.raw_diagnostics.
    cfg.DEBUG.keep_diagnostics = false;
    
    % Save solver input/output and print Gurobi messages.
    cfg.DEBUG.solver_io = false;    

end