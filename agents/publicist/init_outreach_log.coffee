#!/usr/bin/env coffee

normalizeText = (value) ->
  String(value ? '').trim()

resolveArtifactPayload = (M, experiment, artifactKey, validator) ->
  value = M.theLowdown(artifactKey)?.value
  return { value, key: artifactKey } if validator(value)

  targetKey = experiment?.artifacts?[artifactKey]?.target
  targetValue = M.theLowdown(targetKey)?.value
  return { value: targetValue, key: targetKey } if targetKey? and validator(targetValue)

  { value, key: artifactKey, targetKey, targetValue }

buildDefaultEntry = (draft) ->
  draft_id: draft.draft_id ? ''
  organization: draft.organization ? ''
  audience: draft.audience_label ? draft.audience_key ? ''
  channel: draft.contact_channel ? ''
  status: 'not_sent'
  sent_manually_at: null
  response_status: 'none'
  follow_up_date: null
  notes: ''

@step =
  desc: 'Initialize or preserve a manual outreach log for reviewed publicist drafts.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    messageDraftsKey = 'message_drafts'
    reviewDecisionsKey = 'review_decisions'
    messageDrafts = await L.need messageDraftsKey
    reviewDecisions = await L.need reviewDecisionsKey

    messageDrafts = resolveArtifactPayload(M, experiment, messageDraftsKey, (value) -> Array.isArray(value?.drafts)).value ? messageDrafts
    reviewDecisions = resolveArtifactPayload(M, experiment, reviewDecisionsKey, (value) -> Array.isArray(value?.decisions)).value ? reviewDecisions

    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless Array.isArray(messageDrafts?.drafts)
    throw new Error "[#{stepName}] Missing required artifact '#{reviewDecisionsKey}'" unless Array.isArray(reviewDecisions?.decisions)

    outreachLogArtifact = resolveArtifactPayload(M, experiment, 'outreach_log', (value) -> Array.isArray(value?.entries))
    existingDoc = outreachLogArtifact.value ? {}
    existingEntries = if Array.isArray(existingDoc?.entries) then existingDoc.entries else []
    existingByDraftId = {}
    for entry in existingEntries when normalizeText(entry?.draft_id).length
      existingByDraftId[entry.draft_id] = entry

    decisionsByDraftId = {}
    for entry in reviewDecisions.decisions when normalizeText(entry?.draft_id).length
      decisionsByDraftId[entry.draft_id] = entry

    nextEntries = []
    seen = new Set()

    for draft in messageDrafts.drafts when normalizeText(draft?.draft_id).length
      draftId = draft.draft_id
      seen.add draftId
      base = buildDefaultEntry draft
      existing = existingByDraftId[draftId]
      decision = decisionsByDraftId[draftId]
      merged = if existing? then Object.assign {}, base, existing else base
      merged.organization = draft.organization ? merged.organization ? ''
      merged.audience = draft.audience_label ? draft.audience_key ? merged.audience ? ''
      merged.channel = draft.contact_channel ? merged.channel ? ''
      if normalizeText(merged.response_status).length is 0
        merged.response_status = 'none'
      merged.review_required = true if decision?
      nextEntries.push merged

    for entry in existingEntries when normalizeText(entry?.draft_id).length and not seen.has(entry.draft_id)
      nextEntries.push entry

    payload =
      generated_for: messageDrafts.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: messageDrafts.campaign_source_hash ? null
      entry_count: nextEntries.length
      entries: nextEntries
      summary:
        not_sent: nextEntries.filter((entry) -> String(entry?.status ? 'not_sent') is 'not_sent').length
        sent_manually: nextEntries.filter((entry) -> String(entry?.status ? '') is 'sent_manually').length
        replied: nextEntries.filter((entry) -> String(entry?.status ? '') is 'replied').length
        follow_up_needed: nextEntries.filter((entry) -> String(entry?.status ? '') is 'follow_up_needed').length
        closed: nextEntries.filter((entry) -> String(entry?.status ? '') is 'closed').length

    L.make 'outreach_log', payload
    L.done()
    return
