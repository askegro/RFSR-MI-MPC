function [x_new, y_k, ep, epEnd_out] = advancePlantState(x_k, u_k, constants)
    
    cfg     = constants.cfg;
    elec    = constants.models.elec;
    therm   = constants.models.therm;
    cell    = constants.models.cell;
    aging   = constants.models.aging;

    dq_cyc  = aging.dq_cyc_anonFunc;
    
    Ns       = cfg.Ns;
    Tstep    = cfg.Tstep;
    BAL      = cfg.BALANCING_CONFIG;
    NUMERICS = cfg.NUMERICS;

    r_s = elec.r_s;   


    % ====================================================================
    % INPUTS
    % ====================================================================  
    S_cmd_k               = u_k.S_cmd;
    i_pack_cmd_k          = u_k.i_pack_cmd;
    i_cell_bal_vec_k      = u_k.i_cell_bal;       % Ns x 1 (can be zeros)
    v_OC_k                = u_k.v_oc;             % Ns x 1 (caller supplies to avoid recompute)
    t_days_k              = u_k.t_days;
    SOH_cell_vec_k        = u_k.SOH_cell;
    FLAG_CycUpdate_k      = u_k.FLAG_CycUpdate_k;
    episodeType_k         = u_k.episodeType;

    z_cell_min_vec_ep     = u_k.ep.z_cell_min_vec;    
    z_cell_max_vec_ep     = u_k.ep.z_cell_max_vec;        
    EFC_cell_tot_vec_ep   = u_k.ep.EFC_cell_tot_vec;
    Crate_cell_tot_vec_ep = u_k.ep.Crate_cell_tot_vec;
    T_cell_tot_vec_ep     = u_k.ep.T_cell_tot_vec;
    step_count_ep         = u_k.ep.step_count;    
   
    
    % ====================================================================
    % STATES
    % ==================================================================== 
    z_cell_vec_k          = x_k.z;
    iRC1_vec_k            = x_k.iRC1;
    iRC2_vec_k            = x_k.iRC2;
    T_cell_vec_k          = x_k.T;
    q_cell_loss_cal_vec_k = x_k.qcal;
    q_cell_loss_cyc_vec_k = x_k.qcyc;
    EFC_cell_vec_k        = x_k.EFC;

    % Effective capacity from SOH
    Q_cell_As_k = cell.Q_cell_nom_As .* SOH_cell_vec_k;
    


    % ====================================================================
    % ELECTRICAL STATES AND OUTPUTS
    % ====================================================================  

    % Cell current: i_i = S_i * i_pack (manuscript eq. 3)
    i_cell_vec_k = S_cmd_k .* i_pack_cmd_k;

    % Cell terminal voltage (manuscript eq. 7):
    %   v_i = OCV_i - R0 * i_i - R1 * i_RC1_i - R2 * i_RC2_i
    v_cell_meas_vec_k = v_OC_k ...
                        - elec.R0 .* i_cell_vec_k ...
                        - elec.R1 .* iRC1_vec_k ...
                        - elec.R2 .* iRC2_vec_k;

    % Pack voltage (manuscript eq. 9a, updated for switch resistance):
    %   v_pack = sum_i(S_i * v_i) - N * r_s * i_pack
    % The term N * r_s * i_pack is configuration-independent: i_pack flows
    % through exactly one switch of resistance r_s per unit at every step.
    v_pack_meas_k = S_cmd_k' * v_cell_meas_vec_k - Ns * r_s * i_pack_cmd_k;
    
    % Electrical state updates
    z_cell_new = z_cell_vec_k - (Tstep ./ Q_cell_As_k) .* i_cell_vec_k;
    iRC1_new   = elec.a1 .* iRC1_vec_k + elec.b1 .* i_cell_vec_k;
    iRC2_new   = elec.a2 .* iRC2_vec_k + elec.b2 .* i_cell_vec_k;
    


    % ====================================================================
    % THERMAL STATES AND OUTPUTS
    % ====================================================================     

    % Cell heat generation (manuscript eq. 6, updated for switch resistance):
    %   Q_gen_i = R0 * i_i^2 + R1 * i_RC1_i^2 + R2 * i_RC2_i^2
    %           + r_s * i_pack^2
    %
    % The switch term r_s * i_pack^2 is configuration-independent and is
    % attributed to the series switch S_i, which is thermally coupled to
    % cell i. The bypass switch S_i' carries i_pack when cell i is bypassed
    % but is thermally isolated; its dissipation is excluded here.
    p_cell_loss_elec_k = elec.R0 .* (i_cell_vec_k.^2) ...
                       + elec.R1 .* (iRC1_vec_k.^2)   ...
                       + elec.R2 .* (iRC2_vec_k.^2)   ...
                       + r_s     .* (i_pack_cmd_k.^2);   % switch term, all cells

    p_cell_loss_bal_vec_k = (i_cell_bal_vec_k.^2) .* BAL.R_balance;

    if BAL.thermal_coupling
        p_cell_loss_tot_vec_k = p_cell_loss_elec_k + p_cell_loss_bal_vec_k;
    else
        p_cell_loss_tot_vec_k = p_cell_loss_elec_k;
    end
    
    % Thermal state update (manuscript eq. 4c):
    %   T_i(k+1) = T_amb + a_T * (T_i(k) - T_amb) + b_T * Q_gen_i(k)
    T_cell_new = therm.T_amb ...
               + therm.a_th .* (T_cell_vec_k - therm.T_amb) ...
               + therm.b_th .* p_cell_loss_tot_vec_k;
    

    % ====================================================================
    % AGING STATES AND OUTPUTS
    % ====================================================================     

    % Calendar aging state update
    dq_cal_new = dq_cal_update_xu2023(t_days_k, aging.dt_days, T_cell_vec_k, z_cell_vec_k, aging.p);
    qcal_new   = q_cell_loss_cal_vec_k + dq_cal_new;

    % Cycle aging state update
    z_cell_min_vec_ep     = min(z_cell_min_vec_ep, z_cell_vec_k);
    z_cell_max_vec_ep     = max(z_cell_max_vec_ep, z_cell_vec_k);
    DoD_cell_vec_ep       = z_cell_max_vec_ep - z_cell_min_vec_ep;
    
    dAh_step              = abs(i_cell_vec_k) * (Tstep / 3600);      
    dEFC_new              = dAh_step ./ (2 * cell.Q_cell_nom_Ah); 
    EFC_cell_tot_vec_ep   = EFC_cell_tot_vec_ep + dEFC_new; 

    Crate_new             = abs(i_cell_vec_k) ./ cell.Q_cell_nom_Ah;
    Crate_cell_tot_vec_ep = Crate_cell_tot_vec_ep + Crate_new .* dEFC_new; 

    T_cell_tot_vec_ep     = T_cell_tot_vec_ep + T_cell_vec_k .* dEFC_new;
    step_count_ep         = step_count_ep + 1; 

    switch FLAG_CycUpdate_k
        case true
            EFC_cell_tot_vec_ep_safe = max(EFC_cell_tot_vec_ep, NUMERICS.eps_div0);
            T_cell_avg_vec_ep        = T_cell_tot_vec_ep   ./ EFC_cell_tot_vec_ep_safe;
            Crate_cell_avg_vec_ep    = Crate_cell_tot_vec_ep ./ EFC_cell_tot_vec_ep_safe;
            dq_cyc_new               = dq_cyc(EFC_cell_tot_vec_ep, ...
                                              T_cell_avg_vec_ep,   ...
                                              DoD_cell_vec_ep,     ...
                                              Crate_cell_avg_vec_ep);

            epEnd.z_cell_min_vec     = z_cell_min_vec_ep;   
            epEnd.z_cell_max_vec     = z_cell_max_vec_ep; 
            epEnd.DoD_cell_vec       = DoD_cell_vec_ep;
            epEnd.EFC_cell_tot_vec   = EFC_cell_tot_vec_ep;
            epEnd.Crate_cell_tot_vec = Crate_cell_tot_vec_ep;
            epEnd.T_cell_tot_vec     = T_cell_tot_vec_ep;
            epEnd.step_count         = step_count_ep;                
         
            z_cell_min_vec_ep        = z_cell_vec_k;
            z_cell_max_vec_ep        = z_cell_vec_k; 
            DoD_cell_vec_ep          = zeros(Ns, 1);
            EFC_cell_tot_vec_ep      = zeros(Ns, 1);
            Crate_cell_tot_vec_ep    = zeros(Ns, 1);            
            T_cell_tot_vec_ep        = zeros(Ns, 1);
            step_count_ep            = 0;        

        otherwise
            dq_cyc_new = zeros(Ns, 1);
    end
    qcyc_new = q_cell_loss_cyc_vec_k + dq_cyc_new;    

    % EFC state update
    EFC_new = EFC_cell_vec_k + dEFC_new;            

    

    % ====================================================================
    % PACK INTO STATES AND OUTPUTS
    % ====================================================================
    x_new      = x_k;
    x_new.z    = z_cell_new;
    x_new.iRC1 = iRC1_new;
    x_new.iRC2 = iRC2_new;
    x_new.T    = T_cell_new;
    x_new.qcal = qcal_new;
    x_new.qcyc = qcyc_new;    
    x_new.EFC  = EFC_new;
    
    y_k                         = struct();
    y_k.v_cell_meas_vec         = v_cell_meas_vec_k;
    y_k.p_cell_loss_tot_vec     = p_cell_loss_tot_vec_k;
    y_k.p_cell_loss_bal_vec     = p_cell_loss_bal_vec_k;
    y_k.v_pack_meas             = v_pack_meas_k;
    y_k.i_pack                  = i_pack_cmd_k;
    y_k.p_pack_meas             = v_pack_meas_k * i_pack_cmd_k;

    if FLAG_CycUpdate_k
        epEnd_out = epEnd;  
    else
        epEnd_out = u_k.ep; 
    end

    ep.z_cell_min_vec       = z_cell_min_vec_ep;   
    ep.z_cell_max_vec       = z_cell_max_vec_ep; 
    ep.DoD_cell_vec         = DoD_cell_vec_ep;        
    ep.EFC_cell_tot_vec     = EFC_cell_tot_vec_ep;
    ep.Crate_cell_tot_vec   = Crate_cell_tot_vec_ep;
    ep.T_cell_tot_vec       = T_cell_tot_vec_ep;
    ep.step_count           = step_count_ep;  
    ep.episode_currentType  = episodeType_k;

    invalidMask = ~isfinite(z_cell_new)       ...
                | ~isfinite(T_cell_new)        ...
                | ~isfinite(v_cell_meas_vec_k);
    y_k.invalid = any(invalidMask);

end