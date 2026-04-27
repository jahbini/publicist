#!/usr/bin/env coffee

joinLines = (lines) ->
  lines.join("\n").replace(/\n{3,}/g, "\n\n")

decisionBucket = (decision) ->
  value = String(decision?.decision ? '').trim().toLowerCase()
  return 'approved' if decision?.approved_for_send is true or value in ['approved', 'approve']
  return 'rejected' if value in ['rejected', 'reject']
  'pending'

@step =
  desc: 'Write a human review packet for draft-only outreach.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    sourceMaterialKey = 'source_material'
    audienceProfilesKey = 'audience_profiles'
    contactLedgerKey = 'contact_ledger'
    messageDraftsKey = 'message_drafts'
    reviewDecisionsKey = 'review_decisions'
    sqliteLoadReportKey = 'sqlite_load_report'
    nextActionsKey = 'next_actions'
    sqliteInsightsTarget = experiment.artifacts?.sqlite_insights?.target
    sourceMaterial = await L.need sourceMaterialKey
    audienceProfiles = await L.need audienceProfilesKey
    contactLedger = await L.need contactLedgerKey
    messageDrafts = await L.need messageDraftsKey
    reviewDecisions = await L.need reviewDecisionsKey
    sqliteLoadReport = await L.need sqliteLoadReportKey
    nextActions = await L.need nextActionsKey
    sqliteInsights = if sqliteInsightsTarget? then M.theLowdown(sqliteInsightsTarget)?.value else null
    throw new Error "[#{stepName}] Missing required artifact '#{sourceMaterialKey}'" unless sourceMaterial?
    throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}'" unless audienceProfiles?.profiles?
    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless contactLedger?.entries?
    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless messageDrafts?.drafts?
    throw new Error "[#{stepName}] Missing required artifact '#{reviewDecisionsKey}'" unless reviewDecisions?.decisions?
    throw new Error "[#{stepName}] Missing required artifact '#{sqliteLoadReportKey}'" unless sqliteLoadReport?.summary?
    throw new Error "[#{stepName}] Missing required artifact '#{nextActionsKey}'" unless nextActions?.summary?

    reviewers = M.getStepParam(stepName, 'reviewers') ? []
    reviewDeadline = M.getStepParam stepName, 'review_deadline'

    audienceLines = audienceProfiles.profiles.map (profile) ->
      "- #{profile.audience_label}: #{profile.angle}"

    ledgerLines = contactLedger.entries.map (entry) ->
      "- #{entry.audience}: #{entry.organization} / #{entry.contact_name} / #{entry.contact_role} / #{entry.contact_channel} / #{entry.status}"

    decisionLines = reviewDecisions.decisions.map (decision) ->
      "- #{decision.draft_id}: #{decision.contact_name} / #{decision.organization} / #{decision.decision} / approved_for_send=#{decision.approved_for_send}"

    approvedLines = reviewDecisions.decisions
      .filter (decision) -> decisionBucket(decision) is 'approved'
      .map (decision) -> "- #{decision.draft_id}: #{decision.contact_name} / #{decision.organization}"
    pendingLines = reviewDecisions.decisions
      .filter (decision) -> decisionBucket(decision) is 'pending'
      .map (decision) -> "- #{decision.draft_id}: #{decision.contact_name} / #{decision.organization}"
    rejectedLines = reviewDecisions.decisions
      .filter (decision) -> decisionBucket(decision) is 'rejected'
      .map (decision) -> "- #{decision.draft_id}: #{decision.contact_name} / #{decision.organization}"

    sqliteSummaryLines = [
      "- valid: #{sqliteLoadReport.summary.valid}"
      "- audiences: #{sqliteLoadReport.planned_table_row_counts?.audiences ? 0}"
      "- contacts: #{sqliteLoadReport.planned_table_row_counts?.contacts ? 0}"
      "- drafts: #{sqliteLoadReport.planned_table_row_counts?.drafts ? 0}"
      "- review_decisions: #{sqliteLoadReport.planned_table_row_counts?.review_decisions ? 0}"
      "- outreach_events: #{sqliteLoadReport.planned_table_row_counts?.outreach_events ? 0}"
      "- missing_required_fields: #{sqliteLoadReport.summary.missing_required_fields_count ? 0}"
      "- unresolved_joins: #{sqliteLoadReport.summary.unresolved_joins_count ? 0}"
      "- duplicate_ids: #{sqliteLoadReport.summary.duplicate_ids_count ? 0}"
    ]

    sqliteInsightsLines = if sqliteInsights?.summary?
      countsByAudience = if Array.isArray(sqliteInsights.counts_by_audience) then sqliteInsights.counts_by_audience else []
      pendingOutreach = if Array.isArray(sqliteInsights.pending_outreach) then sqliteInsights.pending_outreach else []
      emptyAudiences = if Array.isArray(sqliteInsights.empty_audiences) then sqliteInsights.empty_audiences else []
      recentActivity = if Array.isArray(sqliteInsights.recent_activity) then sqliteInsights.recent_activity else []
      [
        "- db_available: #{sqliteInsights.summary.db_available is true}"
        "- counts_by_audience: #{countsByAudience.length}"
        "- pending_outreach: #{pendingOutreach.length}"
        "- empty_audiences: #{emptyAudiences.length}"
        "- recent_activity: #{recentActivity.length}"
        ""
        "### Counts By Audience"
        ""
        (if countsByAudience.length then countsByAudience.map((row) -> "- #{row.audience_label ? row.audience_key}: #{row.approved_drafts ? 0}").join("\n") else "- none")
        ""
        "### Pending Outreach"
        ""
        (if pendingOutreach.length then pendingOutreach.map((row) -> "- #{row.draft_id}: #{row.contact_name ? 'unknown'} / #{row.organization ? 'unknown'} / reviewed_at=#{row.reviewed_at ? 'n/a'}").join("\n") else "- none")
        ""
        "### Empty Audiences"
        ""
        (if emptyAudiences.length then emptyAudiences.map((row) -> "- #{row.audience_label ? row.audience_key}").join("\n") else "- none")
        ""
        "### Recent Activity"
        ""
        (if recentActivity.length then recentActivity.map((row) -> "- #{row.draft_id}: #{row.reviewed_at ? 'n/a'} / #{row.contact_name ? 'unknown'} / #{row.organization ? 'unknown'}").join("\n") else "- none")
      ]
    else
      [
        "- db_available: false"
        "- sqlite_insights artifact not present"
      ]

    nextActionLines = [
      "- follow_up_contacts: #{nextActions.summary?.follow_up_contacts_count ? 0}"
      "- audiences_to_expand: #{nextActions.summary?.audiences_to_expand_count ? 0}"
      "- drafts_needing_review: #{nextActions.summary?.drafts_needing_review_count ? 0}"
      "- stale_items: #{nextActions.summary?.stale_items_count ? 0}"
      ""
      "### Follow-up Contacts"
      ""
      (if nextActions.follow_up_contacts?.length then nextActions.follow_up_contacts.map((row) -> "- #{row.draft_id}: #{row.contact_name ? 'unknown'} / #{row.organization ? 'unknown'}").join("\n") else "- none")
      ""
      "### Audiences To Expand"
      ""
      (if nextActions.audiences_to_expand?.length then nextActions.audiences_to_expand.map((row) -> "- #{row.audience_label ? row.audience_key}").join("\n") else "- none")
      ""
      "### Drafts Needing Review"
      ""
      (if nextActions.drafts_needing_review?.length then nextActions.drafts_needing_review.map((row) -> "- #{row.draft_id}: #{row.contact_name ? 'unknown'} / #{row.organization ? 'unknown'}").join("\n") else "- none")
      ""
      "### Stale Items"
      ""
      (if nextActions.stale_items?.length then nextActions.stale_items.map((row) -> "- #{row.draft_id}: age=#{row.age_days ? 'n/a'}d / #{row.contact_name ? 'unknown'} / #{row.organization ? 'unknown'}").join("\n") else "- none")
    ]

    draftLines = messageDrafts.drafts.map (draft) ->
      [
        "## #{draft.audience_label}"
        ""
        "Draft ID: #{draft.draft_id ? 'TBD'}"
        "Organization: #{draft.organization ? 'TBD'}"
        "Contact: #{draft.contact_name ? 'TBD'}#{if draft.contact_role? then " (#{draft.contact_role})" else ''}"
        "Channel: #{draft.contact_channel ? 'TBD'}"
        ""
        "Subject: #{draft.subject}"
        ""
        "#{draft.email_body}"
        ""
        "Follow-up note: #{draft.follow_up_note}"
      ].join("\n")

    packet = joinLines([
      "# Publicist Review Packet"
      ""
      "Campaign: #{sourceMaterial.campaign_name}"
      "Brand: #{sourceMaterial.brand_name}"
      "Launch city: #{sourceMaterial.launch_city ? 'TBD'}"
      "Announcement date: #{sourceMaterial.announcement_date ? 'TBD'}"
      "Review owner: #{experiment.run?.review_owner ? 'unassigned'}"
      "Review deadline: #{reviewDeadline ? 'TBD'}"
      ""
      "## Review Gates"
      ""
      "- Human review required before outreach."
      "- No network posting from this recipe."
      "- No email sending from this recipe."
      "- No direct OS or CLI actions from the agent layer."
      ""
      "## Assigned Reviewers"
      ""
      (if reviewers.length then reviewers.map((name) -> "- #{name}").join("\n") else "- none listed")
      ""
      "## Source Highlights"
      ""
      (sourceMaterial.highlights ? []).map((line) -> "- #{line}").join("\n")
      ""
      "## Audience Angles"
      ""
      audienceLines.join("\n")
      ""
      "## Contact Ledger"
      ""
      ledgerLines.join("\n")
      ""
      "## Review Decisions"
      ""
      "Approved: #{approvedLines.length}"
      "Pending: #{pendingLines.length}"
      "Rejected: #{rejectedLines.length}"
      ""
      "### Approved"
      ""
      (if approvedLines.length then approvedLines.join("\n") else "- none")
      ""
      "### Pending"
      ""
      (if pendingLines.length then pendingLines.join("\n") else "- none")
      ""
      "### Rejected"
      ""
      (if rejectedLines.length then rejectedLines.join("\n") else "- none")
      ""
      "### Detailed Decisions"
      ""
      decisionLines.join("\n")
      ""
      "## SQLite Load Report"
      ""
      sqliteSummaryLines.join("\n")
      ""
      "## SQLite Insights"
      ""
      sqliteInsightsLines.join("\n")
      ""
      "## Next Actions"
      ""
      nextActionLines.join("\n")
      ""
      "## Draft Messages"
      ""
      draftLines.join("\n\n")
    ])

    L.make 'review_packet', packet
    L.done()
    return
