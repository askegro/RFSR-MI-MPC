function sd = extract_solver_diagnostics(diagnostics)
% EXTRACT_SOLVER_DIAGNOSTICS  Extract common solver diagnostics from a
% YALMIP diagnostics struct.
%
% Purpose
%   Provide a solver-agnostic summary of the most useful diagnostic fields
%   used by the controller:
%     - termination classification
%     - objective / incumbent / bound information
%     - relative gap
%     - node count
%
% Notes
%   - Designed primarily for YALMIP + Gurobi.
%   - Includes graceful fallback for alternative solver-output layouts.
%   - Uses problem_code first when possible, then status text as fallback.
%
% Returned fields:
%   problem_code      - YALMIP diagnostics.problem
%   status_str        - diagnostics.infostr if available
%   termination       - same as status_str unless better info exists
%   termination_class - "normal", "timeout", "infeasible", "error"
%   fail_type         - "none", "timeout", "solver_fail"
%   obj_val           - final/incumbent objective if available
%   incumbent_obj     - same as obj_val unless separate incumbent is exposed
%   best_bound        - best known bound if available
%   mip_gap           - relative MIP gap if available or computable
%   node_count        - branch-and-bound node count if available

    % ------------------------------------------------------------
    % Default output
    % ------------------------------------------------------------
    sd = struct();
    sd.problem_code      = NaN;
    sd.status_str        = "N/A";
    sd.termination       = "N/A";
    sd.termination_class = "error";
    sd.fail_type         = "solver_fail";

    sd.obj_val       = NaN;
    sd.incumbent_obj = NaN;
    sd.best_bound    = NaN;
    sd.mip_gap       = NaN;
    sd.node_count    = NaN;
    sd.solver_time   = NaN;

    % ------------------------------------------------------------
    % Validate input
    % ------------------------------------------------------------
    if ~isstruct(diagnostics) || isempty(diagnostics)
        return;
    end

    % ------------------------------------------------------------
    % Basic YALMIP fields
    % ------------------------------------------------------------
    if isfield(diagnostics, 'problem') && ~isempty(diagnostics.problem)
        sd.problem_code = double(diagnostics.problem);
    end

    if isfield(diagnostics, 'infostr') && ~isempty(diagnostics.infostr)
        sd.status_str  = string(diagnostics.infostr);
        sd.termination = string(diagnostics.infostr);
    end

    % ------------------------------------------------------------
    % Classify termination
    % ------------------------------------------------------------
    txt = lower(char(sd.status_str));

    if sd.problem_code == 0
        sd.termination_class = "normal";
        sd.fail_type         = "none";
    elseif contains(txt, 'time')
        sd.termination_class = "timeout";
        sd.fail_type         = "timeout";
    elseif contains(txt, 'infeas')
        sd.termination_class = "infeasible";
        sd.fail_type         = "solver_fail";
    else
        sd.termination_class = "error";
        sd.fail_type         = "solver_fail";
    end

    % ------------------------------------------------------------
    % Solver-specific output
    % ------------------------------------------------------------
    if ~isfield(diagnostics, 'solveroutput') || isempty(diagnostics.solveroutput)
        return;
    end

    so = diagnostics.solveroutput;

    % ------------------------------------------------------------
    % Gurobi-style nested result struct
    % ------------------------------------------------------------
    if isfield(so, 'result') && isstruct(so.result)
        r = so.result;

        if isfield(r, 'runtime') && ~isempty(r.runtime)
            sd.solver_time = double(r.runtime);
        end

        if isfield(r, 'objval') && ~isempty(r.objval)
            sd.obj_val       = double(r.objval);
            sd.incumbent_obj = double(r.objval);
        end

        if isfield(r, 'objbound') && ~isempty(r.objbound)
            sd.best_bound = double(r.objbound);
        end

        if isfield(r, 'mipgap') && ~isempty(r.mipgap)
            sd.mip_gap = double(r.mipgap);
        elseif ~isnan(sd.obj_val) && ~isnan(sd.best_bound)
            denom      = max(1e-12, abs(sd.obj_val));
            sd.mip_gap = abs(sd.obj_val - sd.best_bound) / denom;
        end

        if isfield(r, 'nodecount') && ~isempty(r.nodecount)
            sd.node_count = double(r.nodecount);
        elseif isfield(r, 'NodeCount') && ~isempty(r.NodeCount)
            sd.node_count = double(r.NodeCount);
        end

        return;
    end

    % ------------------------------------------------------------
    % Flat solveroutput layout
    % ------------------------------------------------------------
    if isfield(so, 'runtime') && ~isempty(so.runtime)
        sd.solver_time = double(so.runtime);
    end

    if isfield(so, 'objval') && ~isempty(so.objval)
        sd.obj_val       = double(so.objval);
        sd.incumbent_obj = double(so.objval);
    end

    if isfield(so, 'objbound') && ~isempty(so.objbound)
        sd.best_bound = double(so.objbound);
    end

    if isfield(so, 'mipgap') && ~isempty(so.mipgap)
        sd.mip_gap = double(so.mipgap);
    elseif ~isnan(sd.obj_val) && ~isnan(sd.best_bound)
        denom      = max(1e-12, abs(sd.obj_val));
        sd.mip_gap = abs(sd.obj_val - sd.best_bound) / denom;
    end

    if isfield(so, 'nodecount') && ~isempty(so.nodecount)
        sd.node_count = double(so.nodecount);
    elseif isfield(so, 'NodeCount') && ~isempty(so.NodeCount)
        sd.node_count = double(so.NodeCount);
    end

    % ------------------------------------------------------------
    % Alternative primal-objective fields
    % ------------------------------------------------------------
    try
        if isnan(sd.obj_val) && isfield(so, 'sol') && isstruct(so.sol)
            if isfield(so.sol, 'int') && isstruct(so.sol.int) ...
                    && isfield(so.sol.int, 'pobjval') && ~isempty(so.sol.int.pobjval)
                sd.obj_val       = double(so.sol.int.pobjval);
                sd.incumbent_obj = double(so.sol.int.pobjval);
            elseif isfield(so.sol, 'itr') && isstruct(so.sol.itr) ...
                    && isfield(so.sol.itr, 'pobjval') && ~isempty(so.sol.itr.pobjval)
                sd.obj_val       = double(so.sol.itr.pobjval);
                sd.incumbent_obj = double(so.sol.itr.pobjval);
            end
        end
    catch
    end

    % ------------------------------------------------------------
    % Alternative gap fields
    % ------------------------------------------------------------
    try
        if isfield(so, 'res') && isfield(so.res, 'info') && isstruct(so.res.info)
            info = so.res.info;

            candidateGapFields = { ...
                'MSK_DINF_MIO_REL_GAP', ...
                'mio_rel_gap',          ...
                'relgap',               ...
                'MIO_REL_GAP'};

            for i = 1:numel(candidateGapFields)
                f = candidateGapFields{i};
                if isfield(info, f) && ~isempty(info.(f))
                    sd.mip_gap = double(info.(f));
                    break;
                end
            end
        end
    catch
    end
end