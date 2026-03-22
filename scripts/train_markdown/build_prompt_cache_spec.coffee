@step =
  desc: "Build structured prompt-cache spec from story and KAG fields"

  action: (M, stepName) ->
    kagEntry = M.theLowdown 'kag_record'
    kag = kagEntry?.value
    if kag is undefined
      if typeof kagEntry?.waitFor is 'function'
        kag = await kagEntry.waitFor()
      else if kagEntry?.notifier?
        kag = await kagEntry.notifier
    throw new Error "[#{stepName}] Missing input key 'kag_record'" if kag is undefined

    storyKey = M.getStepParam(stepName, 'story_key')
    storyFragment = M.getStepParam(stepName, 'story_fragment')
    stableInstructions = M.getStepParam(stepName, 'stable_instructions')
    rules = M.getStepParam(stepName, 'rules')
    storyTemplateLabel = M.getStepParam(stepName, 'story_template_label')
    storyText = ''
    storyId = kag?.story_id ? null

    if storyKey?
      storyEntry = M.theLowdown storyKey
      story = storyEntry?.value
      if story is undefined
        if typeof storyEntry?.waitFor is 'function'
          story = await storyEntry.waitFor()
        else if storyEntry?.notifier?
          story = await storyEntry.notifier
      throw new Error "[#{stepName}] Missing input key '#{storyKey}'" if story is undefined
      storyText = story?.text ? ''
      storyId = story?.story_id ? storyId
    else
      storyText = storyFragment ? ''

    out =
      story_id: storyId
      stable_instructions: stableInstructions
      rules: rules
      story_template:
        label: storyTemplateLabel
        text: storyText
      kag_fields: kag?.fields ? {}

    M.saveThis "prompt_cache_spec", out
    M.saveThis "done:#{stepName}", true
    return
