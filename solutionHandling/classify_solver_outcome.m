function u = classify_solver_outcome(u, solver_diag, sol, mode)
% CLASSIFY_SOLVER_OUTCOME  Decide whether the solver payload is usable.
%
% Logic
%   - Normal finish + usable payload => optimal solution
%   - Timeout + usable incumbent     => acceptable incumbent
%   - Otherwise                      => unusable

    has_usable_payload = has_usable_solution(sol, mode);

    % Conservative default
    u.solution_usable   = false;
    u.optimality_proven = false;
    u.used_incumbent    = false;
    u.used_fallback     = false;
    u.solution_source   = "none";

    if solver_diag.termination_class == "normal"
        if has_usable_payload
            u.solution_usable   = true;
            u.optimality_proven = true;
            u.solution_source   = "optimal";
        else
            u.solution_usable   = false;
            u.optimality_proven = false;
            u.solution_source   = "none";
            u.fail_type         = "solver_fail";
            u.termination_class = "error";
        end

    elseif solver_diag.termination_class == "timeout"
        if isfinite(u.incumbent_obj) && has_usable_payload
            u.solution_usable   = true;
            u.optimality_proven = false;
            u.used_incumbent    = true;
            u.solution_source   = "incumbent_timeout";
            u.fail_type         = "timeout_incumbent";
        else
            u.solution_usable   = false;
            u.optimality_proven = false;
            u.solution_source   = "none";
        end
    else
        u.solution_usable   = false;
        u.optimality_proven = false;
        u.solution_source   = "none";
    end
end