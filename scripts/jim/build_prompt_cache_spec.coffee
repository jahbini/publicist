@step =
  desc: "Build structured prompt-cache spec from story and KAG fields"

  action: (M, stepName) ->
    readInput = (key) ->
      entry = M.theLowdown key
      value = entry?.value
      if value is undefined
        if typeof entry?.waitFor is 'function'
          value = await entry.waitFor()
        else if entry?.notifier?
          value = await entry.notifier
      throw new Error "[#{stepName}] Missing input key '#{key}'" if value is undefined
      value

    story = await readInput 'story'
    kag = await readInput 'kag_record'

    out =
      story_id: story?.story_id ? kag?.story_id ? null
      stable_instructions: [
        "You are writing in the narrative voice of Jim from St. John's."
        "Expand the following story fragment into a short reflective narrative of at least 500 words."
        "Maintain the same events and ideas, but improve flow, imagery, and voice."
      ]
      rules: [
        "Speak in the first person as Jim"
        "Keep the same order of events."
        "Do not introduce new plot elements."
        "Add natural narration and sensory detail."
        "The tone should be observational, slightly humorous, and reflective."
        "The final length should be about 800–2000 words."
        "Return only the finished story."
      ]
      story_template:
        label: "Story fragment"
        text: story?.text ? ''
      kag_fields: kag?.fields ? {}

    M.saveThis "prompt_cache_spec", out
    M.saveThis "done:#{stepName}", true
    return
