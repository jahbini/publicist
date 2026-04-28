#!/usr/bin/env coffee

crypto = require 'crypto'

DEFAULT_SOURCE_TEXT = "Describe this campaign here.\n"

splitSentences = (text) ->
  return [] unless text?
  text
    .replace(/\s+/g, ' ')
    .split(/(?<=[.!?])\s+/)
    .map((part) -> part.trim())
    .filter(Boolean)

deriveCampaignName = (text) ->
  lines = String(text ? '')
    .split(/\r?\n/)
    .map((line) -> line.trim())
    .filter(Boolean)
  return 'Untitled campaign' unless lines.length
  first = lines[0].replace(/^campaign:\s*/i, '').trim()
  first = first.replace(/^brand:\s*/i, '').trim()
  return first.slice(0, 120) if first.length
  'Untitled campaign'

deriveBrandName = (text, campaignName) ->
  lines = String(text ? '')
    .split(/\r?\n/)
    .map((line) -> line.trim())
    .filter(Boolean)
  brandLine = lines.find (line) -> /^brand:\s*/i.test(line)
  if brandLine?
    brand = brandLine.replace(/^brand:\s*/i, '').trim()
    return brand if brand.length
  String(campaignName ? 'Campaign').split(/[:,-]/)[0].trim() or 'Campaign'

deriveLaunchCity = (text) ->
  lines = String(text ? '')
    .split(/\r?\n/)
    .map((line) -> line.trim())
    .filter(Boolean)
  cityLine = lines.find (line) -> /^city:\s*/i.test(line) or /^launch city:\s*/i.test(line)
  return null unless cityLine?
  cityLine.replace(/^(city|launch city):\s*/i, '').trim() or null

@step =
  desc: 'Load source material for draft-only publicist planning.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    sourceFile = M.getStepParam stepName, 'source_file'
    throw new Error "[#{stepName}] Missing required key 'source_file'" unless sourceFile?

    sourceText = M.theLowdown(sourceFile)?.value

    if sourceText is undefined
      M.saveThis sourceFile, DEFAULT_SOURCE_TEXT
      sourceText = M.theLowdown(sourceFile)?.value

    throw new Error "[#{stepName}] Missing source material. Attempted key: #{sourceFile}" unless sourceText?

    sourceHash = crypto.createHash('sha256').update(String(sourceText)).digest('hex')
    campaignName = M.getStepParam(stepName, 'campaign_name') ? experiment.run?.campaign_name ? deriveCampaignName(sourceText)
    brandName = M.getStepParam(stepName, 'brand_name') ? experiment.run?.brand_name ? deriveBrandName(sourceText, campaignName)
    launchCity = M.getStepParam(stepName, 'launch_city') ? experiment.run?.launch_city ? deriveLaunchCity(sourceText)
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
      source_hash: sourceHash
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
