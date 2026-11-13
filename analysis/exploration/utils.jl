using Unicode

raw_file(prefix) = joinpath(raw_dir, only(filter(f -> startswith(f, prefix), readdir(raw_dir))))

function clean_names!(df)
    new = map(names(df)) do n
        n = Unicode.normalize(lowercase(n); stripmark=true)  # "Évacuation" → "evacuation"
        n = replace(n, "'" => "", " " => "_", "/" => "_")
    end
    rename!(df, new)
end

# from incidents-data.jl
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

function save_csv(df, name)
    mkpath(joinpath("analysis", "csv"))
    CSV.write(joinpath("analysis", "csv", name * ".csv"), df)
end
function save_png(fig, name)
    mkpath(joinpath("analysis", "plots"))
    save(joinpath("analysis", "plots", name * ".png"), fig)
end

function band_range(label)
    nums = [parse(Int, m.match) for m in eachmatch(r"\d+", label)]
    occursin("et moins", label) && return (0.0, Float64(nums[1]))
    occursin("et plus", label) && return (Float64(nums[1]), Inf)
    return (Float64(nums[1]), Float64(nums[end]))
end

function clock_format(s)
    m = match(r"^(\d{1,2}):(\d{2})(:\d{2})?$", s)
    m === nothing && return "other"
    fmt = m.captures[3] === nothing ? "HH:MM" : "HH:MM:SS"
    after = parse(Int, m.captures[1]) >= 24 ? "24:00 or later" : "before 24:00"
    return "$fmt, $after"
end

function service_minutes(s)
    p = parse.(Int, split(s, ':'))
    return p[1] * 60 + p[2] + (length(p) > 2 ? p[3] / 60 : 0.0)
end

"""Number of incidents, number of majors and major rate per value of `col`."""
major_rate(df, col) = sort(combine(groupby(df, col),
    nrow => :n,
    :target => sum => :major,
    :target => (x -> round(mean(x); digits=4)) => :major_rate), col)

"""Bar chart of the major rate per value of `col`, with the overall rate as a dashed line."""
function plot_major_rate(tbl, col, title, name)
    fig = Figure(size=(900, 400))
    labels = string.(tbl[!, col])
    ax = Axis(fig[1, 1]; title=title, ylabel="Share of incidents ≥ 20 min",
              xticks=(1:nrow(tbl), labels), xticklabelrotation=π / 6)
    barplot!(ax, 1:nrow(tbl), tbl.major_rate)
    hlines!(ax, [sum(tbl.major) / sum(tbl.n)]; linestyle=:dash, color=:gray)   # overall rate
    save_png(fig, name)
    return fig
end

function line_flags(ligne)
    s = lowercase(ligne)
    has(n, colour) = occursin(Regex("(?<!\\d)$(n)(?!\\d)"), s) || occursin(colour, s)
    return (has(1, "verte"), has(2, "orange"), has(4, "jaune"), has(5, "bleue"))
end