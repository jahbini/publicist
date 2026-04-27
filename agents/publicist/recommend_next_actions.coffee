#!/usr/bin/env coffee

isBlank = (value) ->
  String(value ? '').trim().length is 0

daysBetween = (olderIso, newerDate = new Date()) ->
  older = new Date(olderIso)
  return null if Number.isNaN(older.getTime())
  Math.floor((newerDate.getTime() - older.getTime()) / (24 * 60 * 60 * 1000))

@step =
  desc: 'Suggest next publicist actions from SQLite insights and current artifacts.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    sqliteInsightsKey = 'sqlite_insights'
    contactLedgerKey = 'contact_ledger'
    reviewDecisionsKey = 'review_decisions'

    sqliteInsights = await L.need sqliteInsightsKey
    contactLedger = await L.need contactLedgerKey
    reviewDecisions = await L.need reviewDecisionsKey

    throw new Error "[#{stepName}] Missing required artifact '#{sqliteInsightsKey}'" unless sqliteInsights?
    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless contactLedger?.entries?
    throw new Error "[#{stepName}] Missing required artifact '#{reviewDecisionsKey}'" unless reviewDecisions?.decisions?

    staleAfterDays = Number(M.getStepParam(stepName, 'stale_after_days') ? 14)
    now = new Date()

    followUpContacts = (sqliteInsights.pending_outreach ? []).map (row) ->
      draft_id: row.draft_id
      audience_label: row.audience_label ? ''
      organization: row.organization ? ''
      contact_name: row.contact_name ? ''
      reviewed_at: row.reviewed_at ? null
      recommendation: 'Prepare reviewed follow-up plan only; no send action in this phase.'

    audiencesToExpand = (sqliteInsights.empty_audiences ? []).map (row) ->
      audience_key: row.audience_key ? ''
      audience_label: row.audience_label ? ''
      recommendation: 'Add or improve approved draft coverage for this audience.'

    draftsNeedingReview = reviewDecisions.decisions
      .filter (decision) -> String(decision?.decision ? '').trim().toLowerCase() is 'pending_review'
      .map (decision) ->
        draft_id: decision.draft_id ? ''
        contact_name: decision.contact_name ? ''
        organization: decision.organization ? ''
        recommendation: 'Human review still pending.'

    staleItems = []
    for decision in reviewDecisions.decisions when not isBlank(decision?.reviewed_at)
      ageDays = daysBetween decision.reviewed_at, now
      continue unless ageDays? and ageDays >= staleAfterDays
      staleItems.push
        draft_id: decision.draft_id ? ''
        contact_name: decision.contact_name ? ''
        organization: decision.organization ? ''
        decision: decision.decision ? ''
        reviewed_at: decision.reviewed_at
        age_days: ageDays
        recommendation: 'Recheck whether this reviewed item still reflects current priorities.'

    payload =
      generated_for: experiment.run?.campaign_name
      follow_up_contacts: followUpContacts
      audiences_to_expand: audiencesToExpand
      drafts_needing_review: draftsNeedingReview
      stale_items: staleItems
      summary:
        db_available: sqliteInsights.summary?.db_available is true
        follow_up_contacts_count: followUpContacts.length
        audiences_to_expand_count: audiencesToExpand.length
        drafts_needing_review_count: draftsNeedingReview.length
        stale_items_count: staleItems.length
        stale_after_days: staleAfterDays

    L.make 'next_actions', payload
    L.done()
    return
