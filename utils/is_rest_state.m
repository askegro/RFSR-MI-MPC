function tf = is_rest_state(currentState, states)
% IS_REST_STATE  True when the controller must skip MPC and rest.

    tf = currentState == states.REST_AFTER_DISCHARGE || ...
         currentState == states.REST_AFTER_CHARGE;
end