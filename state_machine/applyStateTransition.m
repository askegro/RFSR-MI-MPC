function sm = applyStateTransition(sm, nextState, k, transitionReason)
    oldState        = sm.currentState;
    oldStateName    = state_name_from_id(sm.states, oldState);
    sm.currentState = nextState;
    newStateName    = state_name_from_id(sm.states, nextState);
    sm.step_in_state = 1;
    sm.last_transition_step = k;
    sm.name = newStateName; 
    fprintf('[Step %d] Transition: %s → %s | %s\n', ...
        k, oldStateName, newStateName, string(transitionReason));    
end