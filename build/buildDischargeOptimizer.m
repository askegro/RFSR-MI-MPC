function [opt, varargout] = buildDischargeOptimizer(constants)
% Optional second output: varargout{1} = S_cell (binvar handle, Ns x Np).
% Used by the warm-start variant (A_WS) to inject a MIP-start hint via
% assign(S_cell_handle, prev_S) before each optimizer call.
% Callers that request only one output are unaffected.
% BUILDDISCHARGEOPTIMIZER  Build the YALMIP optimizer for discharge MPC.
%
% Purpose
%   Compile the discharge optimizer once at startup and reuse it at every
%   MPC step. The constraint graph is fixed at build time; all time-varying
%   data are supplied as runtime parameters.
%
% Parameter order
%   The runtime parameter order must match PREPARE_DISCHARGE_PARAMS exactly:
%
%     1  z_cell_prev_par        Ns x 1   cell SOC at step k
%     2  i_RC_1_cell_prev_par   Ns x 1   RC-1 current at step k
%     3  i_RC_2_cell_prev_par   Ns x 1   RC-2 current at step k
%     4  T_cell_prev_par        Ns x 1   cell temperature at step k
%     5  P_pack_req_par         Np x 1   requested pack power over horizon
%     6  sgnP_par               Np x 1   sign of requested power (+1 / -1)
%     7  m_ocv_par              Ns x 1   affine OCV slope dVoc/dSOC (V/SOC)
%     8  b_ocv_par              Ns x 1   affine OCV intercept (V)
%     9  i_pack_upper_par       Np x 1   upper pack-current bound, manuscript A1
%    10  i_pack_lower_par       Np x 1   lower pack-current bound, manuscript A1
%    11  q_sq_max_par           Np x 1   upper bound on q_sq = i_pack^2 per step
%    12  lambda_max_par         Np x 1   curtailment slack upper bound
%    13  Q_cell_As_par          Ns x 1   effective cell capacity (As)
%    14  SOH_inv_par            Ns x 1   SOH-inverse weighting per cell (= 1/SOH_i)
%    15  S_prev_par             Ns x 1   previous-step switch state
%    16  lambda_scale_par        Np x 1   current normalisation (1/A) per step
%    17  Delta_SOCterm_max_par  1  x 1   maximum admissible terminal SOC spread
%    18  Ns_min_stage_par       Np x 1   per-stage minimum engaged-cell count
%
% Outputs
%   The optimizer returns first-step commands and diagnostic objective terms:
%     - switch decision S_cell(:,1)
%     - first-step pack current i_pack(1)
%     - first-step cell / engaged / pack voltages
%     - first-step curtailment slack lambda(1)
%     - objective components J_SOH, J_SOC, J_sw, J_sw_prev, J_curt
%     - terminal SOC spread dzT_terminal
%
% Notes
%   - Cell-indexed quantities are column vectors (Ns x 1).
%   - Stage-indexed quantities are column vectors (Np x 1).
%   - Cell-by-time quantities are matrices: rows = cells, columns = time.


    %% --------------------------------------------------------------------
    %  Unpack constants
    %  --------------------------------------------------------------------
    cfg             = constants.cfg;
    Ns              = cfg.Ns;
    T_step          = cfg.Tstep;
    Np              = cfg.mpc.Np;

    elec            = constants.models.elec;
    R0              = elec.R0;
    R1              = elec.R1;
    R2              = elec.R2;
    r_s             = elec.r_s;        
    a1              = elec.a1;  a2 = elec.a2;
    b1              = elec.b1;  b2 = elec.b2;

    therm           = constants.models.therm;
    T_amb           = therm.T_amb;
    a_th            = therm.a_th;
    b_th            = therm.b_th;

    limits                  = constants.limits;
    v_cell_min              = limits.v_cell_min;
    v_cell_max              = limits.v_cell_max;
    v_pack_min              = limits.v_pack_min;
    v_pack_max              = limits.v_pack_max;
    i_pack_min              = limits.i_pack_min;
    i_pack_max              = limits.i_pack_max;
    z_cell_min              = limits.z_cell_min;
    z_cell_max              = limits.z_cell_max;
    T_cell_min              = limits.T_cell_min;
    T_cell_max              = limits.T_cell_max;
    Ns_min_voltage_safe     = limits.Ns_min_voltage_safe;

    w               = cfg.w;
    w_SOH           = w.SOH;          % manuscript w_SOH    (Eq. 14)
    w_SOC           = w.SOC;          % manuscript w_SOC    (Eq. 14)
    w_lambda        = w.lambda;       % manuscript w_lambda (Eq. 14)
    % --- Legacy switching weights (V-B: commented out, not in Eq. 14) ---
    % w_swHor       = w.swNs_hor;
    % w_swPrev      = w.swNs_prev;

    pwl             = constants.models.pwl.invVpack;
    vgrid           = pwl.vgrid;
    invgrid         = pwl.invgrid;
    n_vpack_bp      = pwl.n;

    ops             = constants.solver.ops;

    SOH_EOL         = cfg.EOL.threshold;
    SOH_EOL_inv     = 1/SOH_EOL;


    %% --------------------------------------------------------------------
    %  Runtime parameters
    %  --------------------------------------------------------------------
    %  Supplied fresh at every MPC call. Order must match PREPARE_DISCHARGE_PARAMS.

    % Current measured / estimated cell state
    z_cell_prev_par         = sdpvar(Ns, 1);
    i_RC_1_cell_prev_par    = sdpvar(Ns, 1);
    i_RC_2_cell_prev_par    = sdpvar(Ns, 1);
    T_cell_prev_par         = sdpvar(Ns, 1);

    % Horizon-wise power request and sign
    P_pack_req_par          = sdpvar(Np, 1);   % P_req > 0: discharge, < 0: charge
    sgnP_par                = sdpvar(Np, 1);   % +1 or -1

    % Affine OCV model linearised about current SOC
    m_ocv_par               = sdpvar(Ns, 1);          % slope  m_i(ell), V/SOC
    b_ocv_par               = sdpvar(Ns, 1);          % intercept b_i(ell), V

    % Per-stage asymmetric pack-current bounds and quadratic envelope bounds
    i_pack_U_par        = sdpvar(Np, 1);   % manuscript \bar{i}_{pack}(ell)
    i_pack_L_par        = sdpvar(Np, 1);   % manuscript \underline{i}_{pack}(ell)
    q_sq_U_par            = sdpvar(Np, 1);   % upper bound on q_sq per step

    % Curtailment, capacity and weighting parameters
    lambda_U_par          = sdpvar(Np, 1);   % lambda^max(ell): curtailment upper bound
    Q_cell_As_par           = sdpvar(Ns, 1);          % effective cell capacity Q_i (As)
    SOH_inv_par             = sdpvar(Ns, 1);          % 1/SOH_i weighting per cell
    S_prev_par              = sdpvar(Ns, 1);          % S(ell-1): switch state at previous step
    lambda_scale_par         = sdpvar(Np, 1);   % current normalisation 1/A per step
    Delta_SOCterm_max_par   = sdpvar(1, 1);           % Delta_SOC_max: terminal SOC spread limit

    % Stage-varying engaged-cell lower bound
    Ns_min_stage_par        = sdpvar(Np, 1);



    %% --------------------------------------------------------------------
    %  Decision variables
    %  --------------------------------------------------------------------

    % State trajectories (columns 1..N_p+1; column 1 = initial condition)
    z_cell              = sdpvar(Ns, Np+1, 'full');    % SOC_i(ell)
    i_RC_1_cell         = sdpvar(Ns, Np+1, 'full');    % i_RC1_i(ell)
    i_RC_2_cell         = sdpvar(Ns, Np+1, 'full');    % i_RC2_i(ell)
    T_cell              = sdpvar(Ns, Np+1, 'full');    % T_i(ell)

    % Switching and current variables
    S_cell              = binvar(Ns, Np, 'full');      % S_i(ell) in {0,1}
    i_pack              = sdpvar(Np, 1);       % i_pack(ell)
    i_cell              = sdpvar(Ns, Np, 'full');      % i_i(ell)

    % Voltage variables
    v_cell              = sdpvar(Ns, Np, 'full');      % v_i(ell)
    v_cell_eng          = sdpvar(Ns, Np, 'full');      % v_eng_i(ell)
    v_pack              = sdpvar(Np, 1);       % v_pack(ell)

    % Epigraph variable for i_pack^2 (manuscript: q_sq(ell))
    q_sq                = sdpvar(Np, 1);       % q_sq(ell) >= i_pack(ell)^2

    % Gated heat auxiliary: q_gen_i(ell) = q_sq(ell) if S_i=1, else 0
    % Manuscript notation: q_i^gen(ell)
    q_gen_cell          = sdpvar(Ns, Np, 'full');

    % Power-curtailment slack (manuscript: lambda(ell))
    lambda        = sdpvar(Np, 1);

    % Terminal SOC spread auxiliaries
    SOCterm_U           = sdpvar(1, 1);
    SOCterm_L           = sdpvar(1, 1);
    DeltaSOCterm        = SOCterm_U - SOCterm_L;



    %% --------------------------------------------------------------------
    %  SOS2 inverse pack voltage: r_pack(ell) approx 1/v_pack(ell)
    %  Manuscript: alpha_j(ell) convex-combination weights, r_pack(ell)
    %  --------------------------------------------------------------------
    alpha               = sdpvar(n_vpack_bp, Np, 'full');  % alpha_j(ell)
    r_pack              = sdpvar(Np, 1);            % r_pack(ell) = approx 1/v_pack(ell)



    %% --------------------------------------------------------------------
    %  Constraints
    %  --------------------------------------------------------------------
    con = [];

    % --- Initial conditions ----------------------------------------------
    con = [con, named(z_cell(:,1)      == z_cell_prev_par,      'init_z_cell')];
    con = [con, named(i_RC_1_cell(:,1) == i_RC_1_cell_prev_par, 'init_iRC1')];
    con = [con, named(i_RC_2_cell(:,1) == i_RC_2_cell_prev_par, 'init_iRC2')];
    con = [con, named(T_cell(:,1)      == T_cell_prev_par,       'init_T_cell')];

    % Curtailment is nonneg by definition
    con = [con, lambda >= 0];


    % --- Horizon constraints ---------------------------------------------
    for ell = 1:Np

        % Aliases for stage ell
        z_cell_ell        = z_cell(:,ell);
        i_RC_1_ell        = i_RC_1_cell(:,ell);
        i_RC_2_ell        = i_RC_2_cell(:,ell);
        T_cell_ell        = T_cell(:,ell);
        S_ell             = S_cell(:,ell);
        i_pack_ell        = i_pack(ell);
        i_cell_ell        = i_cell(:,ell);
        v_cell_ell        = v_cell(:,ell);
        v_cell_eng_ell    = v_cell_eng(:,ell);
        v_pack_ell        = v_pack(ell);
        P_req_ell         = P_pack_req_par(ell);
        sgnP_ell          = sgnP_par(ell);
        q_sq_ell          = q_sq(ell);
        q_gen_ell         = q_gen_cell(:,ell);
        lambda_ell        = lambda(ell);
        i_pack_U_ell      = i_pack_U_par(ell);
        i_pack_L_ell      = i_pack_L_par(ell);
        q_sq_U_ell        = q_sq_U_par(ell);
        lambda_U_ell      = lambda_U_par(ell);


        % --- SOC bounds --------------------------------------------------
        con = [con, z_cell_min <= z_cell_ell];                           %#ok<AGROW>
        con = [con, z_cell_ell   <= z_cell_max];                         %#ok<AGROW>


        % --- Pack current bounds ------------------------------------------
        % Manuscript Appendix, eq:packCurrentBounds: sign-dependent asymmetric bounds.
        % Discharge: 0 <= i_pack <= iU_ell. Charge: iL_ell <= i_pack <= 0.
        con = [con, named(i_pack_L_ell <= i_pack_ell, sprintf('ell%d_i_pack_lower',      ell))]; %#ok<AGROW>
        con = [con, named(i_pack_ell   <= i_pack_U_ell, sprintf('ell%d_i_pack_upper',    ell))]; %#ok<AGROW>
        con = [con, named(i_pack_min   <= i_pack_ell, sprintf('ell%d_i_pack_hard_lower', ell))]; %#ok<AGROW>
        con = [con, named(i_pack_ell   <= i_pack_max, sprintf('ell%d_i_pack_hard_upper', ell))]; %#ok<AGROW>


        % --- Cell current: i_i(ell) = S_i(ell) * i_pack(ell) -------------
        % Manuscript Appendix, eq:currentLinearization: exact asymmetric Big-M product
        % reformulation using lower/upper pack-current bounds.
        % S_i=1: i_cell = i_pack.  S_i=0: i_cell = 0.
        con = [con,  i_cell_ell <= i_pack_U_ell*S_ell];                           %#ok<AGROW>
        con = [con,  i_cell_ell >= i_pack_L_ell*S_ell];                           %#ok<AGROW>
        con = [con,  i_cell_ell <= i_pack_ell - i_pack_L_ell*(1 - S_ell)];          %#ok<AGROW>
        con = [con,  i_cell_ell >= i_pack_ell - i_pack_U_ell*(1 - S_ell)];          %#ok<AGROW>


        % --- Discrete-time electrothermal dynamics -----------------------
        % Manuscript eq. (4): SOC, RC-1, RC-2 dynamics.
        con = [con, named(z_cell(:,ell+1) == z_cell_ell - i_cell_ell * T_step ./ Q_cell_As_par, ...
            sprintf('ell%d_soc_dynamics', ell))];                                                %#ok<AGROW>
        con = [con, i_RC_1_cell(:,ell+1) == a1*i_RC_1_ell + b1*i_cell_ell];                     %#ok<AGROW>
        con = [con, i_RC_2_cell(:,ell+1) == a2*i_RC_2_ell + b2*i_cell_ell];                     %#ok<AGROW>


        % --- Cell terminal voltage ---------------------------------------
        % Manuscript eq. (7): v_i = OCV(SOC_i) - R0*i_i - R1*i_RC1 - R2*i_RC2.
        % OCV is affine in SOC_i via the local linearisation (Appendix).
        con = [con, v_cell_ell == (m_ocv_par .* z_cell_ell + b_ocv_par) ...
                                - R0*i_cell_ell - R1*i_RC_1_ell - R2*i_RC_2_ell]; %#ok<AGROW>


        % --- Cell voltage safety limits ----------------------------------
        con = [con, v_cell_min <= v_cell_ell];                           %#ok<AGROW>
        con = [con, v_cell_ell   <= v_cell_max];                         %#ok<AGROW>


        % --- Engaged-cell voltage gating ---------------------------------
        % Manuscript eq. (8): v_eng_i = S_i * v_i.
        % McCormick linearisation using [v_cell_min, v_cell_max] bounds.
        % S_i=1: v_cell_eng = v_cell.  S_i=0: v_cell_eng = 0.
        con = [con, v_cell_eng_ell >= v_cell_min * S_ell];                              %#ok<AGROW>
        con = [con, v_cell_eng_ell <= v_cell_max * S_ell];                              %#ok<AGROW>
        con = [con, v_cell_eng_ell >= v_cell_ell - v_cell_max*(1 - S_ell)];              %#ok<AGROW>
        con = [con, v_cell_eng_ell <= v_cell_ell - v_cell_min*(1 - S_ell)];              %#ok<AGROW>


        % --- Pack voltage ------------------------------------------------
        % Manuscript eq. (9a):
        %   v_pack(ell) = sum_i v_eng_i(ell) - N * r_s * i_pack(ell).
        % The term N*r_s*i_pack is configuration-independent: i_pack flows
        % through exactly one switch of resistance r_s per unit at every step.
        con = [con, named(v_pack_ell == sum(v_cell_eng_ell) - Ns * r_s * i_pack_ell, ...
            sprintf('ell%d_v_pack_sum', ell))];                                      %#ok<AGROW>
        con = [con, v_pack_min <= v_pack_ell];                               %#ok<AGROW>
        con = [con, v_pack_ell   <= v_pack_max];                             %#ok<AGROW>


        % --- Per-stage minimum engaged-cell count ------------------------
        con = [con, named(sum(S_ell) >= Ns_min_stage_par(ell), ...
            sprintf('ell%d_Ns_min_stage', ell))];                          %#ok<AGROW>


        % --- SOS2 inverse pack voltage -----------------------------------
        % Manuscript Appendix: r_pack(ell) = sum_j r_j * alpha_j(ell)
        % approximates 1/v_pack(ell) via piecewise-linear interpolation.
        a_ell = alpha(:,ell);
        con = [con, named(sum(a_ell) == 1, sprintf('ell%d_alpha_sum',    ell))]; %#ok<AGROW>
        con = [con, named(a_ell >= 0,      sprintf('ell%d_alpha_nonneg', ell)), sos2(a_ell)]; %#ok<AGROW>
        con = [con, named(v_pack_ell  == vgrid'   * a_ell, sprintf('ell%d_vpack_interp',     ell))]; %#ok<AGROW>
        con = [con, named(r_pack(ell) == invgrid' * a_ell, sprintf('ell%d_inv_vpack_interp', ell))]; %#ok<AGROW>
        %con = [con, r_pack(ell) == 1 / v_pack_min];


        % --- Epigraph constraint for i_pack^2 ----------------------------
        % Manuscript Appendix eq. (A3): q_sq(ell) >= i_pack(ell)^2,
        % imposed as a second-order cone constraint.
        con = [con, 0      <= q_sq_ell];                                 %#ok<AGROW>
        con = [con, q_sq_ell <= q_sq_U_ell];                                   %#ok<AGROW>
        con = [con, q_sq_ell >= i_pack_ell^2];                             %#ok<AGROW>


        % --- Gated heat auxiliary: q_gen_i(ell) = S_i(ell) * q_sq(ell) --
        % Manuscript Appendix eq. (A5): McCormick linearisation.
        % S_i=1: q_gen_i = q_sq.  S_i=0: q_gen_i = 0.
        con = [con, 0        <= q_gen_ell];                              %#ok<AGROW>
        con = [con, q_gen_ell  <= q_sq_U_ell * S_ell];                          %#ok<AGROW>
        con = [con, q_gen_ell  <= q_sq_ell * ones(Ns,1)];                 %#ok<AGROW>
        con = [con, q_gen_ell  >= q_sq_ell - q_sq_U_ell*(1 - S_ell)];            %#ok<AGROW>


        % --- Thermal dynamics --------------------------------------------
        % Manuscript eq. (4c) with updated heat generation eq. (6):
        %   Q_gen_i(ell) = R0 * q_gen_i(ell) + r_s * q_sq(ell).
        %
        % R0 * q_gen_i: cell ohmic dissipation, gated by engagement.
        % r_s * q_sq:   switch dissipation, configuration-independent
        %               (one switch of resistance r_s carries i_pack per
        %               unit at every step regardless of engagement state).
        Q_gen_cell_ell = R0 * q_gen_ell + r_s * q_sq_ell * ones(Ns, 1);
        con = [con, T_cell(:,ell+1) == T_amb + a_th*(T_cell_ell - T_amb) + b_th*Q_gen_cell_ell]; %#ok<AGROW>
        con = [con, T_cell_min <= T_cell(:,ell+1)];                     %#ok<AGROW>
        con = [con, T_cell(:,ell+1) <= T_cell_max];                     %#ok<AGROW>


        % --- Power tracking with curtailment slack -----------------------
        % Manuscript eq. (12): lambda(ell) = P_req * r_pack - i_pack,
        % normalised by sgn(P_req). Rearranged to i_pack = P_req*r_pack - sgn*lambda.
        con = [con, named(i_pack_ell == P_req_ell * r_pack(ell) - sgnP_ell * lambda_ell, ...
            sprintf('ell%d_power_track', ell))];                                             %#ok<AGROW>
        con = [con, named(0          <= lambda_ell, sprintf('ell%d_lambda_nonneg', ell))];  %#ok<AGROW>
        con = [con, named(lambda_ell <= lambda_U_ell, sprintf('ell%d_lambda_ub',   ell))];  %#ok<AGROW>
        % con = [con, 0 <= lambda_ell];
        % con = [con, lambda_ell <= lambda_U_ell];

    end


    % --- Optional monotone stack constraint ------------------------------
    %  Cells are pre-sorted best-to-worst by the caller; the engaged set
    %  is constrained to be a contiguous prefix (ranking-based restriction).
    if isfield(constants, 'enable_monotone') && constants.enable_monotone
        con = [con, S_cell(1:end-1, :) >= S_cell(2:end, :)];
        %con = [con, S_cell(1:Ns_min_voltage_safe, :) == 1];
    end


    % --- Terminal constraints --------------------------------------------
    con = [con, z_cell_min <= z_cell(:, Np+1)];
    con = [con, z_cell(:, Np+1) <= z_cell_max];

    con = [con, T_cell_min <= T_cell(:, Np+1)];
    con = [con, T_cell(:, Np+1) <= T_cell_max];

    % Terminal SOC spread: max_i SOC_i(N_p+1) - min_i SOC_i(N_p+1) <= Delta_SOC_max.
    % Manuscript eq. (13), linearised via auxiliary max/min variables.
    SOCterm = z_cell(:, Np+1);
    con = [con, named(SOCterm        <= SOCterm_U,             'terminal_SOCterm_upper')];
    con = [con, named(SOCterm        >= SOCterm_L,             'terminal_SOCterm_lower')];
    con = [con, named(DeltaSOCterm   <= Delta_SOCterm_max_par, 'terminal_delta_SOC')];
    con = [con, z_cell_min <= SOCterm_L];
    con = [con, SOCterm_L <= z_cell_max];
    con = [con, z_cell_min <= SOCterm_U];
    con = [con, SOCterm_U <= z_cell_max];



    % %% --------------------------------------------------------------------
    % %  Objective
    % %  --------------------------------------------------------------------
    % obj = 0;
    % 
    % % --- SOH usage cost (J_SOH) ------------------------------------------
    % SOH_scale           = (Np * Ns);
    % SOH_scaledMetric    = sum((SOH_inv_par'/SOH_EOL_inv) * S_cell);
    % J_SOH               = (1/SOH_scale) * SOH_scaledMetric;
    % obj                 = obj + w_SOH * J_SOH;
    % 
    % 
    % % --- SOC balancing cost (J_SOC) --------------------------------------
    % SOC_scale   = (Np * Ns);
    % z_acc       = 0;
    % for ell = 2:Np+1
    %     z_ell   = z_cell(:,ell);
    %     dz      = z_ell - sum(z_ell)/Ns;   
    %     z_acc   = z_acc + sum((dz/Delta_SOCterm_max_par).^2);
    % end
    % J_SOC       = (1/SOC_scale) * z_acc;
    % obj         = obj + w_SOC * J_SOC;
    % 
    % 
    % % --- Switching cost terms (J_sw, J_sw_prev) --------------------------
    % % V-B audit item #1: switching is not part of manuscript Eq. 14.
    % % Both within-horizon switching and step-to-previous switching are
    % % commented out. Placeholder zeros are returned in the output slots
    % % so the optimizer signature and caller unpacking remain stable.
    % J_sw      = sdpvar(1,1);
    % J_sw_prev = sdpvar(1,1);
    % con       = [con, J_sw == 0, J_sw_prev == 0];
    % %
    % % --- Legacy within-horizon switching cost (DISABLED) -----------------
    % % J_sw      = sdpvar(1,1);
    % % con       = [con, J_sw == 0];
    % %
    % % --- Legacy step-to-previous switching cost (DISABLED) ---------------
    % % swPrev_scale = Ns;
    % % J_sw_prev    = w_swPrev * (1/swPrev_scale) * sum(abs(S_cell(:,1) - S_prev_par));
    % % obj          = obj + J_sw_prev;
    % 
    % 
    % % --- Curtailment cost (J_curt) ----------------------------------------
    % lambda_scale        = Np;
    % lambda_scaledMetric = sum(lambda .* lambda_scale_par);
    % J_lambda            = (1/lambda_scale) * lambda_scaledMetric;
    % obj                 = obj + w_lambda * J_lambda;

    %% --------------------------------------------------------------------
    %  Objective
    %  --------------------------------------------------------------------
    obj = 0;
    
    obj_mode = "full";
    if isfield(cfg, 'DEBUG') && isfield(cfg.DEBUG, 'discharge_objective_mode')
        obj_mode = string(cfg.DEBUG.discharge_objective_mode);
    end
    
    switch obj_mode
    
        case "zero"
            % Pure feasibility test: remove all objective expressions.
            J_SOH    = sdpvar(1,1);
            J_SOC    = sdpvar(1,1);
            J_sw     = sdpvar(1,1);
            J_sw_prev = sdpvar(1,1);
            J_lambda = sdpvar(1,1);
    
            con = [con, J_SOH == 0, J_SOC == 0, J_sw == 0, ...
                        J_sw_prev == 0, J_lambda == 0];
            obj = 0;
    
        otherwise
            % --- SOH usage cost (J_SOH) --------------------------------------
            SOH_scale           = (Np * Ns);
            SOH_scaledMetric    = sum((SOH_inv_par'/SOH_EOL_inv) * S_cell);
            J_SOH               = (1/SOH_scale) * SOH_scaledMetric;
    
            % --- SOC balancing cost (J_SOC) ----------------------------------
            SOC_scale = (Np * Ns);
            z_acc     = 0;
    
            switch obj_mode
                case "no_soc"
                    J_SOC = sdpvar(1,1);
                    con   = [con, J_SOC == 0];
    
                case "soc_const"
                    Delta_SOCterm_nom = cfg.mpc.socSpread.Delta_high;
                    for ell = 2:Np+1
                        z_ell = z_cell(:,ell);
                        dz    = z_ell - sum(z_ell)/Ns;
                        z_acc = z_acc + sum(dz.^2) / (Delta_SOCterm_nom^2);
                    end
                    J_SOC = (1/SOC_scale) * z_acc;
    
                case "full"
                    for ell = 2:Np+1
                        z_ell = z_cell(:,ell);
                        dz    = z_ell - sum(z_ell)/Ns;
                        z_acc = z_acc + sum((dz/Delta_SOCterm_max_par).^2);
                    end
                    J_SOC = (1/SOC_scale) * z_acc;
    
                otherwise
                    error('Unknown cfg.DEBUG.discharge_objective_mode: %s', obj_mode);
            end
    
            % --- Switching cost terms, disabled -------------------------------
            J_sw      = sdpvar(1,1);
            J_sw_prev = sdpvar(1,1);
            con       = [con, J_sw == 0, J_sw_prev == 0];
    
            % --- Curtailment cost (J_curt) ------------------------------------
            lambda_scale        = Np;
            lambda_scaledMetric = sum(lambda .* lambda_scale_par);
            J_lambda            = (1/lambda_scale) * lambda_scaledMetric;
    
            % Assemble selected objective
            obj = obj + w_SOH    * J_SOH;
            obj = obj + w_lambda * J_lambda;
    
            if obj_mode ~= "no_soc"
                obj = obj + w_SOC * J_SOC;
            end
    end    



    %% --------------------------------------------------------------------
    %  Optimizer outputs
    %  --------------------------------------------------------------------
    outs = { ...
        S_cell(:,1),       ...   % first-step switch decisions S_i(1)
        i_pack(1),         ...   % first-step pack current i_pack(1)
        v_cell(:,1),       ...   % first-step cell voltages v_i(1)
        v_cell_eng(:,1),   ...   % first-step engaged-cell voltages v_eng_i(1)
        v_pack(1),         ...   % first-step pack voltage v_pack(1)
        lambda(1),   ...   % first-step curtailment slack lambda(1)
        J_SOH,             ...   % SOH usage cost
        J_SOC,             ...   % SOC balancing cost
        J_sw,              ...   % within-horizon switching cost (disabled)
        J_sw_prev,         ...   % step-to-previous switching cost
        J_lambda,            ...   % curtailment cost
        DeltaSOCterm};      % terminal SOC spread (scalar = SOCterm_U - SOCterm_L)


    %% --------------------------------------------------------------------
    %  Optimizer parameter list
    %  --------------------------------------------------------------------
    params = { ...
        z_cell_prev_par,        ...   %  1  SOC_i(ell)
        i_RC_1_cell_prev_par,   ...   %  2  i_RC1_i(ell)
        i_RC_2_cell_prev_par,   ...   %  3  i_RC2_i(ell)
        T_cell_prev_par,        ...   %  4  T_i(ell)
        P_pack_req_par,         ...   %  5  P_req(ell)
        sgnP_par,               ...   %  6  sgn(P_req(ell))
        m_ocv_par,              ...   %  7  m_i(ell): OCV slope
        b_ocv_par,              ...   %  8  b_i(ell): OCV intercept
        i_pack_U_par,       ...   %  9  upper pack-current bound, Eq. A1
        i_pack_L_par,       ...   % 10  lower pack-current bound, Eq. A1
        q_sq_U_par,                 ...   % 11  upper bound on q_sq per step
        lambda_U_par,   ...   % 12  lambda^max(ell)
        Q_cell_As_par,          ...   % 13  Q_i (As)
        SOH_inv_par,          ...   % 14  1/SOH_i
        S_prev_par,             ...   % 15  S(ell-1)
        lambda_scale_par,        ...   % 16  current normalisation 1/A
        Delta_SOCterm_max_par,           ...   % 17  Delta_SOC_max
        Ns_min_stage_par,       ...   % 18  per-stage minimum engaged-cell count
    };


    %% --------------------------------------------------------------------
    %  Build YALMIP optimizer
    %  --------------------------------------------------------------------
    opt = optimizer(con, obj, ops, params, outs);

    % Return binary variable handle for warm-start use (optional).
    % The caller assigns the previous step's solution via:
    %   assign(S_cell_handle, repmat(prev_S_sorted, 1, Np))
    % with the optimizer built using ops.usex0 = 1 in sdpsettings.
    if nargout > 1
        varargout{1} = S_cell;
    end

end


% -------------------------------------------------------------------------
function C = named(C, name)
% NAMED  Attach a diagnostic tag to a YALMIP constraint set.
%   C = named(C, name)  calls tag(C, char(name)) and returns the tagged
%   constraint. Use this to label constraint blocks so that infeasibility
%   certificates and dual variables can be traced back to source.
    C = tag(C, char(name));
end

