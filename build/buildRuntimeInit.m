function runtime = buildRuntimeInit(cfg, sm, x0, models)

    runtime = struct();
    

    % ----------------------------
    % Plant states
    % ----------------------------
    runtime.x = x0;


    % ----------------------------
    % Previous commands
    % ----------------------------    
    runtime.prev = struct();
    runtime.prev.i_cell_cmd_vec = 0;    
    runtime.prev.i_pack_cmd = 0;
    runtime.prev.S          = ones(cfg.Ns,1);
    runtime.prev.solverOK   = true;    


    % ----------------------------
    % Last measurements
    % ----------------------------        
    % last measured voltage (OCV at t=0)
    runtime.meas = struct( ...
        'v_cell_meas_vec',     models.ocv.func(runtime.x.z), ...
        'p_cell_loss_tot_vec', zeros(cfg.Ns,1), ...
        'p_cell_loss_bal_vec', zeros(cfg.Ns,1), ...
        'v_pack_meas',              0.0, ...
        'i_pack',              0.0, ...
        'p_pack_meas',              0.0);
    runtime.meas.v_pack_meas = sum(runtime.meas.v_cell_meas_vec);


    % ----------------------------
    % State machine
    % ----------------------------
    runtime.sm = sm;
    

    % ----------------------------
    % Episode tracking
    % ----------------------------
    runtime.episode = struct();
   
    runtime.episode.z_cell_min_vec      = runtime.x.z;
    runtime.episode.z_cell_max_vec      = runtime.x.z;    
    runtime.episode.DoD_cell_vec        = zeros(cfg.Ns,1); 
    runtime.episode.EFC_cell_tot_vec    = zeros(cfg.Ns,1);
    runtime.episode.Crate_cell_tot_vec  = zeros(cfg.Ns,1);    
    runtime.episode.T_cell_tot_vec      = zeros(cfg.Ns,1);
    runtime.episode.step_count          = 0;    
    runtime.episode.currentType         = getEpisodeType(sm.currentState, sm.states);
    runtime.episode.start_step = 1;

    
    % ----------------------------
    % Balancing flags
    % ----------------------------
    runtime.bal = struct();
    runtime.bal.active_prev = false(cfg.Ns,1);
    runtime.bal.hyst_spread_active = false;
    
    
    % ----------------------------
    % EOL
    % ----------------------------
    runtime.eol_reached = false;
    runtime.eol_step    = uint32(0);
    runtime.eol_reason  = "";
    runtime.eol_cell_idx = uint32(0);
    runtime.eol_soh_value = NaN;
    

end
