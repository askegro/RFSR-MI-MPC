function solver = buildSolverOptions(cfg)

    solverInfo = struct();
    solverInfo.name = cfg.solver.name;
    
    if exist('sdpsettings','file') ~= 2
        warning('YALMIP not found. Returning empty solver options.');
        ops = struct();
        solverInfo.available = false;
        solver.ops = ops;
        solver.solverInfo = solverInfo;        
        return;
    end
    
    maxSolverTime = cfg.timeLimit;
    
    ops = sdpsettings( ...
        'verbose',0,'debug',0,'warning',1,'showprogress',0, ...
        'cachesolvers',1, ...
        'savesolverinput',0,'savesolveroutput',1, ...
        'savedebug',0,'saveduals',0, ...
        'usex0',0,'warmstart',0);
    
    ops.solver = cfg.solver.name;
    
    switch lower(cfg.solver.name)
        case 'mosek'
            ops.mosek.MSK_IPAR_NUM_THREADS     = 1;
            ops.mosek.MSK_IPAR_MIO_SEED        = 42;
            ops.mosek.MSK_IPAR_SIM_SEED        = 23456;
            %ops.mosek.MSK_DPAR_MIO_TOL_REL_GAP = cfg.solver.gapAllowed;
            ops.mosek.MSK_DPAR_MIO_MAX_TIME    = maxSolverTime;
            ops.mosek.MSK_IPAR_LOG             = 0;
            ops.mosek.MSK_IPAR_LOG_INTPNT      = 0;
            ops.mosek.MSK_IPAR_LOG_MIO         = 0;
            %ops.mosek.MSK_IPAR_PRESOLVE_USE = 'MSK_ON';     % presolve on
    
        case 'gurobi'
            % Honour cfg.solver.threads; fall back to 1 for safety if absent.
            if isfield(cfg.solver, 'threads') && cfg.solver.threads > 0
                ops.gurobi.Threads = cfg.solver.threads;
            else
                ops.gurobi.Threads = 1;
            end
            ops.gurobi.Seed         = 42;
            ops.gurobi.MIPGap       = 1e-4;
            ops.gurobi.TimeLimit    = maxSolverTime;
            ops.gurobi.OutputFlag   = 0;
            ops.gurobi.LogToConsole = 0;
            ops.gurobi.NumericFocus   = 0;      % important
            % ops.gurobi.FeasibilityTol = 1e-8;
            % ops.gurobi.IntFeasTol     = 1e-8;
            % ops.gurobi.OptimalityTol  = 1e-8;
    
        otherwise
            error('Unsupported solver: %s', cfg.solver.name);
    end
    
    % -------------------------------------------------------------------------
    % Optional debug solver I/O
    % -------------------------------------------------------------------------
    if isfield(cfg, 'DEBUG') && isfield(cfg.DEBUG, 'solver_io') && cfg.DEBUG.solver_io
        ops.verbose          = 2;
        ops.debug            = 1;
        ops.savesolverinput  = 1;
        ops.savesolveroutput = 1;
    
        if strcmpi(cfg.solver.name, 'gurobi')
            ops.gurobi.OutputFlag   = 1;
            ops.gurobi.LogToConsole = 1;
        end
    end    

    solverInfo.available = true;

    solver.ops = ops;
    solver.solverInfo = solverInfo;

end
