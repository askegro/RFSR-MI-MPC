function [pwl, metrics] = buildInvVpackPWLAuto(v_pack_min, v_pack_max, Ns, ocv_max_error_mV)
%BUILDINVVPACKPWLAUTO  Minimum-breakpoint SOS2 PWL for 1/v_pack.
%
%   Finds the smallest n_bp such that the 1/V PWL approximation error,
%   converted to an equivalent pack-voltage error, does not exceed the
%   OCV approximation budget.
%
%   Criterion (evaluated on a fine grid, not a conservative bound):
%
%       max_{v in [v_min, v_max]}  v^2 * |delta_r(v)|  <=  Ns * ocv_max_error_mV * 1e-3
%
%   Derivation:  r_pwl = 1/v + delta_r,  so the linearised voltage error
%   is  |delta_v| = v^2 * |delta_r|.  The OCV budget per cell is
%   ocv_max_error_mV [mV], so the allowable pack-level error is Ns times
%   that value.
%
%   Conservative closed-form version (for intuition / sanity check):
%       v_max^2 * max|delta_r|  <=  Ns * ocv_max_error_mV * 1e-3
%   This overestimates the worst case because v^2 and |delta_r| are not
%   simultaneously maximised at v_max; the full product evaluation used
%   here is tighter and requires fewer breakpoints in practice.
%
% Inputs:
%   v_pack_min        Pack voltage lower limit [V]  (from buildLimits)
%   v_pack_max        Pack voltage upper limit [V]  (from buildLimits)
%   Ns                Number of series cells [-]
%   ocv_max_error_mV  Per-cell OCV PWL max error [mV]  (default: cfg.ocv.max_error_mV = 0.5)
%
% Outputs:
%   pwl     Struct identical to buildInvVpackPWL output:
%             .vgrid, .invgrid, .n, .Vmin, .Vmax, .n_requested
%   metrics Approximation quality summary:
%             .n_bp               breakpoints used
%             .max_delta_r        max|delta_r|  [V^-1]
%             .max_weighted_err_V max v^2*|delta_r|  [V]  (== criterion LHS)
%             .tol_V              criterion RHS  [V]
%             .criterion_met      logical
%             .v_at_max_err       voltage at which max v^2*|delta_r| occurs  [V]
%
% Usage:
%   [pwl, m] = buildInvVpackPWLAuto(limits.v_pack_min, limits.v_pack_max, ...
%                                    cfg.Ns, cfg.ocv.max_error_mV);
%   % then store pwl in  models.pwl.invVpack  as before
%
% See also: buildInvVpackPWL, buildLimits, buildOCVpwl.

    %% --- Defaults and validation -----------------------------------------
    if nargin < 4 || isempty(ocv_max_error_mV)
        ocv_max_error_mV = 0.5;   % [mV]  matches default_config default
    end

    assert(v_pack_min > 0 && v_pack_max > v_pack_min, ...
        'buildInvVpackPWLAuto: require 0 < v_pack_min < v_pack_max.');
    assert(Ns >= 1 && mod(Ns,1) == 0, ...
        'buildInvVpackPWLAuto: Ns must be a positive integer.');
    assert(ocv_max_error_mV > 0, ...
        'buildInvVpackPWLAuto: ocv_max_error_mV must be positive.');

    tol_V = Ns * ocv_max_error_mV * 1e-3;   % pack-level voltage tolerance [V]

    %% --- Fine evaluation grid -------------------------------------------
    n_fine = 2000;
    v_fine    = linspace(v_pack_min, v_pack_max, n_fine)';
    inv_true  = 1 ./ v_fine;

    %% --- Search: increment n_bp until criterion is met ------------------
    N_BP_MAX = 200;   % safety cap — should never be reached in practice
    n_bp     = 2;     % minimum meaningful PWL

    while n_bp <= N_BP_MAX
        pwl_candidate = buildInvVpackPWL(v_pack_min, v_pack_max, n_bp);

        inv_pwl      = interp1(pwl_candidate.vgrid, pwl_candidate.invgrid, ...
                               v_fine, 'linear', 'extrap');
        delta_r      = abs(inv_true - inv_pwl);           % |delta_r(v)|  [V^-1]
        weighted_err = (v_fine .^ 2) .* delta_r;         % v^2*|delta_r| [V]

        if max(weighted_err) <= tol_V
            break;
        end

        n_bp = n_bp + 1;
    end

    if n_bp > N_BP_MAX
        warning('buildInvVpackPWLAuto:NotConverged', ...
            'Criterion not met within %d breakpoints. Using %d.', N_BP_MAX, N_BP_MAX);
    end

    %% --- Final PWL and metrics ------------------------------------------
    pwl = buildInvVpackPWL(v_pack_min, v_pack_max, n_bp);

    inv_pwl_final  = interp1(pwl.vgrid, pwl.invgrid, v_fine, 'linear', 'extrap');
    delta_r_final  = abs(inv_true - inv_pwl_final);
    weighted_final = (v_fine .^ 2) .* delta_r_final;

    [max_w, idx_max] = max(weighted_final);

    metrics.n_bp               = n_bp;
    metrics.max_delta_r        = max(delta_r_final);          % [V^-1]
    metrics.max_weighted_err_V = max_w;                       % [V]
    metrics.tol_V              = tol_V;                       % [V]
    metrics.criterion_met      = (max_w <= tol_V);
    metrics.v_at_max_err       = v_fine(idx_max);             % [V]
    metrics.ocv_max_error_mV   = ocv_max_error_mV;
    metrics.Ns                 = Ns;

    %% --- Report ---------------------------------------------------------
    fprintf('  1/V PWL auto: %d bp | max v²|δr| = %.4f mV (tol %.4f mV) | worst at v=%.1f V\n', ...
        n_bp, max_w * 1e3, tol_V * 1e3, v_fine(idx_max));
    if ~metrics.criterion_met
        fprintf('  WARNING: tolerance not met.\n');
    end
end
