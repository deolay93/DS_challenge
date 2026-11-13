using Statistics: mean

"""
    average_precision(y, p)

PR-AUC: area under the precision–recall curve, summed over distinct score
thresholds from highest to lowest. A random score gets the positive rate.
"""
function average_precision(y, p)
    n_pos = sum(y .== 1)
    n_pos == 0 && return missing
    order = sortperm(p; rev=true)
    ys, ps = y[order], p[order]
    ap, tp, prev_recall, i = 0.0, 0, 0.0, 1
    while i <= length(ps)
        j = i
        while j < length(ps) && ps[j + 1] == ps[i]   # group tied scores
            j += 1
        end
        tp += sum(ys[i:j] .== 1)
        recall = tp / n_pos
        ap += (recall - prev_recall) * (tp / j)
        prev_recall = recall
        i = j + 1
    end
    return ap
end

"""
    at_budget(y, p, share) -> (recall, precision)

Flag the top `share` of incidents by score (e.g. 0.05 = 5%).
recall = share of all majors that were flagged; precision = share of flags that were majors.
"""
function at_budget(y, p, share)
    k = max(1, ceil(Int, share * length(p)))
    top = partialsortperm(p, 1:k; rev=true)
    caught = sum(y[top] .== 1)
    return (recall=caught / max(1, sum(y .== 1)), precision=caught / k)
end

"""
    top_k(p, share) -> indices

The `share` of incidents with the highest scores (e.g. 0.01 = top 1%).
"""
top_k(p, share) = partialsortperm(p, 1:max(1, ceil(Int, share * length(p))); rev=true)

"""
    stakeholder_metrics(y, p, share; delay, severe, months) -> NamedTuple

What flagging the top `share` of incidents means in practice:
- lift: hit rate of the flags ÷ hit rate of random flags (the share of majors)
- alerts_per_month: how many incidents would be escalated each month
- delay_captured: share of all major-incident delay minutes covered by the flags
- severe_recall: share of the 30+ minute incidents that were flagged
"""
function stakeholder_metrics(y, p, share; delay, severe, months)
    top = top_k(p, share)
    major_delay = delay .* (y .== 1)
    return (lift=mean(y[top]) / mean(y),
            alerts_per_month=length(top) / months,
            delay_captured=sum(major_delay[top]) / sum(major_delay),
            severe_recall=sum(severe[top]) / max(1, sum(severe)))
end

"""
One row of a metrics table. Pass `delay`, `severe` and `months` to add the
stakeholder metrics for the top 1% and top 5%.
"""
function evaluate(y, p; model="model", delay=nothing, severe=nothing, months=nothing)
    b1, b5, b10 = at_budget(y, p, 0.01), at_budget(y, p, 0.05), at_budget(y, p, 0.10)
    r(x) = round(x; digits=3)
    row = (model=model, n=length(y), majors=sum(y), prevalence=r(mean(y)),
           pr_auc=r(average_precision(y, p)),
           recall_top1=r(b1.recall), precision_top1=r(b1.precision),
           recall_top5=r(b5.recall), precision_top5=r(b5.precision),
           recall_top10=r(b10.recall), precision_top10=r(b10.precision))
    delay === nothing && return row
    s1 = stakeholder_metrics(y, p, 0.01; delay, severe, months)
    s5 = stakeholder_metrics(y, p, 0.05; delay, severe, months)
    return merge(row, (
        lift_top1=r(s1.lift), alerts_per_month_top1=r(s1.alerts_per_month),
        delay_captured_top1=r(s1.delay_captured), severe_recall_top1=r(s1.severe_recall),
        lift_top5=r(s5.lift), alerts_per_month_top5=r(s5.alerts_per_month),
        delay_captured_top5=r(s5.delay_captured), severe_recall_top5=r(s5.severe_recall)))
end
