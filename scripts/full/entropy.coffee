@step =
  desc: "Summarize generation rows into entropy placeholder outputs"

  action: (S) ->
    rows = await S.need 'generation_rows'
    await S.need 'artifacts_registry'

    tokenRows = []
    summaryRows = []

    for row, idx in rows ? []
      words = String(row.generation ? '').split(/\s+/).filter (w) -> w.length
      for word, wordIdx in words
        tokenRows.push
          prompt_idx: idx
          token_idx: wordIdx
          token: word
          entropy_available: false
      summaryRows.push
        prompt_idx: idx
        artifact: row.artifact ? ''
        token_count: words.length
        entropy_available: false

    csv = "prompt_idx,artifact,token_count,entropy_available\n" +
      summaryRows.map((r) -> "#{r.prompt_idx},#{r.artifact},#{r.token_count},#{r.entropy_available}").join("\n") +
      "\n"

    S.make 'entropy_tokens', tokenRows
    S.make 'entropy_summary', csv
    S.done()
    return
