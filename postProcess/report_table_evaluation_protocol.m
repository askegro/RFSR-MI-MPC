% postProcess/report_table_evaluation_protocol.m
%
% Reproduces manuscript Table I (tab:evaluation_protocol, "Nominal
% Evaluation Parameters") directly from the configuration and build
% pipeline, so the printed table stays in sync with the code that
% actually runs the nominal WLTC evaluation (Section V-A).
%
% Unlike the other TABLE-producing scripts in postProcess/, this table
% is not derived from a saved simulation log: every entry except the
% CPU descriptor is read here from default_config() and the immutable
% build pipeline (buildChemistry / buildLimits / buildScaledDriveCycle),
% so a change to the nominal parameters is automatically reflected here
% without hand-editing this file.
%
% Column layout mirrors the manuscript table exactly: two
% (Quantity, Value) pairs per row.
%
% Manuscript symbol -> code source:
%   N                                cfg.Ns
%   N_p                              cfg.mpc.Np
%   Delta t                          cfg.Tstep
%   Demand                           cfg.driveCycle.type (+ DriveCycleFile)
%   (w_SOH, w_SOC, w_lambda)         cfg.w.SOH, cfg.w.SOC, cfg.w.lambda
%   t_lim^op                         cfg.timeLimit
%   Relative MIP-gap tolerance       solver.gurobi.MIPGap  (buildSolverOptions.m)
%   v_cell = [v_cell^min,v_cell^max] limits.v_cell_min / v_cell_max
%   v_pack = [v_pack^min,v_pack^max] limits.v_pack_min / v_pack_max
%   i_pack = [i_pack^min,i_pack^max] limits.i_pack_min / i_pack_max
%   SOC_cell                        limits.z_cell_min / z_cell_max
%   T_cell                          limits.T_cell_min / T_cell_max
%   SOH^EOL                         cfg.EOL.threshold
%   delta_P                         cfg.mpc.delta_P_curtail
%   (Delta_low, Delta_high)          cfg.mpc.socSpread.Delta_low / Delta_high
%   (z1, z2)                         cfg.mpc.socSpread.z_low / z_high
%   sigma_Delta                      cfg.mpc.socSpread.slew_rate
%   SOC_i(0) ~ N(mu,sigma^2)         cfg.z_cell_init_mean / z_cell_init_spread
%   SOH_i(0) ~ N(mu,sigma^2)         cfg.SOH_cell_init_mean / SOH_cell_init_spread
%   T_i(0)                           models.therm.T_amb (buildInitialState.m)
%   i_RC,i(0)                        0 A (buildInitialState.m, hardcoded)
%   kappa_WLTC                       Results.scale_factor (buildScaledDriveCycle.m)
%   CPU                              hardware descriptor; not derivable from code

clc;
thisFile    = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));  % parent of postProcess
addpath(projectRoot);
rootDir     = initProjectPaths(thisFile);
fprintf('=== REPORT TABLE I: Nominal Evaluation Parameters (tab:evaluation_protocol) ===\n\n');

SEP = repmat('=', 1, 74);
sep = repmat('-', 1, 74);

cfg = default_config();

%% Resolve physical bounds and kappa_WLTC from the immutable build pipeline.
% Wrapped in try/catch so this report degrades gracefully (falls back to
% cfg-only rows) if run in an environment without the chemistry data
% files or YALMIP/Gurobi on the path.
haveLimits = false;
kappa_WLTC = NaN;
T_amb      = NaN;
try
    [chem, raw]  = buildChemistry(cfg); %#ok<ASGLU>
    models       = buildModels(cfg, chem, raw);
    limits       = buildLimits(cfg, models, raw.constraints);
    T_amb        = models.therm.T_amb;
    haveLimits   = true;

    [Results, ~, ~] = buildScaledDriveCycle( ...
        cfg.DriveCycleFile, cfg.N_cycles_required, ...
        limits.z_cell_max, limits.z_cell_min, ...
        cfg.CellChemistry, cfg.CellParamFile, cfg.Ns, cfg.Np, false);
    kappa_WLTC = Results.scale_factor;
catch ME
    warning('report_table_evaluation_protocol:buildFailed', ...
        'Could not build chemistry/limits/drive-cycle pipeline (%s). Physical-bound and kappa_WLTC rows will be shown as N/A.', ME.message);
end

