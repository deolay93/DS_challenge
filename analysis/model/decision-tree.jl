# Interpretable model: a single shallow decision tree.
# Can a handful of if/then rules, readable by the control room, rank incidents
# nearly as well as an ensemble? Uses the features as they are (hour as a number).

include(abspath("analysis/model/setup.jl"))
import DecisionTree

#######################################################
# MODEL
#######################################################
mutable struct TreeModel
    params::NamedTuple
    tree::Any
end
TreeModel(params) = TreeModel(params, nothing)

function fit_model!(m::TreeModel, d)
    m.tree = DecisionTree.DecisionTreeClassifier(max_depth=m.params.max_depth,
                                                 min_samples_leaf=m.params.min_samples_leaf, rng=42)
    DecisionTree.fit!(m.tree, X(d), d.target)
    return m
end
predict_model(m::TreeModel, d) =
    DecisionTree.predict_proba(m.tree, X(d))[:, findfirst(==(1), DecisionTree.get_classes(m.tree))]

#######################################################
# DATA
#######################################################
data = get_data()
train_data, test_data = split_data(data)
folds = make_folds(train_data)

#######################################################
# CROSS-VALIDATION over the grid
#######################################################
# Shallow trees stay readable; a minimum leaf size stops rules built on a
# handful of incidents.
grid = expand_grid((max_depth=[2, 3, 4, 5], min_samples_leaf=[20, 50, 100, 200]))
cv_metrics = DataFrame()
for (i, params) in enumerate(grid)
    m = TreeModel(params)
    for f in folds
        fit_model!(m, f.train)
        p = predict_model(m, f.valid)
        push!(cv_metrics, fold_row("decision_tree", i, params, f, p))
    end
end
cv_table = summarise_cv(cv_metrics) 
best = grid[cv_table.setting[1]] # select the best
save_result(cv_table, "decision_tree_cv")
save_result(cv_metrics[cv_metrics.setting .== cv_table.setting[1], :], "decision_tree_cv_folds")
first(cv_table, 10)

#######################################################
# TEST: refit on 2019–2024, score 2025 once
#######################################################
m = TreeModel(best)
fit_model!(m, train_data)
p_test = predict_model(m, test_data)
test_metrics = DataFrame([evaluate_df(test_data, p_test; model="decision_tree")])
save_result(test_metrics, "decision_tree_test")
save_predictions(test_data, p_test, "decision_tree")
test_metrics
