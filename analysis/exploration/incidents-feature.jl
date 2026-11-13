using CSV, DataFrames, Dates
using CairoMakie
using Statistics: mean, median

include(abspath("analysis/exploration/utils.jl"))

raw_dir = joinpath("data", "raw")
inc = CSV.read(raw_file("Incidents"), DataFrame)
clean_names!(inc)
select!(inc, col_keep)

# text columns come in as DataString; plain String is easier to work with
for c in names(inc)
    eltype(inc[!, c]) <: AbstractString && (inc[!, c] = String.(inc[!, c]))
end

#######################################################
# TARGET
#######################################################
combine(groupby(inc, :incident_en_minutes), nrow => :n)
"""
 Row │ incident_en_minutes  n     
     │ String               Int64 
─────┼────────────────────────────
   1 │ 02 min et moins      32844
   2 │ 03 à 04 min           6304
   3 │ 10 à 14 min            933
   4 │ 05 à 09 min           4377
   5 │ 25 à 29 min            107
   6 │ 15 à 19 min            299
   7 │ 30 min et plus         524
   8 │ 20 à 24 min            173
""";

# The labels are text, so sort them by the minutes they stand for:
# "X et moins" = 0..X, "X à Y" = X..Y, "X et plus" = X and above
bands = combine(groupby(inc, :incident_en_minutes), nrow => :n)
rename!(bands, :incident_en_minutes => :band)
bands.min_minutes = first.(band_range.(bands.band))
bands.max_minutes = last.(band_range.(bands.band))
sort!(bands, :min_minutes)
band_order = bands.band
save_csv(bands, "delay_bands")

# Rebuild the duration from the times
# We notice that for some of the heure its shown as HH:MM, some as HH:MM:SS, and some are after 24:00
combine(groupby(DataFrame(format=clock_format.(inc.heure_de_lincident)), :format), nrow => :n)
combine(groupby(DataFrame(format=clock_format.(inc.heure_de_reprise)), :format), nrow => :n)
"""
 Row │ format                    n     
     │ String                    Int64 
─────┼─────────────────────────────────
   1 │ HH:MM, before 24:00       43245
   2 │ HH:MM:SS, 24:00 or later   2316

 Row │ format                    n     
     │ String                    Int64 
─────┼─────────────────────────────────
   1 │ HH:MM, before 24:00       42293
   2 │ HH:MM:SS, 24:00 or later   3268

The dataset is displaying different time formats for the incident times, anything after 24:00 would be displayed 
    as HH:MM:SS with the hour part greater than 24.
""";

# Times after midnight are written on a service clock (e.g. 25:26:00).
# Therefore, we have to transform them into a consistent measure of minutes since the start of the service day.
inc.start_min = service_minutes.(inc.heure_de_lincident)
inc.resume_min = service_minutes.(inc.heure_de_reprise)
inc.delay_min = inc.resume_min .- inc.start_min
extrema(inc.delay_min)
"""
(0.0, 1605.0)

We seem to have extreme values, with delays exceeding the typical range of incident duration.
""";

# --- 3. Do the rebuilt minutes fall inside the band? -
lo = Dict(zip(bands.band, bands.min_minutes))
hi = Dict(zip(bands.band, bands.max_minutes))
inc.in_band = [lo[b] <= m <= hi[b] for (b, m) in zip(inc.incident_en_minutes, inc.delay_min)]

check = combine(groupby(inc, [:type_dincident, :incident_en_minutes]),
    nrow => :n,
    :in_band => (x -> round(mean(x); digits=3)) => :share_in_band,
    :delay_min => median => :median_minutes)
