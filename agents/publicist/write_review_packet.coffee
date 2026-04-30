#!/usr/bin/env coffee

joinLines = (lines) ->
  lines.join("\n").replace(/\n{3,}/g, "\n\n")

decisionBucket = (decision) ->
  value = String(decision?.decision ? '').trim().toLowerCase()
  return 'approved' if decision?.approved_for_send is true or value in ['approved', 'approve']
  return 'rejected' if value in ['rejected', 'reject']
  'pending'

resolveArtifactPayload = (M, experiment, artifactKey, validator) ->
  value = M.theLowdown(artifactKey)?.value
  return { value, key: artifactKey } if validator(value)

  targetKey = experiment?.artifacts?[artifactKey]?.target
  targetValue = M.theLowdown(targetKey)?.value
  return { value: targetValue, key: targetKey } if targetKey? and validator(targetValue)

  { value, key: artifactKey, targetKey, targetValue }

@step =
  desc: 'Write a human review packet for draft-only outreach.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    sourceMaterialKey = 'source_material'
    audienceSuggestionsKey = 'audience_suggestions'
    audienceProfilesKey = 'audience_profiles'
    contactLedgerKey = 'contact_ledger_enriched'
    messageDraftsKey = 'message_drafts'
    reviewDecisionsKey = 'review_decisions'
    outreachLogKey = 'outreach_log'
    sqliteLoadReportKey = 'sqlite_load_report'
    nextActionsKey = 'next_actions'
    researchRequestsKey = 'research_requests'
    researchResultsKey = 'research_results'
    targetCandidatesKey = 'target_candidates'
    qualifiedTargetsKey = 'qualified_targets'
    contactPageResultsKey = 'contact_page_results'
    enrichedDraftsKey = 'enriched_drafts'
    sqliteInsightsTarget = experiment.artifacts?.sqlite_insights?.target
    sourceMaterial = await L.need sourceMaterialKey
    audienceSuggestions = await L.need audienceSuggestionsKey
    audienceProfiles = await L.need audienceProfilesKey
    contactLedger = await L.need contactLedgerKey
    messageDrafts = await L.need messageDraftsKey
    reviewDecisions = await L.need reviewDecisionsKey
    outreachLog = await L.need outreachLogKey
    sqliteLoadReport = await L.need sqliteLoadReportKey
    nextActions = await L.need nextActionsKey
    researchRequests = await L.need researchRequestsKey
    researchResults = await L.need researchResultsKey
    targetCandidates = await L.need targetCandidatesKey
    qualifiedTargets = await L.need qualifiedTargetsKey
    contactPageResults = await L.need contactPageResultsKey
    enrichedDrafts = await L.need enrichedDraftsKey
    sqliteInsights = if sqliteInsightsTarget? then M.theLowdown(sqliteInsightsTarget)?.value else null
    audienceSuggestions = resolveArtifactPayload(M, experiment, audienceSuggestionsKey, (value) -> Array.isArray(value?.audience_suggestions)).value ? audienceSuggestions
    audienceProfiles = resolveArtifactPayload(M, experiment, audienceProfilesKey, (value) -> Array.isArray(value?.profiles)).value ? audienceProfiles
    contactLedger = resolveArtifactPayload(M, experiment, contactLedgerKey, (value) -> Array.isArray(value?.entries)).value ? contactLedger
    messageDrafts = resolveArtifactPayload(M, experiment, messageDraftsKey, (value) -> Array.isArray(value?.drafts)).value ? messageDrafts
    reviewDecisions = resolveArtifactPayload(M, experiment, reviewDecisionsKey, (value) -> Array.isArray(value?.decisions)).value ? reviewDecisions
    outreachLog = resolveArtifactPayload(M, experiment, outreachLogKey, (value) -> Array.isArray(value?.entries)).value ? outreachLog
    sqliteLoadReport = resolveArtifactPayload(M, experiment, sqliteLoadReportKey, (value) -> value?.summary?).value ? sqliteLoadReport
    nextActions = resolveArtifactPayload(M, experiment, nextActionsKey, (value) -> value?.summary?).value ? nextActions
    researchRequests = resolveArtifactPayload(M, experiment, researchRequestsKey, (value) -> Array.isArray(value?.research_requests)).value ? researchRequests
    researchResults = resolveArtifactPayload(M, experiment, researchResultsKey, (value) -> Array.isArray(value?.results)).value ? researchResults
    targetCandidates = resolveArtifactPayload(M, experiment, targetCandidatesKey, (value) -> value?.target_candidates?).value ? targetCandidates
    qualifiedTargets = resolveArtifactPayload(M, experiment, qualifiedTargetsKey, (value) -> Array.isArray(value?.qualified_targets)).value ? qualifiedTargets
    contactPageResults = resolveArtifactPayload(M, experiment, contactPageResultsKey, (value) -> Array.isArray(value?.results)).value ? contactPageResults
    enrichedDrafts = resolveArtifactPayload(M, experiment, enrichedDraftsKey, (value) -> Array.isArray(value?.enriched_drafts)).value ? enrichedDrafts

    throw new Error "[#{stepName}] Missing required artifact '#{sourceMaterialKey}'" unless sourceMaterial?
    throw new Error "[#{stepName}] Missing required artifact '#{audienceSuggestionsKey}'" unless Array.isArray(audienceSuggestions?.audience_suggestions)
    throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}'" unless audienceProfiles?.profiles?
    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless contactLedger?.entries?
    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless messageDrafts?.drafts?
    throw new Error "[#{stepName}] Missing required artifact '#{reviewDecisionsKey}'" unless reviewDecisions?.decisions?
    throw new Error "[#{stepName}] Missing required artifact '#{outreachLogKey}'" unless Array.isArray(outreachLog?.entries)
    throw new Error "[#{stepName}] Missing required artifact '#{sqliteLoadReportKey}'" unless sqliteLoadReport?.summary?
    throw new Error "[#{stepName}] Missing required artifact '#{nextActionsKey}'" unless nextActions?.summary?
    throw new Error "[#{stepName}] Missing required artifact '#{researchRequestsKey}'" unless Array.isArray(researchRequests?.research_requests)
    throw new Error "[#{stepName}] Missing required artifact '#{researchResultsKey}'" unless Array.isArray(researchResults?.results)
    throw new Error "[#{stepName}] Missing required artifact '#{targetCandidatesKey}'" unless targetCandidates?.target_candidates?
    throw new Error "[#{stepName}] Missing required artifact '#{qualifiedTargetsKey}'" unless Array.isArray(qualifiedTargets?.qualified_targets)
    throw new Error "[#{stepName}] Missing required artifact '#{contactPageResultsKey}'" unless Array.isArray(contactPageResults?.results)
    throw new Error "[#{stepName}] Missing required artifact '#{enrichedDraftsKey}'" unless Array.isArray(enrichedDrafts?.enriched_drafts)

    reviewers = M.getStepParam(stepName, 'reviewers') ? []
    reviewDeadline = M.getStepParam stepName, 'review_deadline'

    audienceLines = audienceProfiles.profiles.map (profile) ->
      "- #{profile.audience_label}: #{profile.angle}"

    audienceSuggestionLines = [
      "- suggestion_count: #{audienceSuggestions.summary?.suggestion_count ? audienceSuggestions.audience_suggestions.length ? 0}"
      "- configured_priority_count: #{audienceSuggestions.summary?.configured_priority_count ? 0}"
      "- suggestion_only: #{audienceSuggestions.summary?.suggestion_only is true}"
      ""
      (if audienceSuggestions.audience_suggestions.length then audienceSuggestions.audience_suggestions.map((row) ->
        [
          "- #{row.name}: #{row.description ? ''}"
          "  rationale=#{row.rationale ? ''}"
          "  example_targets=#{(row.example_targets ? []).join(' | ')}"
        ].join("\n")
      ).join("\n") else "- none")
    ]

    ledgerLines = contactLedger.entries.map (entry) ->
      "- #{entry.audience}: #{entry.organization} / #{entry.contact_name} / #{entry.contact_role} / #{entry.contact_channel} / #{entry.status}"

    qualifiedLedgerLines = contactLedger.entries
      .filter (entry) -> String(entry?.status ? '') is 'target_qualified'
      .map (entry) ->
        [
          "- #{entry.audience}: #{entry.organization} / #{entry.contact_role} / #{entry.contact_channel} / source_candidate_id=#{entry.source_candidate_id ? 'n/a'}"
          "  contact_page_url=#{entry.contact_page_url ? 'n/a'}"
          "  discovered_emails=#{(entry.discovered_emails ? []).join(' | ') or 'none'}"
          "  discovered_contact_forms=#{(entry.discovered_contact_forms ? []).map((item) -> "#{item.method ? 'GET'} #{item.url ? ''}").join(' | ') or 'none'}"
          "  discovered_social_links=#{(entry.discovered_social_links ? []).join(' | ') or 'none'}"
          "  contact_discovery_status=#{entry.contact_discovery_status ? 'n/a'}"
          "  contact_discovery_notes=#{entry.contact_discovery_notes ? 'n/a'}"
        ].join("\n")

    placeholderLedgerLines = contactLedger.entries
      .filter (entry) -> String(entry?.status ? '') isnt 'target_qualified'
      .map (entry) -> "- #{entry.audience}: #{entry.organization} / #{entry.contact_name} / #{entry.contact_role} / #{entry.contact_channel} / #{entry.status}"

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

    researchRequestLines = [
      "- request_count: #{researchRequests.request_count ? researchRequests.research_requests.length ? 0}"
      "- planned_only: #{researchRequests.summary?.planned_only is true}"
      ""
      (if researchRequests.research_requests.length then researchRequests.research_requests.map((row) ->
        [
          "- #{row.request_id}: #{row.research_goal}"
          "  audience=#{row.audience ? 'n/a'}"
          "  organization=#{row.organization ? 'n/a'}"
          "  contact_name=#{row.contact_name ? 'n/a'}"
          "  search_terms=#{(row.suggested_search_terms ? []).join(' | ')}"
          "  allowed_domains=#{(row.allowed_domains ? []).join(' | ')}"
          "  status=#{row.status ? 'n/a'} review_required=#{row.review_required}"
        ].join("\n")
      ).join("\n") else "- none")
    ]

    researchResultLines = [
      "- approved_request_count: #{researchResults.summary?.approved_request_count ? 0}"
      "- fetched_result_count: #{researchResults.summary?.fetched_result_count ? 0}"
      "- skipped_count: #{researchResults.summary?.skipped_count ? 0}"
      ""
      "### Fetched Results"
      ""
      (if researchResults.results.length then researchResults.results.map((row) ->
        [
          "- #{row.request_id}: #{row.url}"
          "  status_code=#{row.status_code ? 'n/a'} fetched_at=#{row.fetched_at ? 'n/a'}"
          "  title=#{row.title ? ''}"
          "  excerpt=#{row.short_text_excerpt ? ''}"
          "  errors=#{(row.errors ? []).join(' | ')}"
        ].join("\n")
      ).join("\n") else "- none")
      ""
      "### Skipped Requests"
      ""
      (if researchResults.skipped?.length then researchResults.skipped.map((row) -> "- #{row.request_id}: #{row.reason ? 'unknown'}").join("\n") else "- none")
    ]

    groupedTargetCandidates = targetCandidates.groups_by_audience ? {}
    if not Object.keys(groupedTargetCandidates).length and Array.isArray(targetCandidates.target_candidates)
      for row in targetCandidates.target_candidates when row?.audience?
        groupedTargetCandidates[row.audience] ?= []
        groupedTargetCandidates[row.audience].push row

    targetCandidateLines = [
      "- total_candidates: #{targetCandidates.summary?.total_candidates ? targetCandidates.target_candidates?.length ? 0}"
      "- suggestion_only: #{targetCandidates.summary?.suggestion_only is true}"
      "- by_target_type: #{Object.entries(targetCandidates.summary?.by_target_type ? {}).map(([k, v]) -> "#{k}=#{v}").join(' | ') or 'none'}"
      "- by_confidence: #{Object.entries(targetCandidates.summary?.by_confidence ? {}).map(([k, v]) -> "#{k}=#{v}").join(' | ') or 'none'}"
      ""
      (if Object.keys(groupedTargetCandidates).length then Object.keys(groupedTargetCandidates).sort().map((audienceKey) ->
        rows = (groupedTargetCandidates[audienceKey] ? []).slice().sort((a, b) ->
          confidenceRank =
            high: 3
            medium: 2
            low: 1
          (confidenceRank[b?.confidence] ? 0) - (confidenceRank[a?.confidence] ? 0)
        ).slice(0, 5)
        [
          "### #{audienceKey}"
          ""
          "- candidate_count: #{groupedTargetCandidates[audienceKey]?.length ? 0}"
          (if rows.length then rows.map((row) -> "- #{row.organization_name ? 'unknown'} / #{row.target_type ? 'unknown'} / #{row.website ? 'n/a'} / #{row.confidence ? 'low'} / #{row.relevance_reason ? ''}").join("\n") else "- none")
        ].join("\n")
      ).join("\n\n") else "- none")
    ]

    qualifiedTargetLines = [
      "- total_qualified_targets: #{qualifiedTargets.summary?.total_qualified_targets ? qualifiedTargets.qualified_targets.length ? 0}"
      "- by_audience: #{Object.entries(qualifiedTargets.summary?.by_audience ? {}).map(([k, v]) -> "#{k}=#{v}").join(' | ') or 'none'}"
      ""
      (if qualifiedTargets.qualified_targets.length then qualifiedTargets.qualified_targets.map((row) -> "- #{row.organization_name ? 'unknown'} / #{row.audience ? 'n/a'} / #{row.website ? 'n/a'} / notes=#{row.reviewer_notes ? ''}").join("\n") else "- none")
    ]

    contactPageResultLines = [
      "- approved_url_count: #{contactPageResults.summary?.approved_url_count ? 0}"
      "- fetched_result_count: #{contactPageResults.summary?.fetched_result_count ? 0}"
      "- skipped_count: #{contactPageResults.summary?.skipped_count ? 0}"
      ""
      "### Fetched Contact Pages"
      ""
      (if contactPageResults.results.length then contactPageResults.results.map((row) ->
        [
          "- #{row.organization_name ? 'unknown'} / #{row.url}"
          "  status_code=#{row.status_code ? 'n/a'} fetched_at=#{row.fetched_at ? 'n/a'}"
          "  page_title=#{row.page_title ? ''}"
          "  emails=#{(row.found_emails ? []).join(' | ') or 'none'}"
          "  contact_forms=#{(row.found_contact_forms ? []).map((item) -> "#{item.method ? 'GET'} #{item.url ? ''}").join(' | ') or 'none'}"
          "  social_links=#{(row.found_social_links ? []).join(' | ') or 'none'}"
          "  excerpt=#{row.clean_text_excerpt ? ''}"
          "  errors=#{(row.errors ? []).join(' | ') or 'none'}"
        ].join("\n")
      ).join("\n") else "- none")
      ""
      "### Skipped Contact Pages"
      ""
      (if contactPageResults.skipped?.length then contactPageResults.skipped.map((row) -> "- #{row.request_id ? 'unknown'} / #{row.url ? 'n/a'}: #{row.reason ? 'unknown'}").join("\n") else "- none")
    ]

    outreachLogLines = [
      "- not_sent: #{outreachLog.summary?.not_sent ? 0}"
      "- sent_manually: #{outreachLog.summary?.sent_manually ? 0}"
      "- replied: #{outreachLog.summary?.replied ? 0}"
      "- follow_up_needed: #{outreachLog.summary?.follow_up_needed ? 0}"
      "- closed: #{outreachLog.summary?.closed ? 0}"
      ""
      (if outreachLog.entries.length then outreachLog.entries.map((row) ->
        [
          "- #{row.draft_id}: #{row.organization ? 'unknown'} / #{row.audience ? 'n/a'} / #{row.channel ? 'n/a'}"
          "  status=#{row.status ? 'not_sent'} sent_manually_at=#{row.sent_manually_at ? 'n/a'}"
          "  response_status=#{row.response_status ? 'none'} follow_up_date=#{row.follow_up_date ? 'n/a'}"
          "  notes=#{row.notes ? ''}"
        ].join("\n")
      ).join("\n") else "- none")
    ]

    enrichmentLines = [
      "- drafts_with_research: #{enrichedDrafts.summary?.drafts_with_research ? 0}"
      "- drafts_without_research: #{enrichedDrafts.summary?.drafts_without_research ? 0}"
      "- suggestions_only: #{enrichedDrafts.summary?.suggestions_only is true}"
      ""
      (if enrichedDrafts.enriched_drafts.length then enrichedDrafts.enriched_drafts.map((row) ->
        [
          "### #{row.draft_id}"
          ""
          "- audience: #{row.audience_label ? 'n/a'}"
          "- organization: #{row.organization ? 'n/a'}"
          "- contact_name: #{row.contact_name ? 'n/a'}"
          "- decision: #{row.decision ? 'n/a'}"
          "- approved_for_send: #{row.approved_for_send is true}"
          "- matched_result_count: #{row.matched_result_count ? 0}"
          "- matched_request_ids: #{(row.matched_request_ids ? []).join(' | ') or 'none'}"
          ""
          "#### Suggested Improvements"
          ""
          (if row.suggested_improvements?.length then row.suggested_improvements.map((item) -> "- #{item}").join("\n") else "- none")
          ""
          "#### Additional Talking Points"
          ""
          (if row.additional_talking_points?.length then row.additional_talking_points.map((item) -> "- #{item}").join("\n") else "- none")
          ""
          "#### Relevant Facts"
          ""
          (if row.relevant_facts?.length then row.relevant_facts.map((item) -> "- #{item}").join("\n") else "- none")
        ].join("\n")
      ).join("\n\n") else "- none")
    ]

    draftLines = messageDrafts.drafts.map (draft) ->
      [
        "## #{draft.audience_label}"
        ""
        "Draft ID: #{draft.draft_id ? 'TBD'}"
        "Organization: #{draft.organization ? 'TBD'}"
        "Contact: #{draft.contact_name ? 'TBD'}#{if draft.contact_role? then " (#{draft.contact_role})" else ''}"
        "Channel: #{draft.contact_channel ? 'TBD'}"
        "Target Website: #{draft.target_website ? 'TBD'}"
        "Target Type: #{draft.target_type ? 'TBD'}"
        "Target Rationale: #{draft.target_rationale ? 'TBD'}"
        "Contact Page URL: #{draft.contact_page_url ? 'TBD'}"
        "Discovered Contact Forms: #{(draft.discovered_contact_forms ? []).map((item) -> "#{item.method ? 'GET'} #{item.url ? ''}").join(' | ') or 'none'}"
        "Discovered Social Links: #{(draft.discovered_social_links ? []).join(' | ') or 'none'}"
        "Context Notes: #{(draft.context_notes ? []).join(' | ') or 'none'}"
        "Why This Target May Care: #{(draft.why_this_target_may_care ? []).join(' | ') or 'none'}"
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
      "## Suggested Audiences"
      ""
      audienceSuggestionLines.join("\n")
      ""
      "## Contact Ledger"
      ""
      "- total_entries: #{contactLedger.entries.length}"
      "- qualified_targets: #{qualifiedLedgerLines.length}"
      "- placeholders: #{placeholderLedgerLines.length}"
      ""
      "### Qualified Targets"
      ""
      (if qualifiedLedgerLines.length then qualifiedLedgerLines.join("\n") else "- none")
      ""
      "### Placeholder Targets"
      ""
      (if placeholderLedgerLines.length then placeholderLedgerLines.join("\n") else "- none")
      ""
      "### All Ledger Entries"
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
      "## Outreach Log"
      ""
      outreachLogLines.join("\n")
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
      "## Research Requests"
      ""
      researchRequestLines.join("\n")
      ""
      "## Research Results"
      ""
      researchResultLines.join("\n")
      ""
      "## Target Candidates"
      ""
      targetCandidateLines.join("\n")
      ""
      "## Qualified Targets"
      ""
      qualifiedTargetLines.join("\n")
      ""
      "## Contact Page Results"
      ""
      contactPageResultLines.join("\n")
      ""
      "## Research-Enhanced Suggestions"
      ""
      enrichmentLines.join("\n")
      ""
      "## Draft Messages"
      ""
      draftLines.join("\n\n")
    ])

    L.make 'review_packet', packet
    L.done()
    return
