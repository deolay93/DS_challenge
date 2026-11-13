module TestMetrics

using Test
using Statistics: mean

include(joinpath(@__DIR__, "..", "analysis", "model", "metrics.jl"))

@testset "model/metrics.jl" begin

    # 10 incidents, 2 majors, scored from highest (1) to lowest (10)
    y = [1, 0, 1, 0, 0, 0, 0, 0, 0, 0]
    p = collect(10.0:-1.0:1.0)

    @testset "average_precision (PR-AUC)" begin
        @test average_precision([1, 1, 0, 0], [0.9, 0.8, 0.2, 0.1]) ≈ 1.0       # perfect ranking
        @test average_precision([1, 0, 1, 0], [0.9, 0.8, 0.7, 0.1]) ≈ 5 / 6     # 1/2·1 + 1/2·2/3
        @test average_precision([0, 0, 1, 1], [0.9, 0.8, 0.2, 0.1]) ≈ 5 / 12    # 1/2·1/3 + 1/2·2/4
        @test ismissing(average_precision([0, 0, 0], [0.3, 0.2, 0.1]))          # no positives
        # tied scores are one threshold: precision is taken over the whole tie
        @test average_precision([1, 0], [0.5, 0.5]) ≈ 0.5
        @test average_precision([0, 1], [0.5, 0.5]) ≈ 0.5
        # a constant score equals the share of positives
        @test average_precision(y, fill(0.3, length(y))) ≈ mean(y)
        # order of rows doesn't matter, only the scores
        perm = [3, 1, 10, 2, 5, 4, 7, 6, 9, 8]
        @test average_precision(y[perm], p[perm]) ≈ average_precision(y, p)
    end

    @testset "top_k" begin
        @test sort(top_k(p, 0.2)) == [1, 2]           # top 20% of 10 = 2 incidents
        @test top_k(p, 0.01) == [1]                   # at least one incident is flagged
        @test length(top_k(collect(1.0:1000.0), 0.01)) == 10
        @test length(top_k(collect(1.0:150.0), 0.01)) == 2   # ceil(1.5)
    end

    @testset "at_budget" begin
        b = at_budget(y, p, 0.2)                      # flags incidents 1, 2 → one major
        @test b.recall ≈ 0.5
        @test b.precision ≈ 0.5
        b = at_budget(y, p, 0.25)                     # ceil(2.5) = 3 flags: 1, 2, 3 → both majors
        @test b.recall ≈ 1.0
        @test b.precision ≈ 2 / 3
        b = at_budget(zeros(Int, 10), p, 0.2)         # no majors: no division by zero
        @test b.recall == 0.0
    end

    @testset "stakeholder_metrics" begin
        delay = [30.0, 5.0, 50.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        severe = [1, 0, 1, 0, 0, 0, 0, 0, 0, 0]
        s = stakeholder_metrics(y, p, 0.2; delay, severe, months=2)
        @test s.lift ≈ 0.5 / 0.2                      # flag hit rate ÷ share of majors
        @test s.alerts_per_month ≈ 1.0                # 2 flags over 2 months
        @test s.delay_captured ≈ 30 / 80              # only major delay counts (5 min non-major ignored)
        @test s.severe_recall ≈ 0.5
    end

    @testset "evaluate" begin
        row = evaluate(y, p; model="m")
        @test row.model == "m"
        @test row.n == 10
        @test row.majors == 2
        @test row.prevalence == 0.2
        @test row.pr_auc == 0.833                     # 5/6, rounded to 3 digits
        @test row.recall_top10 == 0.5
        @test !haskey(row, :lift_top1)                # no stakeholder metrics without delay

        delay = [30.0, 5.0, 50.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        full = evaluate(y, p; model="m", delay=delay, severe=y, months=1)
        @test haskey(full, :lift_top1) && haskey(full, :severe_recall_top5)
        @test full.lift_top1 == 5.0                   # top 1 of 10 is a major: 1.0 / 0.2
        @test full.alerts_per_month_top1 == 1.0
        @test full.delay_captured_top1 == 0.375
    end
end

end # module
