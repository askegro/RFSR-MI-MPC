function strategy = resolveChargeStrategy(strategy_requested, chemistry_type, AUTO_map)

    req = upper(string(strategy_requested));
    chem = upper(string(chemistry_type));
    
    if req == "AUTO"
        if isfield(AUTO_map, chem)
            strategy = string(AUTO_map.(chem));
        else
            error('AUTO_map has no entry for %s', chem);
        end
    else
        strategy = string(strategy_requested);
    end

end