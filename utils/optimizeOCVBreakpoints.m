function [soc_bp_opt, v_bp_opt, metrics] = optimizeOCVBreakpoints(chem, z_min, z_max, max_error_mV, max_points)
%OPTIMIZEOCVBREAKPOINTS Find minimum breakpoints for target accuracy
%
% Greedy refinement: iteratively adds a breakpoint where the absolute error
% between the true OCV and a piecewise-linear (PWL) approximation is largest.
%
% Fixes vs. original:
%   - spacing is relative to SOC range
%   - never calls computeOCV on unsorted SOC
%   - only computes OCV at the *new* breakpoint (no full recompute)
%   - evaluates max error with per-segment sampling (reduces “missed peak” risk)
%   - clamps SOC and uses extrap-safe interpolation
%
% Inputs:
%   chem         - Chemistry object with computeOCV(soc)
%   z_min, z_max - SOC operating range
%   max_error_mV - Target maximum error [mV]
%   max_points   - Maximum allowed breakpoints (optional, default: 50)
%
% Returns:
%   soc_bp_opt - Optimal breakpoint locations
%   v_bp_opt   - Voltages at breakpoints
%   metrics    - Error statistics structure

    if nargin < 5 || isempty(max_points)
        max_points = 50;
    end

    % Validate range
    if ~(isfinite(z_min) && isfinite(z_max) && z_max > z_min)
        error('Invalid SOC range: require finite z_min < z_max.');
    end
    if ~(isfinite(max_error_mV) && max_error_mV >= 0)
        error('max_error_mV must be finite and >= 0.');
    end
    if ~(isscalar(max_points) && max_points >= 2)
        error('max_points must be a scalar >= 2.');
    end

    % Hard SOC lower bound (15%)
    soc_lower_limit = 0.15;
    
    if z_min < soc_lower_limit
        warning('optimizeOCVBreakpoints:ClampedZmin', ...
                'z_min=%.3f clamped to %.3f (15%% SOC).', z_min, soc_lower_limit);
        z_min = soc_lower_limit;
    end    

    % Dense reference curve for final metrics (and plotting/debug)
    n_fine = 1001;  
    soc_fine = linspace(z_min, z_max, n_fine)'; % includes endpoints
    v_fine = chem.computeOCV(soc_fine);

    % Initialize with endpoints (sorted by construction)
    soc_bp = [z_min; z_max];
    v_bp   = [v_fine(1); v_fine(end)]; % avoid computeOCV call for endpoints

    fprintf('\n=== Optimizing OCV Breakpoints ===\n');
    fprintf('Target: max error ≤ %.3f mV\n', max_error_mV);
    fprintf('Initial: 2 points (endpoints only)\n');

    % Spacing: 0.5% of SOC *range*
    min_spacing = 0.005 * (z_max - z_min);

    % Numerical tolerance for duplicate detection
    eps_tol = max(1e-12, 10*eps(max(abs([z_min z_max]))));

    % Per-segment sampling for max error search
    % (bigger => more robust peak detection, slower)
    n_seg_samples = 51;  % includes endpoints of each segment
    if n_seg_samples < 3
        n_seg_samples = 3;
    end

    iteration = 0;

    while numel(soc_bp) < max_points
        iteration = iteration + 1;

        % Ensure sorted (should be already, but keep invariant explicit)
        [soc_bp, sort_idx] = sort(soc_bp);
        v_bp = v_bp(sort_idx);

        % ---- Find worst error using per-segment sampling ----
        worst_err_V = -Inf;
        worst_soc   = NaN;

        for k = 1:(numel(soc_bp)-1)
            a = soc_bp(k);
            b = soc_bp(k+1);

            % Skip degenerate segment
            if b <= a + eps_tol
                continue;
            end

            % Sample inside the segment (includes endpoints)
            soc_seg = linspace(a, b, n_seg_samples)';

            % True OCV and PWL estimate on this segment
            v_true = chem.computeOCV(soc_seg);

            % PWL on segment (explicit formula; avoids interp1 overhead here)
            va = v_bp(k);
            vb = v_bp(k+1);
            t  = (soc_seg - a) ./ (b - a);
            v_pwl = va + t .* (vb - va);

            err_abs = abs(v_true - v_pwl);
            [seg_max, idx] = max(err_abs);

            if seg_max > worst_err_V
                worst_err_V = seg_max;
                worst_soc   = soc_seg(idx);
            end
        end

        error_max_mV = worst_err_V * 1000;

        fprintf('  Iter %2d: %2d points → max error ≈ %.3f mV\n', ...
                iteration, numel(soc_bp), error_max_mV);

        % Check if target achieved
        if error_max_mV <= max_error_mV
            fprintf('✓ Target achieved with %d breakpoints!\n', numel(soc_bp));
            break;
        end

        % Clamp candidate to range (paranoia)
        soc_new = min(max(worst_soc, z_min), z_max);

        % Avoid duplicates / too-close insertions
        dmin = min(abs(soc_bp - soc_new));
        if dmin < min_spacing || dmin < eps_tol
            % Search for next-best point by scanning segments again and picking
            % the best point that satisfies spacing.
            found = false;
            best_err_V = -Inf;
            best_soc   = NaN;

            for k = 1:(numel(soc_bp)-1)
                a = soc_bp(k);
                b = soc_bp(k+1);
                if b <= a + eps_tol
                    continue;
                end

                soc_seg = linspace(a, b, n_seg_samples)';

                % Reject points too close up front (cheap)
                % (keep endpoints too; spacing check will reject if needed)
                ok = true(size(soc_seg));
                for j = 1:numel(soc_bp)
                    ok = ok & (abs(soc_seg - soc_bp(j)) >= min_spacing);
                end
                ok = ok & (abs(soc_seg - z_min) >= 0) & (abs(soc_seg - z_max) >= 0); %#ok<NASGU>

                if ~any(ok)
                    continue;
                end

                v_true = chem.computeOCV(soc_seg);

                va = v_bp(k);
                vb = v_bp(k+1);
                t  = (soc_seg - a) ./ (b - a);
                v_pwl = va + t .* (vb - va);

                err_abs = abs(v_true - v_pwl);

                % Consider only spacing-valid candidates
                err_abs(~ok) = -Inf;

                [seg_max, idx] = max(err_abs);
                if seg_max > best_err_V && isfinite(seg_max)
                    best_err_V = seg_max;
                    best_soc = soc_seg(idx);
                    found = true;
                end
            end

            if ~found
                fprintf('⚠ Cannot add more points (spacing constraint blocks all candidates)\n');
                break;
            end

            soc_new = best_soc;
        end

        % Final duplicate guard
        if min(abs(soc_bp - soc_new)) < eps_tol
            fprintf('⚠ Candidate breakpoint is numerically duplicate; stopping.\n');
            break;
        end

        % ---- Insert new breakpoint (compute OCV only at new point) ----
        v_new = chem.computeOCV(soc_new);

        soc_bp = [soc_bp; soc_new];
        v_bp   = [v_bp; v_new];
    end

    % ---- Final evaluation on a dense grid for reported metrics ----
    [soc_bp, sort_idx] = sort(soc_bp);
    v_bp = v_bp(sort_idx);

    % Clamp soc_fine just in case
    soc_fine_eval = min(max(soc_fine, z_min), z_max);

    % Use extrap to avoid NaNs from floating edge cases
    v_pwl_final = interp1(soc_bp, v_bp, soc_fine_eval, 'linear', 'extrap');

    error_final = abs(v_fine - v_pwl_final);

    soc_bp_opt = soc_bp;
    v_bp_opt   = v_bp;

    metrics.n_points      = numel(soc_bp);
    metrics.max_error_mV  = max(error_final) * 1000;
    metrics.rms_error_mV  = sqrt(mean(error_final.^2)) * 1000;
    metrics.mean_error_mV = mean(error_final) * 1000;
    metrics.soc_fine      = soc_fine;
    metrics.v_fine        = v_fine;
    metrics.v_pwl         = v_pwl_final;
    metrics.error_abs     = error_final;

    fprintf('\n=== Final Result ===\n');
    fprintf('Breakpoints: %d\n', metrics.n_points);
    fprintf('Max error:   %.3f mV\n', metrics.max_error_mV);
    fprintf('RMS error:   %.3f mV\n', metrics.rms_error_mV);
    fprintf('Mean error:  %.3f mV\n', metrics.mean_error_mV);

    if metrics.max_error_mV > max_error_mV
        fprintf('⚠ Target NOT met (target %.3f mV)\n', max_error_mV);
    else
        fprintf('✓ Target met (target %.3f mV)\n', max_error_mV);
    end

    fprintf('====================\n\n');
end
