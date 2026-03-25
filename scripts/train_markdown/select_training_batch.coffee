@step =
  desc: "Select the next batch of story titles for LoRA training"

  action: (M, stepName) ->
    storiesKey = M.getStepParam stepName, 'marshalled_stories'
    newIdsKey = M.getStepParam stepName, 'new_story_ids'
    trainedKey = M.getStepParam stepName, 'trained_story_ids'
    batchSize = M.getStepParam stepName, 'batch_size'

    storiesEntry = M.theLowdown storiesKey
    stories = storiesEntry?.value
    stories = await storiesEntry.notifier if stories is undefined

    trainedEntry = M.theLowdown trainedKey
    trainedStoryIds = trainedEntry?.value
    trainedStoryIds = [] if trainedStoryIds is undefined

    throw new Error "[#{stepName}] #{storiesKey} must be an array" unless Array.isArray stories
    throw new Error "[#{stepName}] #{trainedKey} must be an array" unless Array.isArray trainedStoryIds

    trainedSet = new Set()
    for title in trainedStoryIds
      continue unless title?
      trainedSet.add title

    unseenTitles = []
    unseenSet = new Set()
    batchTitles = []
    batchSet = new Set()

    for segment in stories
      title = segment?.meta?.title
      continue unless title?

      unless trainedSet.has(title) or unseenSet.has(title)
        unseenSet.add title
        unseenTitles.push title

      continue if trainedSet.has title
      continue if batchSet.has title

      batchSet.add title
      batchTitles.push title
      break if batchTitles.length >= batchSize

    storiesLeft = Math.max unseenTitles.length - batchTitles.length, 0

    console.log "[select_training_batch] total unseen stories:", unseenTitles.length
    console.log "[select_training_batch] already trained stories:", trainedSet.size
    console.log "[select_training_batch] selected batch size:", batchTitles.length
    console.log "[select_training_batch] stories left after this batch:", storiesLeft

    for title, idx in batchTitles
      console.log "[select_training_batch] batch[#{idx}] #{title}"

    M.saveThis newIdsKey, batchTitles
    M.saveThis "done:#{stepName}", true
    return
