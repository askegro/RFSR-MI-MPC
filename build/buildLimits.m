function limits = buildLimits(cfg, models, con)

    assert_has_fields(con, { ...
        'C_rate_dis_max','C_rate_chg_max', ...
        'z_cell_min','z_cell_max', ...
        'v_cell_min','v_cell_max', ...
        'T_cell_min','T_cell_max'}, 'chem.constraints');
    
    limits = struct();
    
    % SOC
    limits.z_cell_min = con.z_cell_min;
    limits.z_cell_max = con.z_cell_max;
    if ~(isfinite(limits.z_cell_min) && ...
            isfinite(limits.z_cell_max) && ...
            limits.z_cell_min < limits.z_cell_max)
        error('Invalid SOC limits');
    end
    
    % Voltage
    limits.v_cell_min = con.v_cell_min;
    limits.v_cell_max = con.v_cell_max;
    if ~(isfinite(limits.v_cell_min) && ...
            isfinite(limits.v_cell_max) && ...
            limits.v_cell_min < limits.v_cell_max)
        error('Invalid voltage limits');
    end
    
    % Temperature
    limits.T_cell_min = con.T_cell_min;
    limits.T_cell_max = con.T_cell_max;
    if ~(isfinite(limits.T_cell_min) && ...
            isfinite(limits.T_cell_max) && ...
            limits.T_cell_min < limits.T_cell_max)
        error('Invalid temperature limits');
    end
    
    % Currents (series string => pack current = cell current)
    Q_cell_nom_Ah           = models.cell.Q_cell_nom_Ah;
    limits.i_dis_max_mag    = con.C_rate_dis_max * Q_cell_nom_Ah;
    limits.i_chg_max_mag    = con.C_rate_chg_max * Q_cell_nom_Ah;
    
    limits.i_pack_max = +limits.i_dis_max_mag;   % discharge positive
    limits.i_pack_min = -limits.i_chg_max_mag;   % charge negative
    limits.i_cell_max = +limits.i_dis_max_mag;   % discharge positive
    limits.i_cell_min = -limits.i_chg_max_mag;   % charge negative    
    
    % Ns_cmd bounds (reconfiguration)
    limits.Ns_min = 1; 
    limits.Ns_max = cfg.Ns;
    
    % Pack voltage bounds
    limits.v_pack_min = models.cell.v_cell_nom * limits.Ns_max * cfg.limits.v_pack_min_frac;
    limits.v_pack_max = limits.v_cell_max * limits.Ns_max;

    limits.Ns_min_voltage_safe = ceil(limits.v_pack_min / limits.v_cell_max);
    limits.Ns_min_voltage_nom  = ceil(limits.v_pack_min / models.cell.v_cell_nom);
    
 
    
    fprintf('\n========================================\n');
    fprintf('  Limits built\n');
    fprintf('========================================\n');
    fprintf('  I_pack bounds: [%.2f, %.2f] A\n', limits.i_pack_min, limits.i_pack_max);
    fprintf('  SOC: [%.0f%%, %.0f%%]\n', 100*limits.z_cell_min, 100*limits.z_cell_max);
    fprintf('  Vcell: [%.2f, %.2f] V\n', limits.v_cell_min, limits.v_cell_max);
    fprintf('  Ns_cmd: [%d, %d]\n', limits.Ns_min, limits.Ns_max);
    fprintf('  Vpack: [%.1f, %.1f] V\n', limits.v_pack_min, limits.v_pack_max);
    fprintf('  Ns_min from Vpack/Vcell_max: %d\n', limits.Ns_min_voltage_safe);
    fprintf('  Ns_min from Vpack/Vcell_nom: %d\n', limits.Ns_min_voltage_nom);       
    fprintf('========================================\n');

end
