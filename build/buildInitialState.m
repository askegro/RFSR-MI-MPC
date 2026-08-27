function x0 = buildInitialState(cfg, env, models)

    Ns = cfg.Ns;
    
    % SOC init
    z_init_raw  = cfg.z_cell_init_mean + cfg.init.soc_std * randn(env.sSOC, Ns, 1);
    z_init      = clamp(z_init_raw, cfg.limits.z_min, cfg.limits.z_max);
    
    % RC currents
    iRC1_init   = zeros(size(z_init));
    iRC2_init   = zeros(size(z_init));  

    % Temperature
    T_init      = models.therm.T_amb * ones(Ns,1);    

    % Aging states
    qcal_init   = zeros(size(z_init));
    qcyc_init   = zeros(size(z_init));
    EFC_init    = zeros(size(z_init));    

    x0      = struct();
    x0.z    = z_init(:);
    x0.iRC1 = iRC1_init;
    x0.iRC2 = iRC2_init;
    x0.T    = T_init;
    x0.qcal = qcal_init;
    x0.qcyc = qcyc_init;
    x0.EFC  = EFC_init;


    % SOH init
    soh_raw = cfg.SOH_cell_init_mean + cfg.init.soh_std * randn(env.sSOH, Ns, 1);
    soh     = soh_raw;   
    x0.SOH  = soh(:);

    % capacities
    Q_Ah = models.cell.Q_cell_nom_Ah .* soh;
    Q_As = Q_Ah * 3600;
    x0.Q_Ah = Q_Ah(:);
    x0.Q_As = Q_As(:);
    

end