check.order = indexin(check.incident_en_minutes, band_order)
sort!(check, [:type_dincident, :order]); select!(check, Not(:order))
check
save_csv(check, "minutes_vs_band")
"""
 Row │ type_dincident  incident_en_minutes  n      share_in_band  median_minutes 
     │ String          String               Int64  Float64        Float64        
─────┼───────────────────────────────────────────────────────────────────────────
   1 │ S               02 min et moins      16394          0.045            41.0
   2 │ T               02 min et moins      16450          0.989             0.0
   3 │ T               03 à 04 min           6304          0.975             3.0
   4 │ T               05 à 09 min           4377          0.953             6.0
   5 │ T               10 à 14 min            933          0.935            11.0
   6 │ T               15 à 19 min            299          0.946            17.0
   7 │ T               20 à 24 min            173          0.925            22.0
   8 │ T               25 à 29 min            107          0.935            27.0
   9 │ T               30 min et plus         524          0.998            49.0

All station incidents (type_dincident = "S") fall outside their band: 4.5% match,
vs 93–99% for train incidents. 

This is expected: per the column definitions, station start/resume times measure the incident itself, while train 
start/resume times measure the customer delay.

All 16,394 station incidents are in the lowest band ("02 min et moins"), so none can
be a major incident. We therefore define the target on train incidents only and
remove station incidents from the modelling data.
""";

# --- 3b. Out-of-band minutes --------------------------
# 646 train incidents (2.2%) have rebuilt minutes outside their official band, up to
# ~1,200 minutes in the "02 min et moins" band: recording errors in the times.
# The label comes from the band, so these incidents are kept, but their minutes are
# clamped to the band so they can't distort delay totals (delay share, delay captured).
inc.delay_min = clamp.(inc.delay_min,
    [lo[b] for b in inc.incident_en_minutes], [hi[b] for b in inc.incident_en_minutes])

# --- 4. Define the target -----------------------------
# Major interruption = official customer-delay band of 20 minutes or more
# (Abolfazli 2024: primary delays > 20 min fall mostly in the high-severity cluster).
major_min = 20
inc.band_min = [lo[b] for b in inc.incident_en_minutes]

# No station incident reaches 20 minutes (step 3), so keep train incidents only
tr = filter(:type_dincident => ==("T"), inc)
tr.target = Int.(tr.band_min .>= major_min)
tr.severe = Int.(tr.band_min .>= 30)      # "30 min et plus": the severe tail (evaluation only)
nrow(tr), nrow(inc), sum(tr.target), round(mean(tr.target); digits=4)
"""
julia> nrow(tr), nrow(inc), sum(tr.target), round(mean(tr.target); digits=4)
(29167, 45561, 804, 0.0276)

29,167 train incidents here; 29,166 after the "02-avr" row is removed (line section, below).
""";

# How much of the total customer delay comes from major incidents?
delay_share = combine(groupby(tr, :target),
    nrow => :incidents,
    :delay_min => sum => :delay_minutes,
    :delay_min => median => :median_minutes)
delay_share.share_of_incidents = round.(delay_share.incidents ./ sum(delay_share.incidents); digits=3)
delay_share.share_of_delay = round.(delay_share.delay_minutes ./ sum(delay_share.delay_minutes); digits=3)
save_csv(delay_share, "delay_share_by_major")
delay_share
"""
 Row │ target  incidents  delay_minutes  median_minutes  share_of_incidents  share_of_delay 
     │ Int64   Int64      Float64        Float64         Float64             Float64        
─────┼──────────────────────────────────────────────────────────────────────────────────────
   1 │      0      28363        74248.0             2.0               0.972            0.64
   2 │      1        804        41804.0            37.0               0.028            0.36

2.8% of the incidents are major incidents, but they take 36% of the total customer delay
(minutes clamped to their band, step 3b; with the raw minutes it would read 30.5%).
"""

#######################################################
# FEATURES
#######################################################
# For each column: look at its values, look at the share of major incidents
# per value, then decide how to encode it.

# --- time of day --------------------------------------
tr.hour = floor.(Int, tr.start_min ./ 60)     # 24, 25 = after midnight (service clock)
by_hour = major_rate(tr, :hour)
plot_major_rate(by_hour, :hour, "Major rate by hour of the service day", "major_rate_by_hour")

"""
Some hours are higher than the average major incident rate, indicating that the time of day could be an important feature.
""";

# --- day of week --------------------------------------
major_rate(tr, :jour_de_la_semaine)
by_jour = major_rate(tr, :jour_de_la_semaine)
plot_major_rate(by_jour, :jour_de_la_semaine, "Major rate by day of week", "major_rate_by_day_of_week")

