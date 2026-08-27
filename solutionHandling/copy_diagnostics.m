function u = copy_diagnostics(u, sd)
% COPY_DIAGNOSTICS  Copy solver diagnostic fields into the command struct.

    u.problem_code      = sd.problem_code;
    u.status_str        = sd.status_str;
    u.termination       = sd.termination;
    u.termination_class = sd.termination_class;
    u.fail_type         = sd.fail_type;
    u.mip_gap           = sd.mip_gap;
    u.obj_val           = sd.obj_val;
    u.best_bound        = sd.best_bound;
    u.incumbent_obj     = sd.incumbent_obj;
    u.node_count        = sd.node_count;
    u.solver_time       = sd.solver_time;
end