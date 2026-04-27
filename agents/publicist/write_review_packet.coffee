#!/usr/bin/env coffee

joinLines = (lines) ->
  lines.join("\n").replace(/\n{3,}/g, "\n\n")

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
    sourceMaterial = await L.need sourceMaterialKey
    audienceProfiles = await L.need audienceProfilesKey
    contactLedger = await L.need contactLedgerKey
    messageDrafts = await L.need messageDraftsKey
    reviewDecisions = await L.need reviewDecisionsKey
    sqliteLoadReport = await L.need sqliteLoadReportKey
    throw new Error "[#{stepName}] Missing required artifact '#{sourceMaterialKey}'" unless sourceMaterial?
    throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}'" unless audienceProfiles?.profiles?
    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless contactLedger?.entries?
    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless messageDrafts?.drafts?
    throw new Error "[#{stepName}] Missing required artifact '#{reviewDecisionsKey}'" unless reviewDecisions?.decisions?
    throw new Error "[#{stepName}] Missing required artifact '#{sqliteLoadReportKey}'" unless sqliteLoadReport?.summary?

    reviewers = M.getStepParam(stepName, 'reviewers') ? []
    reviewDeadline = M.getStepParam stepName, 'review_deadline'

    audienceLines = audienceProfiles.profiles.map (profile) ->
      "- #{profile.audience_label}: #{profile.angle}"

    ledgerLines = contactLedger.entries.map (entry) ->
      "- #{entry.audience}: #{entry.organization} / #{entry.contact_name} / #{entry.contact_role} / #{entry.contact_channel} / #{entry.status}"

    decisionLines = reviewDecisions.decisions.map (decision) ->
      "- #{decision.draft_id}: #{decision.contact_name} / #{decision.organization} / #{decision.decision} / approved_for_send=#{decision.approved_for_send}"

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
      decisionLines.join("\n")
      ""
      "## SQLite Load Report"
      ""
      sqliteSummaryLines.join("\n")
      ""
      "## Draft Messages"
      ""
      draftLines.join("\n\n")
    ])

    L.make 'review_packet', packet
    L.done()
    return
