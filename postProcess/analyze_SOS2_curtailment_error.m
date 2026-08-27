% analyze_SOS2_curtailment_error.m
%
% Post-processing check: SOS2 approximation error in the curtailment variable.
%
% At each active step the optimizer solves a MICP in which 1/v_pack is
% approximated by a piecewise-linear SOS2 interpolant r_PL(v_pack).  The
% resulting curtailment slack is
%
%   lambda_SOS2(k) = log.slack_mag(k)        [from optimizer, uses SOS2]
%
% The exact value, computed from the realized closed-loop trajectory, is
%
%   lambda_exact(k) = ( p_req(k) - i_pack(k)*v_pack_meas(k) )
%                     / ( sgn(p_req(k)) * v_pack_meas(k) )
%
% This check reports  max_k |lambda_SOS2(k) - lambda_exact(k)|  over all
% active discharge/charge steps, and compares it to the analytical bound
% derived in the Appendix (Detailed Mixed-Integer Convex Reformulation).
%
% NOTE: the difference between lambda_SOS2 and lambda_exact reflects both
%   (a) the SOS2 approximation error in 1/v_pack  [of primary interest], and
%   (b) the mismatch between the MPC-predicted v_pack and the realized
%       v_pack_meas (OCV linearization, RC model, etc.).
% Using the realized pack voltage gives the more conservative (reviewer-friendly)
% bound.  A second comparison against the MPC-predicted v_pack isolates the
% pure SOS2 error.
%
% Usage:
%   Run from the project root after
%   mainSimulationRunners/run_nominal_wltc.m has completed.

clc;

thisFile    = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(projectRoot);
rootDir     = initProjectPaths(thisFile);

%% -------------------------------------------------------------------------
%  Load the nominal-WLTC result
%  -------------------------------------------------------------------------
latestFile = findLatestResultFile( ...
    fullfile(rootDir, 'results', 'Results_nominal_wltc_*.mat'), ...
    'Run mainSimulationRunners/run_nominal_wltc.m first.');

fprintf('Loading %s ...\n\n', latestFile);
data = load(latestFile);
R    = data.Results;
cfg  = data.cfg;

MC         = metricsConfig();
CURT_TOL   = MC.CURTAILMENT_THRESHOLD_A;   % manuscript eps_lambda = 0.01 A (Sec. V-B, eq:curtRate)
SOLVER_TOL = cfg.NUMERICS.CURT_TOL;        % solver zero-out tolerance (1e-7 A), reference only
P_EPS      = cfg.NUMERICS.TRACKING_POWER_EPS;

%% -------------------------------------------------------------------------
%  Per-variant lambda error check
%  -------------------------------------------------------------------------
variants = {'A', 'D'};

