d3 = require 'd3-dsv'
_ = require 'lodash'

median = (xs) ->
  ys = _.sortBy xs
  return 0 unless ys.length
  mid = Math.floor ys.length / 2
  if ys.length % 2 then ys[mid] else (ys[mid - 1] + ys[mid]) / 2

endsSentence = (s) ->
  /[.!?…]$/.test(String(s).trim())

@step =
  desc: "Aggregate and summarize ablation results"

  action: (S) ->
    rows = await S.need 'ablation_rows'
    throw new Error 'ablation_rows contains no rows' unless Array.isArray(rows) and rows.length > 0

    groups = _.groupBy rows, (r) ->
      [r.model_id ? 'unknown-model', r.artifact ? 'unknown-artifact', r.prompt_variant ? 'default'].join('|')

    agg = []
    for key, g of groups
      n = g.length
      emptyCount = _.sumBy g, (x) -> if x.is_empty then 1 else 0
      sentEnd = _.sumBy g, (x) -> if endsSentence(x.generation or '') then 1 else 0
      lens = (x.len_words for x in g when typeof x.len_words is 'number')
      [modelId, artifact, promptVariant] = key.split '|'
      agg.push
        model_id: modelId
        artifact: artifact
        prompt_variant: promptVariant
        n: n
        empty_rate: emptyCount / n
        sent_end_rate: sentEnd / n
        avg_len: _.mean(lens) or 0
        med_len: median(lens) or 0

    summary =
      created_utc: new Date().toISOString().replace(/\.\d+Z$/, 'Z')
      total_rows: rows.length
      groups: agg

    S.make 'ablation_summary_json', summary
    S.make 'ablation_summary_csv', d3.csvFormat(agg)
    S.saveThis 'sanity:summary', summary
    S.done()
    return summary
