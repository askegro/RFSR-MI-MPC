function [ci, bootMean] = bootstrap_mean_ci(x, B, ciLevel, seed)
%BOOTSTRAP_MEAN_CI Percentile bootstrap CI for the mean of independent data.
%
%   [ci, bootMean] = bootstrap_mean_ci(x, B, ciLevel, seed)
%
% Inputs
%   x       : vector of independent samples
%   B       : number of bootstrap resamples, e.g. 10000
%   ciLevel : confidence level in percent, e.g. 95
%   seed    : optional RNG seed
%
% Outputs
%   ci       : [lower upper] percentile confidence interval
%   bootMean : B-by-1 bootstrap sample means
%
% Use this for independent Monte Carlo realizations, not autocorrelated
% time-step data.

    if nargin < 2 || isempty(B)
        B = 10000;
    end
    if nargin < 3 || isempty(ciLevel)
        ciLevel = 95;
    end
    if nargin >= 4 && ~isempty(seed)
        rng(seed, 'twister');
    end

    x = x(:);
    x = x(isfinite(x));
    n = numel(x);

    if n == 0
        ci = [NaN NaN];
        bootMean = NaN(B,1);
        return;
    end

    idx = randi(n, n, B);
    bootSamples = x(idx);
    bootMean = mean(bootSamples, 1, 'omitnan')';

    alpha = (100 - ciLevel) / 2;
    ci = prctile(bootMean, [alpha, 100-alpha]);
end