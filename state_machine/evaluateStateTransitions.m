function sm = evaluateStateTransitions(sm, x_k, y_k, constants, k, violPacked, violIdx)

    smParams    = sm.params;
    smStates    = sm.states;
    
    z           = x_k.z(:);
    z_min       = min(z);
    v_max       = max(y_k.v_cell_meas_vec(:)); 
    z_max       = max(z);     

    didTransition = false;  
    [viol_sm_code, viol_sm_idx_k] = selectSMViolation(violPacked, violIdx, sm.currentState, sm.states);
    

    % Violation-driven transitions
    if viol_sm_code ~= 0

        transitionReason = sprintf("Violation %d (cell %d)", ...
                                        viol_sm_code, viol_sm_idx_k); 

        switch sm.currentState

            case {smStates.DISCHARGE_HIGH, smStates.DISCHARGE_LOW}

                sm = applyStateTransition(sm, smStates.REST_AFTER_DISCHARGE, ...
                    k, transitionReason);
                sm.lowSOCLatched = true;
                didTransition = true;

            case {smStates.CHARGE_BULK, smStates.CHARGE_BALANCE}

                sm = applyStateTransition(sm, smStates.REST_AFTER_CHARGE, ...
                    k, transitionReason);
                didTransition = true;
        end

        if didTransition
            newName = sm.id2name(sm.currentState);
            sm.name = newName; %getStateNameFast(sm.currentState, smStates);
            return;
        end
    end


    switch sm.currentState
    
        case smStates.DISCHARGE_HIGH
            if z_min <= smParams.SOC_THR_DISHIGH_DISLOW
                transitionReason = sprintf("z_cell_min=%.4f <= %.4f", ...
                    z_min, smParams.SOC_THR_DISHIGH_DISLOW);                
                sm = applyStateTransition(sm, smStates.DISCHARGE_LOW, ...
                    k, transitionReason);
                sm.lowSOCLatched = true;
                didTransition = true;                
            end
    
        case smStates.DISCHARGE_LOW
            if z_min <= smParams.SOC_THR_DISLOW_REST
                transitionReason = sprintf("z_cell_min=%.4f <= %.4f", ...
                    z_min, smParams.SOC_THR_DISLOW_REST);                       
                sm = applyStateTransition(sm, smStates.REST_AFTER_DISCHARGE, ...
                    k, transitionReason);
                sm.rest_counter = 0;   
                didTransition = true;                
            end
    
        case smStates.REST_AFTER_DISCHARGE
            sm.rest_counter = sm.rest_counter + 1;
            t_rest = sm.rest_counter * constants.cfg.Tstep;
            if t_rest >= smParams.REST_DISC_END
                transitionReason = ...
                    sprintf("t_Rest_DisEnd=%.0fs >= %.0fs", ...
                    t_rest, smParams.REST_DISC_END);                    
                sm = applyStateTransition(sm, smStates.CHARGE_BULK, ...
                    k, transitionReason);   
                didTransition = true;                
            end
    
        case smStates.CHARGE_BULK
            if z_max >= smParams.SOC_THR_CHGLOW_CHGHIGH
                transitionReason = sprintf("z_max=%.4f >= %.4f", ...
                    z_max, smParams.SOC_THR_CHGLOW_CHGHIGH);                
                sm = applyStateTransition(sm, smStates.CHARGE_BALANCE, ...
                    k, transitionReason);
                didTransition = true;                
            end
    
        case smStates.CHARGE_BALANCE
    
            z_min_highenough_threshold = smParams.SOC_THR_CHGHIGH_REST - ...
                smParams.SOC_THR_CHGLOW_CHGHIGH_HYST;
            z_min_highenough = z_min > z_min_highenough_threshold;

            z_spread       = z_max - z_min;
            z_balanced     = z_spread < smParams.SOC_THR_CHGHIGH_REST_BAL;

            if z_min_highenough && z_balanced
                transitionReason = ...
                    sprintf("z_min=%.4f >= %.4f, z_spread=%.4f <= %.4f", ...
                    z_min, z_min_highenough_threshold, ...
                    z_spread, smParams.SOC_THR_CHGHIGH_REST_BAL);                
                sm = applyStateTransition(sm, smStates.REST_AFTER_CHARGE, ...
                    k, transitionReason);
                sm.rest_counter = 0;
                didTransition = true;                
            end
    
        case smStates.REST_AFTER_CHARGE
            sm.rest_counter = sm.rest_counter + 1;
            t_rest = sm.rest_counter * constants.cfg.Tstep;
            if t_rest >= smParams.REST_CHG_END
                transitionReason = ...
                    sprintf("t_Rest_ChgEnd=%.0fs >= t_RestChgEndMax=%.0fs", ...
                    t_rest, smParams.REST_CHG_END);                
                sm = applyStateTransition(sm, smStates.DISCHARGE_HIGH, k, transitionReason);
                sm.lowSOCLatched = false;    
                didTransition = true;                
            end
    end
    
    % Step counter: only increment if you did NOT transition this call
    if ~didTransition
        sm.step_in_state = sm.step_in_state + 1;
    end
    %sm.name             = sm.id2name(sm.currentState); %getStateNameFast(sm.currentState, smStates);

end