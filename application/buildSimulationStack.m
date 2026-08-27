function sim = buildSimulationStack(cfg, env, opts)
% BUILDSIMULATIONSTACK Build all immutable simulation dependencies.
%
% This function is the application-layer composition root. It assembles
% chemistry, models, limits, state machine, scales, solver options, logging,
% runtime state, and (optionally) MPC optimizers without running a closed-loop step.
%
% opts.build_optimizers (default true) — set false to skip buildOptimizers.
%   Callers that will mutate constants before building their own optimizer
%   (e.g. tcst_run_variant) should pass false to avoid a wasted build.

    if nargin < 3 || isempty(opts), opts = struct(); end
    if ~isfield(opts, 'build_optimizers'), opts.build_optimizers = true; end

    [chem, raw]          = buildChemistry(cfg);
    models               = buildModels(cfg, chem, raw);
    models.ocv.ocv_pwl   = buildOCVpwl(cfg, chem);
    limits               = buildLimits(cfg, models, raw.constraints);
    models.pwl.invVpack  = buildInvVpackPWLAuto(limits.v_pack_min, limits.v_pack_max, cfg.Ns, cfg.limits.inv_vpack_max_err_mV);
    chg                  = buildChargingParams(cfg, chem, limits);
    driveCycle           = buildDriveCycle(cfg, limits, models);
    [states, ~, stateInitID, id2name] = buildStateMachineEnum(cfg);
    sm                   = buildStateMachine(states, stateInitID, cfg.stateMachineParams, chg, id2name);
    x0                   = buildInitialState(cfg, env, models);
    scale                = buildScales(limits, driveCycle);
    solver               = buildSolverOptions(cfg);
    constants            = buildConstantsBundle(cfg, env, chem, raw, models, limits, chg, states, driveCycle, scale, solver);
    log                  = buildLogging(cfg);
    runtime              = buildRuntimeInit(cfg, sm, x0, models);

    if opts.build_optimizers
        opt = buildOptimizers(constants);
    else
        opt = [];
    end

    sim = struct();
    sim.chem       = chem;
    sim.raw        = raw;
    sim.models     = models;
    sim.limits     = limits;
    sim.chg        = chg;
    sim.driveCycle = driveCycle;
    sim.states     = states;
    sim.stateInitID = stateInitID;
    sim.id2name    = id2name;
    sim.sm         = sm;
    sim.x0         = x0;
    sim.scale      = scale;
    sim.solver     = solver;
    sim.constants  = constants;
    sim.log        = log;
    sim.runtime    = runtime;
    sim.opt        = opt;
end