"""
 Row │ jour_de_la_semaine  n      major  major_rate 
     │ Int64               Int64  Int64  Float64    
─────┼──────────────────────────────────────────────
   1 │                  1   4294    116      0.027
   2 │                  2   4591    101      0.022
   3 │                  3   4334    130      0.03
   4 │                  4   4443    136      0.0306
   5 │                  5   4708    133      0.0282
   6 │                  6   3525     87      0.0247
   7 │                  7   3272    101      0.0309

We also notice some minor difference, it could be used as a feature, but we could drop it later if it doesn't improve the model.
""";

tr.weekend = Int.(in.(tr.jour_de_la_semaine, Ref((6, 7))))
major_rate(tr, :weekend)
"""
 Row │ weekend  n      major  major_rate 
     │ Int64    Int64  Int64  Float64    
─────┼───────────────────────────────────
   1 │       0  22370    616      0.0275
   2 │       1   6797    188      0.0277

Not much difference between weekend and weekday incidents. So no need to include it as a feature.
""";

# --- month --------------------------------------------
by_month = major_rate(tr, :mois_calendrier)
save_csv(by_month, "major_rate_by_month")
plot_major_rate(by_month, :mois_calendrier, "Major rate by month", "major_rate_by_month")
"""
12×4 DataFrame
 Row │ mois_calendrier  n      major  major_rate 
     │ Int64            Int64  Int64  Float64    
─────┼───────────────────────────────────────────
   1 │               1   2985     76      0.0255
   2 │               2   2759     65      0.0236
   3 │               3   2907     84      0.0289
   4 │               4   2355     82      0.0348
   5 │               5   2266     57      0.0252
   6 │               6   2351     79      0.0336
   7 │               7   2319     59      0.0254
   8 │               8   2369     53      0.0224
   9 │               9   2389     57      0.0239
  10 │              10   2105     58      0.0276
  11 │              11   2128     63      0.0296
  12 │              12   2234     71      0.0318

Keep month as the feature, since we notice in March, April, June, Nov, and Dec they are higher 
than the other months.
""";

# --- day of month -------------------------------------
by_day = major_rate(tr, :jour_du_mois)
plot_major_rate(by_day, :jour_du_mois, "Major rate by day of month", "major_rate_by_day_of_month")
"""
Some day of the month are higher than the other.

Keep day of month as a feature.
""";

# --- line ---------------------------------------------
combine(groupby(tr, :ligne), nrow => :n)
"""
There are multiple line or only one line incidents.
"""
# Line names or numbers, alone or combined ("Ligne 1, 2, 4").
# One value, "02-avr", is an Excel date artefact: the original line(s) can't be
# recovered with certainty, so the incident is removed rather than guessed.
filter!(:ligne => !=("02-avr"), tr)
lf = line_flags.(tr.ligne)
for (i, c) in enumerate(("ligne_1", "ligne_2", "ligne_4", "ligne_5"))
    tr[!, c] = Int.(getindex.(lf, i))
end
tr.multi_line = Int.((tr.ligne_1 .+ tr.ligne_2 .+ tr.ligne_4 .+ tr.ligne_5) .> 1)

by_line = vcat([major_rate(tr[tr[!, c] .== 1, :], :multi_line) |> d -> insertcols(d, 1, :line => c)
                for c in ("ligne_1", "ligne_2", "ligne_4", "ligne_5")]...)
by_line
major_rate(tr, :multi_line)
"""
 Row │ line     multi_line  n      major  major_rate 
     │ String   Int64       Int64  Int64  Float64    
─────┼───────────────────────────────────────────────
   1 │ ligne_1           0  11827    332      0.0281
   2 │ ligne_1           1    283     61      0.2155
   3 │ ligne_2           0  11506    276      0.024
   4 │ ligne_2           1    346     81      0.2341
   5 │ ligne_4           0   2153     35      0.0163
   6 │ ligne_4           1    115     30      0.2609
   7 │ ligne_5           0   3232     76      0.0235
   8 │ ligne_5           1     89     35      0.3933

 Row │ multi_line  n      major  major_rate 
     │ Int64       Int64  Int64  Float64    
─────┼──────────────────────────────────────
   1 │          0  28815    722      0.0251
   2 │          1    351     82      0.2336

When there are multiple line incidents, the major_rate is significantly higher.
We keep all these as features.
""";

