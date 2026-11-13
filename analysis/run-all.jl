# Run the whole analysis, in order. From the repo root:
#   julia --project=. analysis/run-all.jl
#
# Each script runs in its own fresh module, so names defined by one script
# (data, grid, best, m, …) can't leak into the next one.

const SCRIPTS = [
    "analysis/exploration/incidents-feature.jl",   # target + features → data/df.csv, analysis/csv/, analysis/plots/
    "analysis/model/baseline.jl",                  # each model → analysis/results/
    "analysis/model/decision-tree.jl",
    "analysis/model/xgboost-model.jl",
    "analysis/model/compare.jl",                   # side-by-side tables
]

function run_script(path)
    @info "Running $path"
    mod = Module(Symbol(splitext(basename(path))[1]))
    Core.eval(mod, :(include(p) = Base.include($mod, p)))   # lets the script use `include`
    t = @elapsed Base.include(mod, abspath(path))
    @info "Done $path" seconds = round(t; digits=1)
end

foreach(run_script, SCRIPTS)
@info "All done: see data/df.csv, analysis/csv/, analysis/plots/ and analysis/results/"
