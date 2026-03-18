@step =
  desc: "Extract structured KAG fields from the assembled Jim story context"

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

    recipe = await readInput 'story_recipe'
    parts = await readInput 'story_parts'
    expanded = await readInput 'expanded_story_parts'

    out =
      story_id: recipe?.story_id ? parts?.story_id ? expanded?.story_id ? null
      keys: parts?.keys ? {}
      fields:
        scene:
          key: parts?.keys?.scene ? null
          location: parts?.scene?.location ? null
          source_text: parts?.scene?.text ? null
          expanded_text: expanded?.expanded_parts?.scene?.text ? null
        arrival:
          key: parts?.keys?.arrival ? null
          character: parts?.arrival?.character ? null
          source_text: parts?.arrival?.text ? null
          expanded_text: expanded?.expanded_parts?.arrival?.text ? null
        disturbance:
          key: parts?.keys?.disturbance ? null
          theme: parts?.disturbance?.theme ? null
          source_text: parts?.disturbance?.text ? null
          expanded_text: expanded?.expanded_parts?.disturbance?.text ? null
        reflection:
          key: parts?.keys?.reflection ? null
          source_text: parts?.reflection?.text ? null
          expanded_text: expanded?.expanded_parts?.reflection?.text ? null
        realization:
          key: parts?.keys?.realization ? null
          source_text: parts?.realization?.text ? null
          expanded_text: expanded?.expanded_parts?.realization?.text ? null

    M.saveThis "kag_record", out
    M.saveThis "done:#{stepName}", true
    return
