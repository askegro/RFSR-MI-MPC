function chg = buildChargingParams(cfg, chem, limits)
    
    chg = cfg.CHARGING;
    
    % ------------------------------------------------------------------------
    % Absolute ceiling (datasheet) - never exceed
    % ------------------------------------------------------------------------    
    chg.V_CEILING    = limits.v_cell_max;

    % ------------------------------------------------------------------------
    % OCV at target SOC (used for CC_CV strategy target)
    % ------------------------------------------------------------------------    
    chg.V_OCV_target = chem.computeOCV(chg.SOC_target);
    
    % ------------------------------------------------------------------------
    % Resolve charging strategy (string)
    % ------------------------------------------------------------------------    
    chg.strategy = resolveChargeStrategy(chg.strategy_requested, cfg.CHEMISTRY_TYPE, chg.AUTO_map);
    
    % ------------------------------------------------------------------------
    % Compute regulation target V_REGULATE based on chosen strategy
    % ------------------------------------------------------------------------
    if strcmpi(chg.strategy, "CC_CV")
        V_REG = chg.V_OCV_target + chg.CC_CV.margin_above_OCV_V;
        chg.V_REGULATE = min(V_REG, chg.V_CEILING);
    elseif strcmpi(string(chg.strategy), "FAST_TO_SOC")
        chg.V_REGULATE = chg.V_CEILING - chg.FAST_TO_SOC.offset_below_ceiling_V;
    else
        error('Unknown charging strategy: %s', string(chg.strategy));
    end
    
    % ------------------------------------------------------------------------
    % Thresholds (used for state machine / heuristics)
    % ------------------------------------------------------------------------
    chg.V_ENTER = chg.V_REGULATE - chg.enter_margin_V;
    
    % Exit threshold only meaningful for FAST_TO_SOC “return-to-CC” behavior
    if strcmpi(string(chg.strategy), "FAST_TO_SOC")
        chg.V_EXIT = chg.V_REGULATE - chg.FAST_TO_SOC.exit_margin_V;
    else
        chg.V_EXIT = NaN;
    end
    
    % Warning threshold below ceiling
    chg.V_WARN     = chg.V_CEILING - chg.warn_margin_V;

    % Voltage low-pass filter coefficient (used only if you run a PI fallback)
    chg.alpha_filt = cfg.Tstep / (chg.tau_filt + cfg.Tstep);

    % ------------------------------------------------------------------------
    % Strategy mismatch warnings (informational)
    % ------------------------------------------------------------------------
    if strcmpi(string(cfg.CHEMISTRY_TYPE), "LFP") && strcmpi(chg.strategy, "CC_CV")
        warning('CC_CV not recommended for LFP (flat OCV). Consider FAST_TO_SOC.');
    end
    if strcmpi(string(cfg.CHEMISTRY_TYPE), "NMC") && strcmpi(chg.strategy, "FAST_TO_SOC")
        warning('FAST_TO_SOC may accelerate NMC aging (high-V dwell). Consider CC_CV.');
    end
    
    fprintf('\n========================================\n');
    fprintf('  Charging params built (%s)\n', cfg.CHEMISTRY_TYPE);
    fprintf('========================================\n');
    fprintf('  Strategy: %s\n', string(chg.strategy));
    fprintf('  V_CEILING=%.4f | V_REG=%.4f | V_ENTER=%.4f | V_WARN=%.4f\n', ...
        chg.V_CEILING, chg.V_REGULATE, chg.V_ENTER, chg.V_WARN);
    if isfinite(chg.V_EXIT)
        fprintf('  V_EXIT=%.4f\n', chg.V_EXIT);
    end
    fprintf('========================================\n');

end