try
    solver = buildSolverOptions(cfg);
    mipGap = solver.gurobi.MIPGap;
catch
    mipGap = 1e-4;  % literal in build/buildSolverOptions.m; used as fallback only
end

fmt2 = @(lab1,val1,lab2,val2) fprintf('%-26s %-18s %-26s %-18s\n', lab1, val1, lab2, val2);

fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:evaluation_protocol>>>\n');
fprintf('%s\n', SEP);
fmt2('N', sprintf('%d', cfg.Ns), 'N_p', sprintf('%d', cfg.mpc.Np));
fmt2('Delta t [s]', sprintf('%.0f', cfg.Tstep), 'Demand', 'Scaled WLTC Class 3');
fmt2('(w_SOH,w_SOC,w_lambda)', sprintf('(%d,%d,%d)', cfg.w.SOH, cfg.w.SOC, cfg.w.lambda), ...
     't_lim^op [s]', sprintf('%.0f', cfg.timeLimit));
fmt2('Relative MIP-gap tolerance', sprintf('%.0e', mipGap), 'CPU', 'i7-1370P (13th Gen)  [hardware; not code-derived]');
if haveLimits
    fmt2('v_cell [V]', sprintf('[%.2f, %.2f]', limits.v_cell_min, limits.v_cell_max), ...
         'v_pack [V]', sprintf('[%.1f, %.1f]', limits.v_pack_min, limits.v_pack_max));
    fmt2('i_pack [A]', sprintf('[%.1f, %.1f]', limits.i_pack_min, limits.i_pack_max), ...
         'SOC_cell [-]', sprintf('[%.2f, %.2f]', limits.z_cell_min, limits.z_cell_max));
    % limits.T_cell_min/max are in KELVIN (see LFPChemistry.constraints).
    % Table I is in degrees Celsius, so convert before printing.
    fmt2('T_cell [C]', sprintf('[%.0f, %.0f]', ...
            limits.T_cell_min - 273.15, limits.T_cell_max - 273.15), ...
         'SOH^EOL [-]', sprintf('%.2f', cfg.EOL.threshold));
else
    fmt2('v_cell [V]', 'N/A (build failed)', 'v_pack [V]', 'N/A (build failed)');
    fmt2('i_pack [A]', 'N/A (build failed)', 'SOC_cell [-]', 'N/A (build failed)');
    fmt2('T_cell [C]', 'N/A (build failed)', 'SOH^EOL [-]', sprintf('%.2f', cfg.EOL.threshold));
end
fmt2('delta_P [-]', sprintf('%.2f', cfg.mpc.delta_P_curtail), ...
     '(Delta_low,Delta_high)', sprintf('(%.2f,%.2f)', cfg.mpc.socSpread.Delta_low, cfg.mpc.socSpread.Delta_high));
fmt2('(z1,z2)', sprintf('(%.2f,%.2f)', cfg.mpc.socSpread.z_low, cfg.mpc.socSpread.z_high), ...
     'sigma_Delta [p.u./s]', sprintf('%.3f', cfg.mpc.socSpread.slew_rate));
fmt2('SOC_i(0)', sprintf('N(%.1f,%.3f^2)', cfg.z_cell_init_mean, cfg.z_cell_init_spread), ...
     'SOH_i(0)', sprintf('N(%.2f,%.2f^2)', cfg.SOH_cell_init_mean, cfg.SOH_cell_init_spread));
if isfinite(T_amb)
    % T_amb is in KELVIN; Table I is in degrees Celsius.
    fmt2('T_i(0) [C]', sprintf('%.0f', T_amb - 273.15), 'i_RC,i(0) [A]', '0');
else
    fmt2('T_i(0) [C]', 'N/A (build failed)', 'i_RC,i(0) [A]', '0');
end
if isfinite(kappa_WLTC)
    fmt2('kappa_WLTC [-]', sprintf('%.6f', kappa_WLTC), '', '');
else
    fmt2('kappa_WLTC [-]', 'N/A (build failed)', '', '');
end
fprintf('%s\n', SEP);
fprintf('<<<MANUSCRIPT_TABLE_END tab:evaluation_protocol>>>\n');
fprintf('\nNote: SOC/SOH/T/i_RC distributions are clipped to the admissible range in buildInitialState.m,\n');
fprintf('matching the manuscript footnote to Table I.\n');

fprintf('\n=== Report complete (Table I) ===\n');
