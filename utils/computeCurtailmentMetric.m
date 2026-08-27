% metrics/computeCurtailmentMetric.m
function Curt = computeCurtailmentMetric(L, active_mask)

    C = metricsConfig();

    curtailed = L.slack_mag > C.CURTAILMENT_THRESHOLD_A;

    Curt = mean(curtailed(active_mask));

end