for v = variants
    vid = v{1};
    L   = R.(vid).log;

    p_req    = L.p_pack_req(:)';     % 1 x nSteps — requested power
    i_pack   = L.i_pack_cmd(:)';     % 1 x nSteps — applied current
    v_meas   = L.v_pack_meas(:)';    % 1 x nSteps — realized plant voltage
    v_pred   = L.v_pack(:)';         % 1 x nSteps — MPC first-step predicted voltage
    lam_SOS2 = L.slack_mag(:)';      % 1 x nSteps — optimizer curtailment slack

    % Active mask: nonzero power request AND usable solution
    act = abs(p_req) > P_EPS & L.solution_usable(:)';
    dis = act & (p_req > 0);
    chg = act & (p_req < 0);

    fprintf('=== Variant %s ===\n', vid);
    fprintf('  Active steps: %d   (dis: %d, chg: %d)\n', sum(act), sum(dis), sum(chg));

    % ------------------------------------------------------------------
    %  (1) lambda_exact from realized closed-loop data — conservative bound
    %      Captures SOS2 error + model prediction mismatch in v_pack.
    % ------------------------------------------------------------------
    safe_meas = act & (v_meas > 0);

    lam_exact_meas = zeros(1, numel(p_req));
    lam_exact_meas(dis & safe_meas) = ...
        (p_req(dis & safe_meas) - i_pack(dis & safe_meas) .* v_meas(dis & safe_meas)) ...
        ./ v_meas(dis & safe_meas);
    lam_exact_meas(chg & safe_meas) = ...
        -(p_req(chg & safe_meas) - i_pack(chg & safe_meas) .* v_meas(chg & safe_meas)) ...
        ./ v_meas(chg & safe_meas);

    err_meas_act = (lam_SOS2(safe_meas) - lam_exact_meas(safe_meas));

    fprintf('\n  --- Comparison vs. realized v_pack_meas ---\n');
    fprintf('  max |lambda_SOS2 - lambda_exact|  = %.4e A\n', max(abs(err_meas_act)));
    fprintf('  mean|lambda_SOS2 - lambda_exact|  = %.4e A\n', mean(abs(err_meas_act)));
    fprintf('  max  lambda_SOS2                  = %.4e A\n', max(lam_SOS2(safe_meas)));
    fprintf('  max  lambda_exact                 = %.4e A\n', max(lam_exact_meas(safe_meas)));

    % ------------------------------------------------------------------
    %  (2) lambda_exact from MPC-predicted v_pack — pure SOS2 error
    %      Uses the same voltage the optimizer saw; removes model mismatch.
    % ------------------------------------------------------------------
    safe_pred = act & (v_pred > 0);

    lam_exact_pred = zeros(1, numel(p_req));
    lam_exact_pred(dis & safe_pred) = ...
        (p_req(dis & safe_pred) - i_pack(dis & safe_pred) .* v_pred(dis & safe_pred)) ...
        ./ v_pred(dis & safe_pred);
    lam_exact_pred(chg & safe_pred) = ...
        -(p_req(chg & safe_pred) - i_pack(chg & safe_pred) .* v_pred(chg & safe_pred)) ...
        ./ v_pred(chg & safe_pred);

    err_pred_act = (lam_SOS2(safe_pred) - lam_exact_pred(safe_pred));

    fprintf('\n  --- Comparison vs. MPC-predicted v_pack (pure SOS2 error) ---\n');
    fprintf('  max |lambda_SOS2 - lambda_exact_pred|  = %.4e A\n', max(abs(err_pred_act)));
    fprintf('  mean|lambda_SOS2 - lambda_exact_pred|  = %.4e A\n', mean(abs(err_pred_act)));

    % ------------------------------------------------------------------
    %  (3) Analytical bound on SOS2 error
    %      epsilon_SOS2 <= h^2/8 * max|f''(v)| = h^2/8 * 2/v_min^3
    %      Uses the actual saved PWL grid from constants_v.
    % ------------------------------------------------------------------
    pwl_  = R.(vid).constants_v.models.pwl.invVpack;
    v_bp_ = pwl_.vgrid(:);
    Nv_   = numel(v_bp_);
    h_    = max(diff(v_bp_));         % max segment width (uniform => all equal)
    eps_SOS2_anal = (h_^2 / 8) * (2 / v_bp_(1)^3);
    p_peak = max(abs(p_req(act)));
    lam_bound_anal = p_peak * eps_SOS2_anal;

    fprintf('\n  --- Analytical SOS2 bound ---\n');
    fprintf('  Nv = %d breakpoints, max segment h = %.4f V\n', Nv_, h_);
    fprintf('  max |1/v - r_PL(v)| (analytical) = %.4e V^-1\n', eps_SOS2_anal);
    fprintf('  Bound on lambda error              = %.4e A  (at peak |p_req| = %.1f W)\n', ...
        lam_bound_anal, p_peak);
    fprintf('  Curtailment threshold eps_lambda   = %.4e A\n', CURT_TOL);
    fprintf('  Bound / threshold                  = %.4f\n\n', lam_bound_anal / CURT_TOL);
end

%% -------------------------------------------------------------------------
%  Numerical SOS2 fit error — exact max over fine grid
%  Uses the actual saved PWL grid (constants_v.models.pwl.invVpack).
%  -------------------------------------------------------------------------
fprintf('--- APPENDIX: SOS2 approximation of the inverse pack voltage ---\n');
fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:appendix_sos2>>>\n');
fprintf('=== SOS2 fit: numerical max pointwise error (actual saved PWL) ===\n');

pwl  = R.D.constants_v.models.pwl.invVpack;
v_bp = pwl.vgrid(:);
r_bp = pwl.invgrid(:);
Nv   = numel(v_bp);

v_fine  = linspace(v_bp(1), v_bp(end), 10000);
r_exact = 1 ./ v_fine;
r_PL    = interp1(v_bp, r_bp, v_fine, 'linear');

max_fit_err = max(abs(r_PL - r_exact));
p_peak_D    = max(abs(R.D.log.p_pack_req));

fprintf('  PWL: %d breakpoints over [%.2f, %.2f] V\n', Nv, v_bp(1), v_bp(end));
fprintf('  Max |r_PL(v) - 1/v|                   = %.4e V^-1\n', max_fit_err);
fprintf('  Implied max lambda error (Var D peak)  = %.4e A  (peak |p_req| = %.1f W)\n', ...
    p_peak_D * max_fit_err, p_peak_D);
fprintf('  Curtailment threshold eps_lambda       = %.4e A\n', CURT_TOL);
fprintf('  Error / threshold                      = %.4f\n\n', ...
    p_peak_D * max_fit_err / CURT_TOL);
fprintf('<<<MANUSCRIPT_TABLE_END tab:appendix_sos2>>>\n');
fprintf('\n');

