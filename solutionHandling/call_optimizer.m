function [sol, diagnostics, u] = call_optimizer(active_optimizer, optimizer_params, u)
% CALL_OPTIMIZER  Execute the selected optimizer and measure wall time.

    t_solve = tic;
    [sol, ~, ~, ~, ~, diagnostics] = active_optimizer(optimizer_params{:});
    u.solve_wall = toc(t_solve);
end