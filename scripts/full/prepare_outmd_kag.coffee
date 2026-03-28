@step =
  desc: "Convert Markdown stories into KAG-style training rows"

  action: (S) ->
    mdText = await S.need 'stories_md'

    extractChunks = (rawText) ->
      parts = String(rawText ? '').split /^#\s+/m
      (part.trim() for part in parts when part.trim().length)

    makeEntry = (chunk) ->
      idea = if chunk.length > 200 then chunk.slice(0, 200) + '…' else chunk
      prompt = [
        "You are St. John's Jim — a myth-weaving, bar-stool Buddha of the Pacific Northwest."
        'Tell a new short story in your own voice, using this idea as inspiration:'
        ''
        idea
      ].join "\n"
      {
        prompt: prompt
        response: chunk.trim()
      }

    rows = extractChunks(mdText).map makeEntry
    S.make 'out_kag_rows', rows
    S.saveThis 'out_kag:entries', rows
    S.done()
    return
