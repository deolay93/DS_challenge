# Flexible model: gradient-boosted trees (XGBoost).
# Is there non-linear or interaction signal (e.g. symptom × line, or specific
# hours) that a single decision tree misses?

include(abspath("analysis/model/setup.jl"))
import XGBoost

#######################################################
# MODEL
#######################################################
mutable struct XGBModel
    params::NamedTuple
    booster::Any
end
XGBModel(params) = XGBModel(params, nothing)

function fit_model!(m::XGBModel, d)
    p = m.params
    dtrain = XGBoost.DMatrix(X(d), d.target; feature_names=feature_cols(d))
    m.booster = XGBoost.xgboost(dtrain;
        num_round=p.num_round, max_depth=p.max_depth, eta=p.eta,
        min_child_weight=p.min_child_weight, subsample=p.subsample,
        colsample_bytree=p.colsample_bytree, scale_pos_weight=p.scale_pos_weight,
        objective="binary:logistic", seed=42, verbosity=0,
        watchlist=Dict{String,XGBoost.DMatrix}())     # no per-round logging
    return m
end
predict_model(m::XGBModel, d) = XGBoost.predict(m.booster, X(d))

#######################################################
# DATA
#######################################################
data = get_data()
train_data, test_data = split_data(data)
folds = make_folds(train_data)

#######################################################
# CROSS-VALIDATION over the grid
#######################################################
# needed due to unbalanced target, so major incidents have more weights 
neg_pos_ratio = round(sum(train_data.target .== 0) / sum(train_data.target); digits=1)
grid = expand_grid((
    max_depth=[2, 3, 4, 6],
    eta=[0.03, 0.1],
    num_round=[100, 300],
    min_child_weight=[1, 10],
    subsample=[0.8],
    colsample_bytree=[0.8],
    scale_pos_weight=[1.0, neg_pos_ratio],
)) # could be looked into to have better coverage of the hyperparameter space
cv_metrics = DataFrame()
for (i, params) in enumerate(grid)
    m = XGBModel(params)
    for f in folds
        fit_model!(m, f.train)
        p = predict_model(m, f.valid)
        push!(cv_metrics, fold_row("xgboost", i, params, f, p))
    end
end
cv_table = summarise_cv(cv_metrics)
best = grid[cv_table.setting[1]] # select the best
save_result(cv_table, "xgboost_cv")
save_result(cv_metrics[cv_metrics.setting .== cv_table.setting[1], :], "xgboost_cv_folds")
first(cv_table, 10)

#######################################################
# TEST: refit on 2019–2024, score 2025 once
#######################################################
m = XGBModel(best)
fit_model!(m, train_data)
p_test = predict_model(m, test_data)
test_metrics = DataFrame([evaluate_df(test_data, p_test; model="xgboost")])
save_result(test_metrics, "xgboost_test")
save_predictions(test_data, p_test, "xgboost")
test_metrics