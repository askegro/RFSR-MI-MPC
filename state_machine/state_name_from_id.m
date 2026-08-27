function name = state_name_from_id(states, stateID)
    f = fieldnames(states);
    name = "UNKNOWN";
    for i = 1:numel(f)
        if states.(f{i}) == stateID
            name = string(f{i});
            return;
        end
    end
end