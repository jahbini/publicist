#!/usr/bin/env coffee

isBlank = (value) ->
  String(value ? '').trim().length is 0

compactText = (value) ->
  String(value ? '')
    .replace(/\s+/g, ' ')
    .trim()

decisionBucket = (decision) ->
  value = String(decision?.decision ? '').trim().toLowerCase()
  return 'approved' if decision?.approved_for_send is true or value in ['approved', 'approve']
  return 'rejected' if value in ['rejected', 'reject']
  return 'revise' if value is 'revise'
  'pending_review'

makeFact = (result) ->
  excerpt = compactText(result?.short_text_excerpt ? '')
  return null unless excerpt.length
  prefix = if not isBlank(result?.title) then "#{result.title}: " else ''
  "#{prefix}#{excerpt}".slice(0, 320)

makeImprovement = (draft, result) ->
  title = compactText(result?.title ? '')
  org = draft?.organization ? result?.organization ? draft?.audience_label ? 'the target'
  if title.length
    "Reference #{org}'s current focus using '#{title}' to make the outreach feel specific."
  else
    "Use the fetched context to make the note to #{org} more specific and timely."

makeTalkingPoint = (draft, result) ->
  excerpt = compactText(result?.short_text_excerpt ? '')
  org = draft?.organization ? result?.organization ? draft?.audience_label ? 'the audience'
  return null unless excerpt.length
  sentence = excerpt.split(/(?<=[.!?])\s+/)[0] ? excerpt
  "Tie #{draft?.brand_name ? 'the campaign'} to #{org} context: #{sentence}".slice(0, 280)

uniqueStrings = (values) ->
  seen = new Set()
  rows = []
  for value in values when not isBlank(value)
    text = String(value).trim()
    continue if seen.has(text)
    seen.add text
    rows.push text
  rows

@step =
  desc: 'Generate research-based draft improvement suggestions without overwriting human text.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    researchResultsKey = 'research_results'
    messageDraftsKey = 'message_drafts'
    reviewDecisionsKey = 'review_decisions'

    researchResults = await L.need researchResultsKey
    messageDrafts = await L.need messageDraftsKey
    reviewDecisions = await L.need reviewDecisionsKey

    throw new Error "[#{stepName}] Missing required artifact '#{researchResultsKey}'" unless Array.isArray(researchResults?.results)
    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless Array.isArray(messageDrafts?.drafts)
    throw new Error "[#{stepName}] Missing required artifact '#{reviewDecisionsKey}'" unless Array.isArray(reviewDecisions?.decisions)

    decisionsByDraftId = {}
    for decision in reviewDecisions.decisions when decision?.draft_id?
      decisionsByDraftId[decision.draft_id] = decision

    resultsByDraftId = {}
    for result in researchResults.results when result?
      draftId = null
      requestId = String(result?.request_id ? '').trim()
      if /^research_(review|follow_up)_/i.test(requestId)
        draftId = requestId.replace(/^research_(review|follow_up)_/i, '')
      unless draftId?
        for draft in messageDrafts.drafts when draft?.draft_id?
          matchesOrganization = compactText(result.organization) is compactText(draft.organization)
          matchesContact = compactText(result.contact_name) is compactText(draft.contact_name)
          matchesAudience = compactText(result.audience) is compactText(draft.audience_label)
          if (matchesOrganization and matchesContact) or (matchesAudience and not isBlank(result.audience))
            draftId = draft.draft_id
            break
      continue unless draftId?
      resultsByDraftId[draftId] ?= []
      resultsByDraftId[draftId].push result

    enrichedDrafts = messageDrafts.drafts.map (draft) ->
      draftId = draft?.draft_id ? ''
      decision = decisionsByDraftId[draftId] ? null
      matchedResults = resultsByDraftId[draftId] ? []
      relevantFacts = uniqueStrings matchedResults.map (result) -> makeFact(result)
      suggestedImprovements = uniqueStrings matchedResults.map (result) -> makeImprovement(draft, result)
      talkingPoints = uniqueStrings matchedResults.map (result) -> makeTalkingPoint(draft, result)

      {
        draft_id: draftId
        audience_label: draft?.audience_label ? ''
        organization: draft?.organization ? ''
        contact_name: draft?.contact_name ? ''
        decision: decisionBucket(decision)
        approved_for_send: decision?.approved_for_send is true
        research_enriched: true
        matched_request_ids: uniqueStrings matchedResults.map (result) -> result?.request_id
        matched_result_count: matchedResults.length
        suggested_improvements: suggestedImprovements
        additional_talking_points: talkingPoints
        relevant_facts: relevantFacts
      }

    payload =
      generated_for: experiment.run?.campaign_name
      draft_count: messageDrafts.drafts.length
      enriched_count: enrichedDrafts.filter((row) -> row.matched_result_count > 0).length
      enriched_drafts: enrichedDrafts
      summary:
        fetched_result_count: researchResults.results.length
        drafts_with_research: enrichedDrafts.filter((row) -> row.matched_result_count > 0).length
        drafts_without_research: enrichedDrafts.filter((row) -> row.matched_result_count is 0).length
        suggestions_only: true

    L.make 'enriched_drafts', payload
    L.done()
    return
