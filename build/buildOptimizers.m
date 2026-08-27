function opt = buildOptimizers(constants)
    
    fprintf('\n========================================\n');
    fprintf('  Building Optimizers\n');
    fprintf('========================================\n');
    
    opt = struct();
    buildStartTime = tic;    

    fprintf('  - Building optDischargeHighSOC...\n');
    opt.disHigh = buildDischargeOptimizer(constants);     
    
    fprintf('  - Building optDischargeLowSOC...\n');
    opt.disLow = buildDischargeOptimizer(constants); 
    
    fprintf('  - Building optChargeBulk...\n');
    opt.chgBulk = buildChargeBulkOptimizer(constants);
    
    fprintf('  - Building optChargeBalance...\n');
    opt.chgBal = buildChargeBalanceOptimizer(constants);
    
    fprintf('  Optimizers built in %.2f s\n', toc(buildStartTime));
    fprintf('========================================\n');

end
