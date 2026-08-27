function pwl = buildInvVpackPWL(v_pack_min, v_pack_max, n_vpack_bp)
%BUILDINVVPACKPWL  Precompute SOS2 PWL grid for inv(Vpack).
%
% Outputs struct pwl with fields:
%   .vgrid     (n x 1) increasing voltage grid
%   .invgrid   (n x 1) corresponding 1/V values
%   .n         scalar number of breakpoints (after unique cleanup)
%   .Vmin, .Vmax, .n_requested

    Vmin = v_pack_min;
    Vmax = v_pack_max;

    inv_min = 1 / Vmax;
    inv_max = 1 / Vmin;

    invgrid = linspace(inv_min, inv_max, n_vpack_bp)';  % increasing
    vgrid   = 1 ./ invgrid;                             % decreasing

    % SOS2 expects ordered x-axis; use V as x and make it increasing
    vgrid   = flipud(vgrid);
    invgrid = flipud(invgrid);

    % Remove duplicates (cheap insurance)
    [vgrid, ia] = unique(vgrid, 'stable');
    invgrid     = invgrid(ia);

    pwl = struct();
    pwl.vgrid        = vgrid;
    pwl.invgrid      = invgrid;
    pwl.n            = length(vgrid);
    pwl.Vmin         = Vmin;
    pwl.Vmax         = Vmax;
    pwl.n_requested  = n_vpack_bp;
end