# --- symptom ------------------------------------------
by_symptom = major_rate(tr, :symptome)
save_csv(by_symptom, "major_rate_by_symptom")
plot_major_rate(by_symptom, :symptome, "Major rate by symptom (initial cause at declaration)", "major_rate_by_symptom")

# One column per symptom; "#N/A" (missing) is the reference
"""
Feu is the highest, very significant compared to other symptoms.
Second by Equipements fixes, Divers, Clientele
We can merge Exploitation stations and Exploitation trains into a single category.
""";

symptom_cols = Dict(
    "Clientèle" => "sym_clientele",
    "Matériel roulant" => "sym_materiel_roulant",
    "Équipements fixes" => "sym_equipements_fixes",
    "Feu, fumée, odeur, produit, etc..." => "sym_feu_fumee",
    "Exploitation trains" => "sym_exploitation",
    "Exploitation stations" => "sym_exploitation",
    "Divers" => "sym_divers",
)
for (value, c) in symptom_cols
    tr[!, c] = Int.(tr.symptome .== value)
end

# --- rolling stock ------------------------------------
major_rate(tr, :type_de_materiel)
"""
 Row │ type_de_materiel  n      major  major_rate 
     │ String            Int64  Int64  Float64    
─────┼────────────────────────────────────────────
   1 │ 10                 1230     29      0.0236
   2 │ 73                 2915     38      0.013
   3 │ Non affecté       25021    737      0.0295

10 is higher than 73. And Non affecte is much higher too. Could be dropped later if it doesn't provide additional predictive power.
""";

tr.tm_73 = Int.(tr.type_de_materiel .== "73")
tr.tm_10 = Int.(tr.type_de_materiel .== "10")      # "Non affecté" is the reference

# --- flags known at declaration -----------------------
major_rate(tr, :kfs)
major_rate(tr, :porte)
"""
 Row │ kfs    n      major  major_rate 
     │ Int64  Int64  Int64  Float64    
─────┼─────────────────────────────────
   1 │     0  28112    782      0.0278
   2 │     1   1054     22      0.0209

Few incidents have kfs = 1 (3.6%), and their major rate is slightly lower than for kfs = 0.
A weak signal, but known at declaration, so it is kept.

 Row │ porte  n      major  major_rate 
     │ Int64  Int64  Int64  Float64    
─────┼─────────────────────────────────
   1 │     0  26255    794      0.0302
   2 │     1   2911     10      0.0034

Door incidents (porte = 1, 10% of incidents) are rarely major: 0.3% vs 3.0%.
A feature that lowers the risk helps the ranking as much as one that raises it, so porte is kept.
""";

# --- flags recorded during the response ---------------
# Compare these rates with the ones above: a very high rate means the flag
# mostly records what happened *because* the incident was long.
major_rate(tr, :cat)
major_rate(tr, :dommage_materiel)
major_rate(tr, :urgence_metro)
by_evac = major_rate(tr, :evacuation)
save_csv(by_evac, "major_rate_by_evacuation")
"""
 Row │ evacuation        n      major  major_rate 
     │ String            Int64  Int64  Float64    
─────┼────────────────────────────────────────────
   1 │ #                 27795    263      0.0095
   2 │ Station              55     12      0.2182
   3 │ Train               968    264      0.2727
   4 │ Train et Station    293    264      0.901
   5 │ Voiture              55      1      0.0182

Not sure if we can use cat, dommage_materiel, or urgence_metro as features, since they are recorded during the response.
I don't think we should use these ones though, since its a response already. 
""";

#######################################################
# FEATURE TABLE
#######################################################
onset_features = [
    "ligne_1", "ligne_2", "ligne_4", "ligne_5", "multi_line",
    sort(unique(collect(values(symptom_cols))))...,
    "tm_73", "tm_10",
    "kfs", "porte",
]

# delay_min and severe are kept for evaluation (delay minutes captured, severe-tail recall) and are never model inputs: 
# they describe the outcome.
df = select(tr, :jour_calendaire => :date, 
    :hour, :mois_calendrier, :jour_de_la_semaine, :jour_du_mois,
    onset_features...,
    :delay_min, :severe, :target)
sort!(df, [:date, :hour])
size(df), sum(df.target)

CSV.write(joinpath("data", "df.csv"), df)
