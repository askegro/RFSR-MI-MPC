function [m_ocv, b_ocv] = ocv_affine_from_pwl(z0_vec, soc_bp, v_bp)
% OCV_AFFINE_FROM_PWL  Local affine OCV model from a piecewise-linear table.
%
% Inputs
%   z0_vec  Ns x 1 current SOC values
%   soc_bp  n_bp x 1 SOC breakpoints (monotone increasing)
%   v_bp    n_bp x 1 OCV breakpoints
%
% Outputs
%   m_ocv   Ns x 1 local slope at each cell's current SOC
%   b_ocv   Ns x 1 local intercept at each cell's current SOC
%
% Notes
%   The SOC is clamped to the breakpoint domain before segment selection.

    Ns    = numel(z0_vec);
    m_ocv = zeros(Ns, 1);
    b_ocv = zeros(Ns, 1);

    for i = 1:Ns
        z0 = z0_vec(i);

        % Clamp SOC to the available breakpoint range
        z0 = max(soc_bp(1), min(soc_bp(end), z0));

        % Find segment j such that soc_bp(j) <= z0 <= soc_bp(j+1)
        j = find(soc_bp <= z0, 1, 'last');
        if j == numel(soc_bp)
            j = j - 1;
        end

        zL = soc_bp(j);   zU = soc_bp(j+1);
        vL = v_bp(j);     vU = v_bp(j+1);

        m  = (vU - vL) / (zU - zL);
        v0 = vL + m * (z0 - zL);
        b  = v0 - m * z0;

        m_ocv(i) = m;
        b_ocv(i) = b;
    end
end