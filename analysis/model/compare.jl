# Side-by-side comparison. Run baseline.jl, decision-tree.jl and
# xgboost-model.jl first.

include(abspath("analysis/model/setup.jl"))

model_names = ("baseline", "decision_tree", "xgboost")

#######################################################
# CROSS-VALIDATION (2021–2024): each model's best setting
#######################################################
cv_cols = [:model, :params, :cv_pr_auc, :worst_fold, :pr_auc_2021, :pr_auc_2022, :pr_auc_2023, :pr_auc_2024]
cv = vcat([select(first(read_result(m * "_cv"), 1), cv_cols) for m in model_names]...)
save_result(cv, "model_comparison_cv")

# Every fold of every model's best setting, one row per (model, year)
all_cv_folds = vcat([read_result(m * "_cv_folds") for m in model_names]...)
save_result(all_cv_folds, "model_comparison_cv_folds")

#######################################################
# TEST (2025, scored once per model)
#######################################################
test = vcat([read_result(m * "_test") for m in model_names]...)
save_result(test, "model_comparison_test")
cv
test
