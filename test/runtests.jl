using Test

@testset "DS_challenge helpers" begin
    include(joinpath(@__DIR__, "test_utils.jl"))     # analysis/exploration/utils.jl
    include(joinpath(@__DIR__, "test_metrics.jl"))   # analysis/model/metrics.jl
    include(joinpath(@__DIR__, "test_setup.jl"))     # analysis/model/setup.jl
end
