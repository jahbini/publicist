#!/usr/bin/env coffee

freshDecision = (draft, fallbackId) ->
  draft_id: draft.draft_id ? fallbackId
  contact_name: draft.contact_name ? ''
  organization: draft.organization ? ''
  decision: 'pending_review'
  reviewer_notes: ""
  approved_for_send: false
  reviewed_at: null
  updated_at: new Date().toISOString()

@step =
  desc: 'Initialize draft-only human review decisions for outreach drafts.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    messageDraftsKey = 'message_drafts'
    messageDrafts = await L.need messageDraftsKey
    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless messageDrafts?.drafts?
    currentSourceHash = String(messageDrafts?.campaign_source_hash ? '')

    reviewDecisionsTarget = experiment.artifacts?.review_decisions?.target
    existingDoc = if reviewDecisionsTarget? then M.theLowdown(reviewDecisionsTarget)?.value else null
    existingDecisions = if Array.isArray(existingDoc?.decisions) then existingDoc.decisions else []
    existingByDraftId = {}
    for entry in existingDecisions when entry?.draft_id?
      existingByDraftId[entry.draft_id] = entry

    decisions = messageDrafts.drafts.map (draft, index) ->
      draftId = draft.draft_id ? "draft_#{index + 1}"
      defaultEntry = freshDecision(draft, draftId)
      existingEntry = existingByDraftId[draftId]
      sameCampaign = String(existingEntry?.campaign_source_hash ? '') is currentSourceHash and currentSourceHash.length > 0
      merged = if sameCampaign then Object.assign {}, defaultEntry, existingEntry else defaultEntry
      merged.draft_id = draftId
      merged.campaign_source_hash = currentSourceHash or null
      merged.contact_name = draft.contact_name ? merged.contact_name ? ''
      merged.organization = draft.organization ? merged.organization ? ''
      merged.updated_at = defaultEntry.updated_at unless sameCampaign and existingEntry?.updated_at?
      merged

    for entry in existingDecisions when entry?.draft_id? and not decisions.some((row) -> row.draft_id is entry.draft_id)
      continue unless String(entry?.campaign_source_hash ? '') is currentSourceHash and currentSourceHash.length > 0
      decisions.push entry

    payload =
      generated_for: messageDrafts.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: currentSourceHash or null
      decision_count: decisions.length
      decisions: decisions
      notes:
        draft_only: true
        no_live_actions: true

    L.make 'review_decisions', payload
    L.done()
    return
