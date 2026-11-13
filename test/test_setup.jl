module TestSetup

using Test, CSV, DataFrames, Dates

include(joinpath(@__DIR__, "..", "analysis", "model", "setup.jl"))

# One incident on 1 June and one on 31 December of each year 2019–2025
toy() = DataFrame(
    date=[d for y in 2019:2025 for d in (Date(y, 6, 1), Date(y, 12, 31))],
    hour=1:14,
    x=collect(14:-1:1),
    delay_min=fill(3.0, 14),
    severe=zeros(Int, 14),
    target=repeat([1, 0], 7),
)

@testset "model/setup.jl" begin

    @testset "feature_cols / X: outcome columns never become features" begin
        d = toy()
        @test feature_cols(d) == ["hour", "x"]
        @test isempty(intersect(feature_cols(d), ["date", "target", "delay_min", "severe"]))
        @test X(d) isa Matrix{Float64}
        @test size(X(d)) == (14, 2)
    end

    @testset "split_data: 2025 is held out" begin
        train, test = split_data(toy())
        @test nrow(train) + nrow(test) == 14
        @test maximum(train.date) < Date(2025, 1, 1) <= minimum(test.date)
        @test Set(year.(test.date)) == Set([2025])
        @test maximum(train.date) == Date(2024, 12, 31)
    end

    @testset "make_folds: expanding window, never validates on the past" begin
        train, _ = split_data(toy())
        folds = make_folds(train)
        @test [f.year for f in folds] == [2021, 2022, 2023, 2024]
        for f in folds
            @test all(year.(f.valid.date) .== f.year)
            @test maximum(f.train.date) < minimum(f.valid.date)
            @test minimum(year.(f.train.date)) == 2019
        end
        @test nrow(folds[1].train) == 4      # 2019–2020
        @test nrow(folds[end].train) == 10   # 2019–2023
    end

    @testset "expand_grid" begin
        g = expand_grid((depth=[2, 3], leaf=[20]))
        @test g == [(depth=2, leaf=20), (depth=3, leaf=20)]
        g = expand_grid((a=[1, 2], b=[10, 20], c=[0.5]))
        @test length(g) == 4
        @test issetequal(g, [(a=1, b=10, c=0.5), (a=2, b=10, c=0.5),
                             (a=1, b=20, c=0.5), (a=2, b=20, c=0.5)])
    end

    @testset "n_months" begin
        @test n_months(DataFrame(date=[Date(2025, 1, 1), Date(2025, 1, 31), Date(2025, 2, 1)])) == 2
        @test n_months(DataFrame(date=[Date(2024, 1, 5), Date(2025, 1, 5)])) == 2   # same month, different years
        @test n_months(DataFrame(date=[Date(2025, m, 1) for m in 1:9])) == 9         # the 2025 test set
    end

    @testset "summarise_cv: mean PR-AUC, worst fold, best setting first" begin
        cv = DataFrame(model="m", setting=[1, 1, 2, 2], params=["a", "a", "b", "b"],
                       valid_year=[2021, 2022, 2021, 2022], pr_auc=[0.1, 0.3, 0.4, 0.4])
        s = summarise_cv(cv)
        @test s.setting == [2, 1]
        @test s.cv_pr_auc == [0.4, 0.2]
        @test s.worst_fold == [0.4, 0.1]
        @test s.pr_auc_2021 == [0.4, 0.1]
        @test s.pr_auc_2022 == [0.4, 0.3]
    end
end

end # module
