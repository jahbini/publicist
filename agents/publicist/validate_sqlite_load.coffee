#!/usr/bin/env coffee

isBlank = (value) ->
  String(value ? '').trim().length is 0

pushMissing = (issues, tableName, rowKey, fieldName) ->
  issues.push
    table: tableName
    row: rowKey
    field: fieldName
    issue: 'missing_required_field'

pushJoin = (issues, tableName, rowKey, joinName, detail) ->
  issues.push
    table: tableName
    row: rowKey
    join: joinName
    issue: 'unresolved_join'
    detail: detail

pushDuplicate = (issues, tableName, idField, idValue) ->
  issues.push
    table: tableName
    field: idField
    value: idValue
    issue: 'duplicate_id'

@step =
  desc: 'Dry-run validator for future publicist SQLite loads.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    audienceProfilesKey = 'audience_profiles'
    contactLedgerKey = 'contact_ledger'
    messageDraftsKey = 'message_drafts'
    reviewDecisionsKey = 'review_decisions'

    audienceProfiles = await L.need audienceProfilesKey
    contactLedger = await L.need contactLedgerKey
    messageDrafts = await L.need messageDraftsKey
    reviewDecisions = await L.need reviewDecisionsKey

    throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}'" unless audienceProfiles?.profiles?
    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless contactLedger?.entries?
    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless messageDrafts?.drafts?
    throw new Error "[#{stepName}] Missing required artifact '#{reviewDecisionsKey}'" unless reviewDecisions?.decisions?

    missingRequiredFields = []
    unresolvedJoins = []
    duplicateIds = []

    audienceByKey = {}
    audienceByLabel = {}
    for profile in audienceProfiles.profiles
      rowKey = profile.audience_key ? profile.audience_label ? 'unknown_audience'
      pushMissing missingRequiredFields, 'audiences', rowKey, 'audience_key' if isBlank(profile.audience_key)
      pushMissing missingRequiredFields, 'audiences', rowKey, 'audience_label' if isBlank(profile.audience_label)
      audienceByKey[profile.audience_key] = profile if profile.audience_key?
      audienceByLabel[profile.audience_label] = profile if profile.audience_label?

    contactIdentitySeen = new Set()
    contactByIdentity = {}
    for entry in contactLedger.entries
      rowKey = "#{entry.organization ? 'unknown_org'}::#{entry.contact_name ? 'unknown_contact'}"
      pushMissing missingRequiredFields, 'contacts', rowKey, 'audience' if isBlank(entry.audience)
      pushMissing missingRequiredFields, 'contacts', rowKey, 'organization' if isBlank(entry.organization)
      pushMissing missingRequiredFields, 'contacts', rowKey, 'contact_channel' if isBlank(entry.contact_channel)

      matchedAudience = audienceByLabel[entry.audience]
      unless matchedAudience?
        pushJoin unresolvedJoins, 'contacts', rowKey, 'audiences', "No audience_profiles row for audience label '#{entry.audience}'"

      if contactIdentitySeen.has(rowKey)
        pushDuplicate duplicateIds, 'contacts', 'organization+contact_name', rowKey
      else
        contactIdentitySeen.add rowKey
        contactByIdentity[rowKey] = entry

    draftIdSeen = new Set()
    draftById = {}
    for draft in messageDrafts.drafts
      draftKey = draft.draft_id ? draft.subject ? 'unknown_draft'
      pushMissing missingRequiredFields, 'drafts', draftKey, 'draft_id' if isBlank(draft.draft_id)
      pushMissing missingRequiredFields, 'drafts', draftKey, 'audience_key' if isBlank(draft.audience_key)
      pushMissing missingRequiredFields, 'drafts', draftKey, 'subject' if isBlank(draft.subject)

      matchedAudience = audienceByKey[draft.audience_key] ? audienceByLabel[draft.audience_label]
      unless matchedAudience?
        pushJoin unresolvedJoins, 'drafts', draftKey, 'audiences', "No audience row for draft audience '#{draft.audience_key ? draft.audience_label}'"

      contactIdentity = "#{draft.organization ? 'unknown_org'}::#{draft.contact_name ? 'unknown_contact'}"
      unless contactByIdentity[contactIdentity]?
        pushJoin unresolvedJoins, 'drafts', draftKey, 'contacts', "No contact_ledger row for '#{contactIdentity}'"

      if draftIdSeen.has(draft.draft_id)
        pushDuplicate duplicateIds, 'drafts', 'draft_id', draft.draft_id
      else if draft.draft_id?
        draftIdSeen.add draft.draft_id
        draftById[draft.draft_id] = draft

    decisionDraftSeen = new Set()
    for decision in reviewDecisions.decisions
      rowKey = decision.draft_id ? 'unknown_decision'
      pushMissing missingRequiredFields, 'review_decisions', rowKey, 'draft_id' if isBlank(decision.draft_id)
      pushMissing missingRequiredFields, 'review_decisions', rowKey, 'decision' if isBlank(decision.decision)

      unless draftById[decision.draft_id]?
        pushJoin unresolvedJoins, 'review_decisions', rowKey, 'drafts', "No message_drafts row for draft_id '#{decision.draft_id}'"

      if decisionDraftSeen.has(decision.draft_id)
        pushDuplicate duplicateIds, 'review_decisions', 'draft_id', decision.draft_id
      else if decision.draft_id?
        decisionDraftSeen.add decision.draft_id

    plannedRowCounts =
      audiences: audienceProfiles.profiles.length
      contacts: contactLedger.entries.length
      drafts: messageDrafts.drafts.length
      review_decisions: reviewDecisions.decisions.length
      outreach_events: 0

    wouldInsert =
      audiences: audienceProfiles.profiles.map (profile) -> profile.audience_key
      contacts: contactLedger.entries.map (entry) -> "#{entry.organization}::#{entry.contact_name}"
      drafts: messageDrafts.drafts.map (draft) -> draft.draft_id
      review_decisions: reviewDecisions.decisions.map (decision) -> decision.draft_id
      outreach_events: []

    report =
      generated_for: experiment.run?.campaign_name
      validation_mode: 'dry_run'
      schema_path: 'db/publicist/schema.sql'
      planned_table_row_counts: plannedRowCounts
      missing_required_fields: missingRequiredFields
      unresolved_joins: unresolvedJoins
      duplicate_ids: duplicateIds
      would_insert: wouldInsert
      summary:
        valid: missingRequiredFields.length is 0 and unresolvedJoins.length is 0 and duplicateIds.length is 0
        missing_required_fields_count: missingRequiredFields.length
        unresolved_joins_count: unresolvedJoins.length
        duplicate_ids_count: duplicateIds.length
        tables_checked: ['audiences', 'contacts', 'drafts', 'review_decisions', 'outreach_events']
        db_write_planned: false

    L.make 'sqlite_load_report', report
    L.done()
    return
