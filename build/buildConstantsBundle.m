function constants = buildConstantsBundle(cfg, env, chem, ....
    raw, models, limits, chg, states, profile, scale, solver)

    constants           = struct();
    constants.cfg       = cfg;
    constants.env       = env;
    constants.chem      = chem;   
    constants.raw       = raw;    
    constants.models    = models;
    constants.limits    = limits;
    constants.chg       = chg;
    constants.states    = states;
    constants.profile   = profile;
    constants.scale     = scale;
    constants.solver    = solver;

    % --- Propagate switch on-state resistance into models.elec ---------
    constants.models.elec.r_s = cfg.r_s;

    % --- Make cfg.mpc variant flags authoritative at the top level ------
    % Consumers (buildDischargeOptimizer, controller_step) check
    % constants.enable_sorting and constants.enable_monotone directly.
    if isfield(cfg, 'mpc') && isfield(cfg.mpc, 'enable_sorting')
        constants.enable_sorting = cfg.mpc.enable_sorting;
    else
        constants.enable_sorting = true;
    end
    if isfield(cfg, 'mpc') && isfield(cfg.mpc, 'enable_monotone')
        constants.enable_monotone = cfg.mpc.enable_monotone;
    else
        constants.enable_monotone = true;
    end

end
