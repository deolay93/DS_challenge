using CSV, DataFrames, Dates
using CairoMakie 

include(abspath("analysis/exploration/utils.jl"))

raw_dir = joinpath("data", "raw")

# The .xls files are actually CSV text, so CSV.jl reads them directly
km = CSV.read(raw_file("Kilom"), DataFrame)

size(km) # (8472, 11)
describe(km, :eltype, :nmissing, :nunique, :first)
"""
 Row │ variable              eltype      nmissing  nunique  first       
     │ Symbol                DataType    Int64     Union…   Any         
─────┼──────────────────────────────────────────────────────────────────
   1 │ Ligne                 DataString         0  4        Ligne bleue
   2 │ Période Exploitation  DataString         0  28       18N
   3 │ Type de Jour          DataString         0  8        Dimanche
   4 │ Tournée               Int64              0           1
   5 │ Année civile          Int64              0           2019
   6 │ Année civile/mois     DataString         0  57       2019-01
   7 │ Année civile/semaine  Date               0  248      2018-12-31
   8 │ Jour calendaire       Date               0  1734     2019-01-06
   9 │ Jour de la semaine    DataString         0  7        Dimanche
  10 │ Mois calendrier       Int64              0           1
  11 │ KM planifié           DataString         0  83       15810
""";

# clean up column names 
clean_names!(km)
names(km)

# checkup on the actual value types within each column, even though they might be stored as strings
# by looking at a few unique values in each column
for col in names(km)
    println("Column: ", col)
    println("Unique types: ", first(unique(km[!, col]),5))
    println("Unique values: ", length(unique(km[!, col])))
    println()
end

"""
Column: ligne
Unique types: DataStrings.DataString["Ligne bleue", "Ligne jaune", "Ligne orange", "Ligne verte"]
Unique values: 4
Note: this indicates the metro line. Could be used for mapping

Column: periode_exploitation
Unique types: DataStrings.DataString["18N", "19J", "19M", "19N", "19S"]
Unique values: 28

Column: type_de_jour
Unique types: DataStrings.DataString["Dimanche", "Quatrième pér. fête", "Samedi", "Semaine", "Troisième pér. fête"]
Unique values: 8
Note: this indicates the type

Column: tournee
Unique types: [1]
Unique values: 1

Column: annee_civile
Unique types: [2019, 2020, 2021, 2022, 2023]
Unique values: 5
Note: From incidents data, we have coverage for (Date("2019-01-01"), Date("2025-09-30")), but here it only goes until 2023

Column: annee_civile_mois
Unique types: DataStrings.DataString["2019-01", "2019-02", "2019-03", "2019-04", "2019-05"]
Unique values: 57

Column: annee_civile_semaine
Unique types: [Date("2018-12-31"), Date("2019-01-07"), Date("2019-01-14"), Date("2019-01-21"), Date("2019-01-28")]
Unique values: 248

Column: jour_calendaire
Unique types: [Date("2019-01-06"), Date("2019-01-02"), Date("2019-01-05"), Date("2019-01-03"), Date("2019-01-04")]
Unique values: 1734

Column: jour_de_la_semaine
Unique types: DataStrings.DataString["Dimanche", "Mercredi", "Samedi", "Jeudi", "Vendredi"]
Unique values: 7

Column: mois_calendrier
Unique types: [1, 2, 3, 4, 5]
Unique values: 12

Column: km_planifie
Unique types: DataStrings.DataString["15810", "16315,92", "26940,24", "14039,28", "18592,56"]
Unique values: 83
""";

# date coverage for this dataset 
# The dataset covers incidents from the earliest date to the latest date in the 'jour_calendaire' column.
extrema(km.jour_calendaire)
"""
(Date("2019-01-01"), Date("2023-09-30"))
""";

"""
We cannot really use this dataset, since it only covers planned kilometers up to September 2023, whereas the incidents 
data extends until September 2025.
""";