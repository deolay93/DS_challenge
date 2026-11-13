# Baseline: score each incident by the share of majors for its symptom.
# The simplest rule the control room could already apply ("fire/smoke incidents
# tend to run long"). A model is only worth using if it beats this.

include(abspath("analysis/model/setup.jl"))

#######################################################
# MODEL
#######################################################
mutable struct SymptomRule
    rate::Dict{String,Float64}      # share of majors per symptom
    overall::Float64                # fallback for a symptom unseen in training
end
SymptomRule(params=(;)) = SymptomRule(Dict{String,Float64}(), 0.0)

symptom_of(d) = [join(r) for r in eachrow(Matrix(d[:, filter(startswith("sym_"), names(d))]))]

function fit_model!(m::SymptomRule, d)
    keys_d = symptom_of(d)
    m.rate = Dict(k => mean(d.target[keys_d .== k]) for k in unique(keys_d))
    m.overall = mean(d.target)
    return m
end
predict_model(m::SymptomRule, d) = [get(m.rate, k, m.overall) for k in symptom_of(d)]

#######################################################
# DATA
#######################################################
data = get_data()
train_data, test_data = split_data(data)
folds = make_folds(train_data)

#######################################################
# CROSS-VALIDATION (no hyperparameters: a single setting)
#######################################################
grid = [(;)]
cv_metrics = DataFrame()
for (i, params) in enumerate(grid)
    m = SymptomRule(params)
    for f in folds
        fit_model!(m, f.train)
        p = predict_model(m, f.valid)
        push!(cv_metrics, fold_row("symptom_only", i, params, f, p))
    end
end
cv_table = summarise_cv(cv_metrics)
best = grid[cv_table.setting[1]] # select the best
save_result(cv_table, "baseline_cv")
save_result(cv_metrics[cv_metrics.setting .== cv_table.setting[1], :], "baseline_cv_folds")
cv_table

#######################################################
# TEST: refit on 2019–2024, score 2025 once
#######################################################
m = SymptomRule(best)
fit_model!(m, train_data)
p_test = predict_model(m, test_data)
test_metrics = DataFrame([evaluate_df(test_data, p_test; model="symptom_only")])
save_result(test_metrics, "baseline_test")
save_predictions(test_data, p_test, "baseline")
test_metrics
