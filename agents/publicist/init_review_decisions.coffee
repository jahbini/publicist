#!/usr/bin/env coffee

@step =
  desc: 'Initialize draft-only human review decisions for outreach drafts.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    messageDraftsKey = 'message_drafts'
    messageDrafts = await L.need messageDraftsKey
    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless messageDrafts?.drafts?

    decisions = messageDrafts.drafts.map (draft, index) ->
      draft_id: draft.draft_id ? "draft_#{index + 1}"
      contact_name: draft.contact_name ? ''
      organization: draft.organization ? ''
      decision: 'pending_review'
      reviewer_notes: ""
      approved_for_send: false
      reviewed_at: null

    payload =
      generated_for: experiment.run?.campaign_name
      decision_count: decisions.length
      decisions: decisions
      notes:
        draft_only: true
        no_live_actions: true

    L.make 'review_decisions', payload
    L.done()
    return
