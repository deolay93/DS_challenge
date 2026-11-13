using CSV, DataFrames, Dates
using CairoMakie 

include(abspath("analysis/exploration/utils.jl"))

raw_dir = joinpath("data", "raw")

# The .xls files are actually CSV text, so CSV.jl reads them directly
inc = CSV.read(raw_file("Incidents"), DataFrame)

size(inc) # (45561, 26)
describe(inc, :eltype, :nmissing, :nunique, :first)
"""
 Row │ variable             eltype      nmissing  nunique  first           
     │ Symbol               DataType    Int64     Union…   Any             
─────┼─────────────────────────────────────────────────────────────────────
   1 │ Numero d'incident    DataString         0  45561    S01011901
   2 │ Type d'incident      DataString         0  2        S
   3 │ Cause primaire       DataString         0  6        Autres
   4 │ Cause secondaire     DataString         0  21       Autres
   5 │ Symptome             DataString         0  8        Clientèle
   6 │ Ligne                DataString         0  22       Ligne orange
   7 │ Numéro de tournée    DataString         0  168      #
   8 │ Heure de l'incident  DataString         0  1439     02:56
   9 │ Heure de reprise     DataString         0  1549     03:32
  10 │ Incident en minutes  DataString         0  8        02 min et moins
  11 │ Véhicule             DataString         0  1058     #
  12 │ Porte de voiture     DataString         0  38       #
  13 │ Type de matériel     DataString         0  3        Non affecté
  14 │ Code de lieu         DataString         0  230      Snowdon
  15 │ Dommage matériel     Int64              0           0
  16 │ KFS                  Int64              0           0
  17 │ Porte                Int64              0           0
  18 │ Urgence métro        Int64              0           0
  19 │ CAT                  Int64              0           0
  20 │ Évacuation           DataString         0  5        #
  21 │ Année civile         Int64              0           2019
  22 │ Année civile/mois    DataString         0  81       janv-19
  23 │ Mois calendrier      Int64              0           1
  24 │ Jour du mois         Int64              0           1
  25 │ Jour de la semaine   Int64              0           2
  26 │ Jour calendaire      Date               0  2465     2019-01-01
""";

# clean up column names 
clean_names!(inc)
names(inc)

# checkup on the actual value types within each column, even though they might be stored as strings
# by looking at a few unique values in each column
for col in names(inc)
    println("Column: ", col)
    println("Unique types: ", first(unique(inc[!, col]),5))
    println("Unique values: ", length(unique(inc[!, col])))
    println()
end

