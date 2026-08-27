function x_phys = unsort_vec(x_sorted, idx, Ns)
% UNSORT_VEC  Map a sorted cell vector back to physical cell order.
%
% Definition
%   x_phys(idx) = x_sorted
%
% Inputs
%   x_sorted  Ns x 1 vector in sorted cell order
%   idx       permutation mapping physical -> sorted order
%   Ns        number of series cells

    x_phys      = zeros(Ns, 1);
    x_phys(idx) = x_sorted;
end