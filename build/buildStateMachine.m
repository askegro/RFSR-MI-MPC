function sm = buildStateMachine(states, stateInitID, ...
    smParams, chg, id2name)

    sm                      = struct();
    sm.states               = states;
    sm.currentState         = stateInitID;
    
    sm.name                 = state_name_from_id(states, stateInitID);
    
    % transition bookkeeping
    sm.step_in_state        = 1;
    sm.last_transition_step = 1;
    
    % timers (rest durations etc.)
    sm.rest_counter         = 0;
    
    % attach config knobs
    sm.params               = smParams;
    sm.chg                  = chg;

    sm.id2name              = id2name;   % store in sm (or constants.states)

end
