function ocv_pwl = buildOCVpwl(cfg, chem)
    
    fprintf('========================================\n');
    fprintf('\nValidating OCV model...\n');
    fprintf('========================================\n');

    z_min_cell_OCV = chem.constraints.z_cell_min_OCV;
    z_max_cell_OCV = chem.constraints.z_cell_max_OCV;    

    if cfg.USE_EMPIRICAL_DATA
        [soc_bp_optimal, v_bp_optimal, metrics_optimal] = ...
            optimizeOCVBreakpoints(chem, z_min_cell_OCV, z_max_cell_OCV, ...
            cfg.ocv.max_error_mV, cfg.ocv.max_points);
    
        %plotOCVOptimization(z_min_cell_OCV, z_max_cell_OCV, ...
        %    soc_bp_optimal, v_bp_optimal, metrics_optimal);
    
        ocv_pwl = struct();
        ocv_pwl.soc_bp_optimal = soc_bp_optimal;
        ocv_pwl.v_bp_optimal   = v_bp_optimal;
        ocv_pwl.metrics        = metrics_optimal;
    
        fprintf('  Optimized breakpoints stored in constants.ocv\n');
    else
        fprintf('  Using nominal OCV model (no optimization)\n');
    end
    
    fprintf('\n=== OCV Model Summary ===\n');
    fprintf('  Plant: Piecewise linear (full accuracy)\n');
    fprintf('  MPC:   Linear approximation (fast)\n');
    fprintf('  Range: [%.0f%%, %.0f%%] SOC\n', ...
         100*ocv_pwl.soc_bp_optimal(1), 100*ocv_pwl.soc_bp_optimal(end));
    fprintf('  Error:  max=%.1f mV, RMS=%.1f mV\n', ...
        ocv_pwl.metrics.max_error_mV, ...
        ocv_pwl.metrics.rms_error_mV);


end
