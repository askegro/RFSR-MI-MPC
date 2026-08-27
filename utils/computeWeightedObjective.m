function [J_obj, J_SOH_w, J_SOC_w, J_curt_w] = computeWeightedObjective(J_SOH, J_SOC, J_curt, cfg)
% COMPUTEWEIGHTEDOBJECTIVE Convert unweighted normalized components into
% weighted objective contributions.
%
% Inputs:
%   J_SOH, J_SOC, J_curt are the unweighted normalized components returned
%   by the optimizer.
%
% Output:
%   J_obj is the actual scalar MPC objective contribution:
%       w.SOH*J_SOH + w.SOC*J_SOC + w.lambda*J_curt

    J_SOH_w  = cfg.w.SOH    .* J_SOH;
    J_SOC_w  = cfg.w.SOC    .* J_SOC;
    J_curt_w = cfg.w.lambda .* J_curt;

    J_obj = J_SOH_w + J_SOC_w + J_curt_w;
end