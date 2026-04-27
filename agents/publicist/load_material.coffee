#!/usr/bin/env coffee

splitSentences = (text) ->
  return [] unless text?
  text
    .replace(/\s+/g, ' ')
    .split(/(?<=[.!?])\s+/)
    .map((part) -> part.trim())
    .filter(Boolean)

@step =
  desc: 'Load source material for draft-only publicist planning.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    sourceFile = M.getStepParam stepName, 'source_file'
    throw new Error "[#{stepName}] Missing required key 'source_file'" unless sourceFile?

    sourceText = M.theLowdown(sourceFile)?.value
    throw new Error "[#{stepName}] Missing source material at #{sourceFile}" unless sourceText?

    campaignName = M.getStepParam(stepName, 'campaign_name') ? experiment.run?.campaign_name ? 'Untitled campaign'
    brandName = M.getStepParam(stepName, 'brand_name') ? experiment.run?.brand_name ? 'Unknown brand'
    launchCity = M.getStepParam(stepName, 'launch_city') ? experiment.run?.launch_city
    announcementDate = M.getStepParam stepName, 'announcement_date'
    reviewGoal = M.getStepParam(stepName, 'review_goal') ? 'Prepare reviewed outreach drafts only.'

    sentences = splitSentences sourceText
    highlights = sentences.slice(0, 4)

    material =
      campaign_name: campaignName
      brand_name: brandName
      launch_city: launchCity
      announcement_date: announcementDate
      review_goal: reviewGoal
      source_file: sourceFile
      source_text: sourceText.trim()
      highlights: highlights
      notes:
        experiment_output_dir: experiment.run?.output_dir
        draft_only: true
        no_live_actions: true

    L.make 'source_material', material
    L.done()
    return
