function [tf, first_break] = isPrefixBinary(s)
% ISPREFIXBINARY  True if a binary vector is a prefix pattern.
%   A prefix pattern has the form [1 ... 1 0 ... 0].
%
% Inputs
%   s            Column or row vector, numeric or logical.
%
% Outputs
%   tf           True if s is a prefix pattern.
%   first_break  First index j such that s(j) < s(j+1). NaN if tf is true.

    s = round(double(s(:)));
    d = diff(s);
    bad = find(d > 0, 1, 'first');
    tf = isempty(bad);
    if tf
        first_break = NaN;
    else
        first_break = bad;
    end
end
