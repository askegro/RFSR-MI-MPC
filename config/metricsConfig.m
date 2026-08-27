% config/metricsConfig.m
function C = metricsConfig()

    C.CURTAILMENT_THRESHOLD_A = 0.01; % manuscript eps_lambda, Section V-B, eq:curtRate

    % Bootstrap reporting parameters used only in post-processing.
    % These do not affect simulations or controller behavior.
    C.BOOTSTRAP_REPS = 10000;
    C.BOOTSTRAP_CI_LEVEL = 95;

    % For time-series paired comparisons, use block bootstrap rather than
    % ordinary i.i.d. bootstrap because WLTC steps are temporally correlated.
    C.BLOCK_BOOTSTRAP_LEN = 25;    

end