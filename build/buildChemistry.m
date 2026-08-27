function [chem, raw] = buildChemistry(cfg)

    fprintf('\n========================================\n');
    fprintf('  Loading chemistry object...\n');
    fprintf('========================================\n');
    
    switch upper(cfg.CHEMISTRY_TYPE)
        case 'LFP'
            chem = LFPChemistry('UseEmpirical', cfg.USE_EMPIRICAL_DATA);
        case 'NMC'
            chem = NMCChemistry('UseEmpirical', cfg.USE_EMPIRICAL_DATA);
        otherwise
            error('Unknown chemistry type: %s', cfg.CHEMISTRY_TYPE);
    end
    
    raw             = struct();
    raw.elec        = chem.electrical;
    raw.therm       = chem.thermal;
    raw.aging       = chem.aging;
    raw.constraints = chem.constraints;
    raw.cell        = chem.cell;
    
    if ismethod(chem,'displayInfo')
        chem.displayInfo();
    end

end
