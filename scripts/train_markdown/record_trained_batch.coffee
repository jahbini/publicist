@step =
  desc: "Record the completed LoRA training batch"

  action: (M, stepName) ->
    newIdsKey = M.getStepParam stepName, 'new_story_ids'
    trainedKey = M.getStepParam stepName, 'trained_story_ids'

    newIdsEntry = M.theLowdown newIdsKey
    newStoryIds = newIdsEntry?.value
    newStoryIds = await newIdsEntry.notifier if newStoryIds is undefined

    trainedEntry = M.theLowdown trainedKey
    trainedStoryIds = trainedEntry?.value
    trainedStoryIds = [] if trainedStoryIds is undefined

    throw new Error "[#{stepName}] #{newIdsKey} must be an array" unless Array.isArray newStoryIds
    throw new Error "[#{stepName}] #{trainedKey} must be an array" unless Array.isArray trainedStoryIds

    merged = []
    seen = new Set()

    for title in trainedStoryIds
      continue unless title?
      continue if seen.has title
      seen.add title
      merged.push title

    for title in newStoryIds
      continue unless title?
      continue if seen.has title
      seen.add title
      merged.push title

    console.log "[record_trained_batch] previous trained stories:", trainedStoryIds.length
    console.log "[record_trained_batch] current batch stories:", newStoryIds.length
    console.log "[record_trained_batch] total trained stories:", merged.length

    for title, idx in newStoryIds
      console.log "[record_trained_batch] trained[#{idx}] #{title}" if title?

    M.saveThis trainedKey, merged
    M.saveThis "done:#{stepName}", true
    return
