module TestUtils

using Test, CSV, DataFrames
using Statistics: mean

include(joinpath(@__DIR__, "..", "analysis", "exploration", "utils.jl"))

@testset "exploration/utils.jl" begin

    @testset "band_range" begin
        @test band_range("02 min et moins") == (0.0, 2.0)
        @test band_range("03 à 04 min") == (3.0, 4.0)
        @test band_range("20 à 24 min") == (20.0, 24.0)
        @test band_range("30 min et plus") == (30.0, Inf)

        # The 8 official bands should tile 0 → ∞ with no gaps or overlaps
        labels = ["02 min et moins", "03 à 04 min", "05 à 09 min", "10 à 14 min",
                  "15 à 19 min", "20 à 24 min", "25 à 29 min", "30 min et plus"]
        ranges = band_range.(labels)
        @test first(ranges[1]) == 0.0
        @test last(ranges[end]) == Inf
        @test all(first(ranges[i + 1]) == last(ranges[i]) + 1 for i in 1:length(ranges) - 1)
    end

    @testset "clock_format" begin
        @test clock_format("02:56") == "HH:MM, before 24:00"
        @test clock_format("24:04") == "HH:MM, 24:00 or later"
        @test clock_format("25:26:00") == "HH:MM:SS, 24:00 or later"
        @test clock_format("7:05") == "HH:MM, before 24:00"
        @test clock_format("not a time") == "other"
        @test clock_format("12:5") == "other"
    end

    @testset "service_minutes" begin
        @test service_minutes("00:00") == 0.0
        @test service_minutes("02:56") == 176.0
        @test service_minutes("25:26:00") == 25 * 60 + 26       # service clock past midnight
        @test service_minutes("00:00:30") == 0.5                 # seconds become fractions
        # resume − start across midnight stays positive on the service clock
        @test service_minutes("24:10:00") - service_minutes("23:55") == 15.0
    end

    @testset "line_flags (ligne_1, ligne_2, ligne_4, ligne_5)" begin
        @test line_flags("Ligne verte") == (true, false, false, false)
        @test line_flags("Ligne orange") == (false, true, false, false)
        @test line_flags("Ligne jaune") == (false, false, true, false)
        @test line_flags("Ligne bleue") == (false, false, false, true)
        @test line_flags("Ligne 1, 2, 4, 5") == (true, true, true, true)
        @test line_flags("Ligne 2, 5") == (false, true, false, true)
        @test line_flags("LIGNE ORANGE") == (false, true, false, false)   # case-insensitive
        @test line_flags("Ligne 12") == (false, false, false, false)      # digits must stand alone
    end

    @testset "clean_names!" begin
        df = DataFrame("Évacuation" => [1], "Heure de l'incident" => [1],
                       "Année civile/mois" => [1], "KFS" => [1], "Type de matériel" => [1])
        clean_names!(df)
        @test names(df) == ["evacuation", "heure_de_lincident", "annee_civile_mois",
                            "kfs", "type_de_materiel"]
    end

    @testset "major_rate" begin
        df = DataFrame(g=["b", "a", "b", "a", "b"], target=[1, 1, 0, 0, 0])
        t = major_rate(df, :g)
        @test t.g == ["a", "b"]                    # sorted by the grouping column
        @test t.n == [2, 3]
        @test t.major == [1, 1]
        @test t.major_rate == [0.5, 0.3333]        # rounded to 4 digits
        # the overall rate used for the dashed line in plot_major_rate
        @test sum(t.major) / sum(t.n) == mean(df.target)
    end
end

end # module
