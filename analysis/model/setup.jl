using CSV, DataFrames, Dates
using Statistics: mean

include("metrics.jl")

# Columns that describe the outcome: used to evaluate, never as features
const EVAL_COLS = ["delay_min", "severe"]

#######################################################
# DATA
#######################################################
get_data() = CSV.read(joinpath("data", "df.csv"), DataFrame)

feature_cols(d) = setdiff(names(d), ["date", "target", EVAL_COLS...])
X(d) = Matrix{Float64}(d[:, feature_cols(d)])

"""
    split_data(data; test_start=2025-01-01) -> (train_data, test_data)

By time: the model will score future incidents, so it is tested on incidents
after everything it was trained on (a random split would learn from the future).
train_data = 2019–2024 (model choice and final fit); test_data = 2025, scored once.
"""
function split_data(data; test_start=Date(2025, 1, 1))
    train_data = data[data.date .< test_start, :]
    test_data = data[data.date .>= test_start, :]
    @info "split" n_train=nrow(train_data) majors_train=sum(train_data.target) n_test=nrow(test_data) majors_test=sum(test_data.target)
    return train_data, test_data
end

"""
    make_folds(train_data; years=2021:2024) -> Vector

Expanding window by year: each fold trains on all years before Y and validates
on year Y (2019–2020 → 2021, …, 2019–2023 → 2024).
"""
function make_folds(train_data; years=2021:2024)
    y = year.(train_data.date)
    return [(year=Y, train=train_data[y .< Y, :], valid=train_data[y .== Y, :]) for Y in years]
end

"""All combinations of a grid, e.g. (depth=[2, 3], leaf=[20]) → [(depth=2, leaf=20), (depth=3, leaf=20)]."""
expand_grid(grid::NamedTuple) = vec([NamedTuple{keys(grid)}(v) for v in Iterators.product(values(grid)...)])

#######################################################
# EVALUATION
#######################################################
"""Number of calendar months covered by `d` (for alerts per month)."""
n_months(d) = length(unique(yearmonth.(d.date)))

"""All metrics for scores `p` on the rows of `d`, including the stakeholder metrics."""
evaluate_df(d, p; model="model") =
    evaluate(d.target, p; model=model, delay=d.delay_min, severe=d.severe, months=n_months(d))

"""One row of the CV table: setting, fold, and every metric on the validation year."""
function fold_row(model, setting_id, params, f, p)
    m = evaluate_df(f.valid, p; model=model)
    return merge((; model=model, setting=setting_id, params=string(params), valid_year=f.year,
                    train_years="2019–$(f.year - 1)", n_train=nrow(f.train)),
                 Base.structdiff(m, NamedTuple{(:model,)}))
end

"""
    summarise_cv(cv_metrics) -> DataFrame

One row per setting: mean PR-AUC over the folds, worst fold, PR-AUC per year.
Sorted best first.
"""
function summarise_cv(cv_metrics)
    s = combine(groupby(cv_metrics, [:model, :setting, :params]),
        :pr_auc => (x -> round(mean(x); digits=3)) => :cv_pr_auc,
        :pr_auc => minimum => :worst_fold)
    per_year = unstack(cv_metrics, [:model, :setting, :params], :valid_year, :pr_auc; renamecols=y -> "pr_auc_$y")
    s = innerjoin(s, per_year; on=[:model, :setting, :params])
    return sort!(s, :cv_pr_auc; rev=true)
end

"""Save the test-set scores, to inspect which incidents each model flags."""
save_predictions(d, p, name) =
    save_result(DataFrame(date=d.date, target=d.target, delay_min=d.delay_min, severe=d.severe, score=p),
                name * "_test_predictions")

save_result(df, name) = (mkpath(joinpath("analysis", "results")); CSV.write(joinpath("analysis", "results", name * ".csv"), df))
read_result(name) = CSV.read(joinpath("analysis", "results", name * ".csv"), DataFrame)
