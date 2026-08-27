function tf = has_usable_solution(sol, mode)
% HAS_USABLE_SOLUTION  Check whether the optimizer returned a usable payload.
%
% Criteria
%   - The payload must be a non-empty cell array.
%   - It must contain the expected number of outputs for the active mode.
%   - Every required output must be non-empty, finite, and convertible to
%     numeric form via DOUBLE.

    tf = iscell(sol) && ~isempty(sol);
    if ~tf, return; end

    switch mode
        case "charge_balance"
            need = 2;
        case "charge_bulk"
            need = 1;
        case "discharge"
            need = 12;
        otherwise
            tf = false;
            return;
    end

    if numel(sol) < need
        tf = false;
        return;
    end

    for i = 1:need
        if isempty(sol{i})
            tf = false;
            return;
        end
        try
            xi = double(sol{i});
            if any(isnan(xi(:))) || any(isinf(xi(:)))
                tf = false;
                return;
            end
        catch
            tf = false;
            return;
        end
    end
end