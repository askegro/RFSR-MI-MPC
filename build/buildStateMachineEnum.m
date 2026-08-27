function [states, stateInitName, ...
    stateInit, id2name] = buildStateMachineEnum(cfg)

    states = struct( ...
        'DISCHARGE_HIGH',       uint8(1), ...
        'DISCHARGE_LOW',        uint8(2), ...
        'REST_AFTER_DISCHARGE', uint8(3), ...
        'CHARGE_BULK',          uint8(4), ...
        'CHARGE_BALANCE',       uint8(5), ...
        'REST_AFTER_CHARGE',    uint8(6));
    
    legacyInitMap = containers.Map( ...
        {'CHARGE_CC','CHARGE_CV','CHARGE_VLIM'}, ...
        {'CHARGE_BULK','CHARGE_BALANCE','CHARGE_BALANCE'});
    
    stateInitName = cfg.stateInit_name;
    if isKey(legacyInitMap, upper(stateInitName))
        stateInitName = legacyInitMap(upper(stateInitName));
    end
    
    if ~isfield(states, stateInitName)
        error('Invalid stateInit_name "%s". Valid: %s', stateInitName, strjoin(fieldnames(states), ', '));
    end
    
    stateInit = states.(stateInitName);

    f = fieldnames(states);
    vals = zeros(numel(f),1,'uint16');
    for i = 1:numel(f)
        vals(i) = uint16(states.(f{i}));
    end
    
    maxId = double(max(vals));
    id2name = strings(1, maxId);
    for i = 1:numel(f)
        id2name(double(vals(i))) = string(f{i});
    end    

end
