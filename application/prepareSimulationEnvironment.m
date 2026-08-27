function env = prepareSimulationEnvironment(opts)
% PREPARESIMULATIONENVIRONMENT Centralise RNG and solver-session reset.
%
% Keeps reproducibility and YALMIP cleanup out of experiment scripts.

    if nargin < 1 || isempty(opts)
        opts = struct();
    end
    opts = withDefault(opts, 'seed', 1337);
    opts = withDefault(opts, 'sort_seed', 42);
    opts = withDefault(opts, 'soc_seed', 4242);
    opts = withDefault(opts, 'clear_yalmip', true);
    opts = withDefault(opts, 'print_banner', true);

    if opts.clear_yalmip && exist('yalmip','file') == 2
        yalmip('clear');
    end

    rng(opts.seed, 'twister');
    env = struct();
    env.sSOH = RandStream('Threefry', 'Seed', opts.sort_seed);
    env.sSOC = RandStream('Threefry', 'Seed', opts.soc_seed);
    env.rngStateInit = rng;

    if opts.print_banner
        fprintf('\n========================================\n');
        fprintf('  RBS Simulation (Series String)\n');
        fprintf('========================================\n');
        fprintf('  RNG: Type=%s, Seed=%d\n', env.rngStateInit.Type, env.rngStateInit.Seed);
        fprintf('========================================\n');
    end
end

function s = withDefault(s, fieldName, value)
    if ~isfield(s, fieldName) || isempty(s.(fieldName))
        s.(fieldName) = value;
    end
end