"""
Column: numero_dincident 
Unique types: DataStrings.DataString["S01011901", "S01011902", "S01011903", "S01011904", "S01011905"]  
Unique values: 45561
Note: this is the id, cannot be used to train models, should be excluded from features.

Column: type_dincident
Unique types: DataStrings.DataString["S", "T"] 
Unique values: 2
Note: this indicates the type of incident, could be used as a categorical feature (binary: is_train_incident) 

Column: cause_primaire
Unique types: DataStrings.DataString["Autres", "Clientèle", "Équipements fixes", "Exploitation trains", "Matériel roulant"] 
Unique values: 6
Note: this indicates the primary cause of the incident, identified after the incident, therefore cannot be used. 

Column: cause_secondaire
Unique types: DataStrings.DataString["Autres", "Causes externes", "Méfait volontaire", "Service aux trains", "Nuisance involontaire"] 
Unique values: 21
Note: this indicates the secondary cause of the incident, identified after the incident, therefore cannot be used. 

Column: symptome
Unique types: DataStrings.DataString["Clientèle", "Exploitation stations", "Feu, fumée, odeur, produit, etc...", "#N/A", "Équipements fixes"] 
Unique values: 8
Note: this indicates the symptom of the incident, could be used as a categorical feature, but needs one-hot encoding or similar preprocessing.

Column: ligne
Unique types: DataStrings.DataString["Ligne orange", "Ligne verte", "Ligne bleue", "Ligne jaune", "Ligne 1, 2, 4, 5"] 
Unique values: 22
Note: this indicates the line of the incident, could be used as a categorical feature, but needs one-hot encoding or similar preprocessing.
      but we need to map the name of the line into 1, 2, 4, 5, and have one-hot for [1, 2, 4, 5]

Column: numero_de_tournee
Unique types: DataStrings.DataString["#", "59", "61", "8", "19"]  
Unique values: 168
Note: this indicates the tour number, could be used as a categorical feature, but might have too many unique values for 
one-hot encoding to be efficient.

Column: heure_de_lincident
Unique types: DataStrings.DataString["02:56", "03:35", "04:56", "05:25", "07:11"]
Unique values: 1439
Note: this indicates the time of the incident. Could be used as a feature, but might need to be converted into a 
numerical format (e.g., minutes since midnight) for modeling purposes.

Column: heure_de_reprise
Unique types: DataStrings.DataString["03:32", "03:42", "04:41", "05:36", "05:54"]
Unique values: 1549
Note: this indicates the time of the incident resolution. We cannot use this data, since it tells us the target.

Column: incident_en_minutes
Unique types: DataStrings.DataString["02 min et moins", "03 à 04 min", "10 à 14 min", "05 à 09 min", "25 à 29 min"]
Unique values: 8
Note: this indicates the duration of the incident in minutes. This should be the target variable for identifying 
severity of incidents.

Column: vehicule
Unique types: DataStrings.DataString["#", "10195", "10338", "78072", "10323"]
Unique values: 1058
Note: this indicates the vehicle involved in the incident. Could be used as a categorical feature, but might have too 
many unique values for one-hot encoding to be efficient.

Column: porte_de_voiture
Unique types: DataStrings.DataString["#", "1;", "2;", "8;", "5;"]
Unique values: 38
Note: this indicates the door of the car involved in the incident. We already have a `porte` column indicating whether 
the door was involved, so this might be redundant.

Column: type_de_materiel
Unique types: DataStrings.DataString["Non affecté", "73", "10"]
Unique values: 3
Note: this indicates the type of material involved in the incident. Could be used as a categorical feature.

Column: code_de_lieu
Unique types: DataStrings.DataString["Snowdon", "Place-des-Arts", "Lionel-Groulx", "Berri-UQAM", "St-Laurent"]
Unique values: 230
Note: this indicates the location code of the incident. Could be used as a categorical feature, 
but might have too many unique values for one-hot encoding to be efficient.

Column: dommage_materiel
Unique types: [0, 1]
Unique values: 2
Note: this indicates whether there was material damage. Could be used as a binary feature.

Column: kfs
Unique types: [0, 1]
Unique values: 2
Note: this indicates whether the KFS system was involved. Could be used as a binary feature.

Column: porte
Unique types: [0, 1]
Unique values: 2
Note: this indicates whether the door was involved. Could be used as a binary feature.

Column: urgence_metro
Unique types: [0, 1]
Unique values: 2
Note: this indicates whether it was a metro emergency. Could be used as a binary feature.

Column: cat
Unique types: [0, 1]
Unique values: 2
Note: CAT = traction power cut. Recorded during the response (can be trigger or response measure), so excluded from the features.

Column: evacuation
Unique types: DataStrings.DataString["#", "Train et Station", "Train", "Voiture", "Station"]
Unique values: 5
Note: this indicates the type of evacuation involved in the incident. Could be used as a categorical feature.

Column: annee_civile
Unique types: [2019, 2020, 2021, 2022, 2023]
Unique values: 7
Note: this indicates the civil year of the incident. Not really useful as a feature on its own.

Column: annee_civile_mois
Unique types: DataStrings.DataString["janv-19", "janv-20", "janv-21", "janv-22", "janv-23"]
Unique values: 81
Note: this indicates the civil year and month of the incident. Its a duplication of the annee_civile and mois_calendrier columns.

Column: mois_calendrier
Unique types: [1, 2, 3, 4, 5]
Unique values: 12
Note: this indicates the calendar month of the incident, could be used as a categorical feature.

Column: jour_du_mois
Unique types: [1, 2, 3, 4, 5]
Unique values: 31
Note: this indicates the day of the month of the incident. Could be used as a numerical feature.

Column: jour_de_la_semaine
Unique types: [2, 3, 5, 6, 7]
Unique values: 7
Note: this indicates the day of the week of the incident. Could be used as a categorical feature.

Column: jour_calendaire
Unique types: [Date("2019-01-01"), Date("2020-01-02"), Date("2020-01-01"), Date("2021-01-01"), Date("2022-01-01")]
Unique values: 2465
Note: this indicates the calendar day of the incident. This will be used to split the data into training and testing sets based on time.
""";

# some feature explore 
unique(inc.porte_de_voiture)

# date coverage for this dataset 
# The dataset covers incidents from the earliest date to the latest date in the 'jour_calendaire' column.
extrema(inc.jour_calendaire)
"""
julia> extrema(inc.jour_calendaire)
(Date("2019-01-01"), Date("2025-09-30"))
""";

col_keep = [
    "type_dincident",
    "symptome",
    "ligne",
    "heure_de_lincident",
    "heure_de_reprise",
    "incident_en_minutes",
    "type_de_materiel",
    "kfs",
    "porte",
    "dommage_materiel",
    "urgence_metro",
    "cat",
    "evacuation",

    # temporal 
    "mois_calendrier",
    "jour_du_mois", 
    "jour_de_la_semaine",

    # date 
    "jour_calendaire"
]