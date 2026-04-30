#!/usr/bin/env coffee

defaultOrganizations =
  local_food_press:
    organization: 'Food Desk Placeholder'
    contact_name: 'Editorial Contact'
    contact_role: 'Food Editor'
    contact_channel: 'reviewed_email_draft'
  neighborhood_newsletters:
    organization: 'Neighborhood Bulletin Placeholder'
    contact_name: 'Community Editor'
    contact_role: 'Community Editor'
    contact_channel: 'reviewed_email_draft'
  community_partners:
    organization: 'Community Partner Placeholder'
    contact_name: 'Partnership Lead'
    contact_role: 'Partnership Lead'
    contact_channel: 'reviewed_email_draft'
  event_calendars:
    organization: 'Event Calendar Placeholder'
    contact_name: 'Listings Coordinator'
    contact_role: 'Listings Coordinator'
    contact_channel: 'listing_submission_draft'

normalizeText = (value) ->
  String(value ? '').trim()

normalizeKey = (value) ->
  normalizeText(value).toLowerCase()

resolveArtifactPayload = (M, experiment, artifactKey, validator) ->
  value = M.theLowdown(artifactKey)?.value
  return { value, key: artifactKey } if validator(value)

  targetKey = experiment?.artifacts?[artifactKey]?.target
  targetValue = M.theLowdown(targetKey)?.value
  return { value: targetValue, key: targetKey } if targetKey? and validator(targetValue)

  { value, key: artifactKey, targetKey, targetValue }

entryKeyByOrgAudience = (entry) ->
  "#{normalizeKey(entry?.audience)}::#{normalizeKey(entry?.organization)}"

@step =
  desc: 'Build a reviewed draft-only contact ledger for outreach targets.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    audienceProfilesKey = 'audience_profiles'
    audienceProfiles = await L.need audienceProfilesKey
    throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}'" unless audienceProfiles?.profiles?

    qualifiedTargetsArtifact = resolveArtifactPayload M, experiment, 'qualified_targets', (value) -> Array.isArray(value?.qualified_targets)
    qualifiedTargets = if Array.isArray(qualifiedTargetsArtifact.value?.qualified_targets) then qualifiedTargetsArtifact.value.qualified_targets else []

    contactLedgerArtifact = resolveArtifactPayload M, experiment, 'contact_ledger', (value) -> Array.isArray(value?.entries)
    existingLedger = if Array.isArray(contactLedgerArtifact.value?.entries) then contactLedgerArtifact.value.entries else []
    existingByCandidateId = {}
    existingByOrgAudience = {}
    for entry in existingLedger when entry?
      existingByCandidateId[normalizeKey(entry.source_candidate_id)] = entry if normalizeText(entry.source_candidate_id).length
      existingByOrgAudience[entryKeyByOrgAudience(entry)] = entry if normalizeText(entry.organization).length and normalizeText(entry.audience).length

    ledgerEntries = audienceProfiles.profiles.map (profile) ->
      defaults = defaultOrganizations[profile.audience_key] ? {}
      audience: profile.audience_label
      organization: defaults.organization ? "#{profile.audience_label} Placeholder"
      contact_name: defaults.contact_name ? 'Review Pending'
      contact_role: defaults.contact_role ? 'Editor'
      contact_channel: defaults.contact_channel ? profile.recommended_channel ? 'reviewed_email_draft'
      status: 'draft_only'
      rationale: profile.rationale ? profile.angle ? 'Candidate outreach target for reviewed drafting.'
      next_action: 'Review contact record before any outreach draft is approved or sent.'
      review_required: true

    qualifiedEntries = []
    for target in qualifiedTargets when normalizeText(target?.organization_name).length
      draftEntry =
        audience: target.audience ? ''
        organization: target.organization_name
        contact_name: 'Review Pending'
        contact_role: target.target_type ? 'unknown'
        contact_channel: target.website ? 'reviewed_email_draft'
        status: 'target_qualified'
        rationale: target.relevance_reason ? 'Approved qualified target.'
        next_action: 'draft_reviewed_outreach'
        review_required: true
        source_candidate_id: target.candidate_id ? null

      preserved = null
      candidateIdKey = normalizeKey(target.candidate_id)
      if candidateIdKey.length and existingByCandidateId[candidateIdKey]?
        preserved = existingByCandidateId[candidateIdKey]
      else
        orgAudienceKey = entryKeyByOrgAudience(draftEntry)
        preserved = existingByOrgAudience[orgAudienceKey] if existingByOrgAudience[orgAudienceKey]?

      if preserved?
        merged = Object.assign {}, draftEntry, preserved
        merged.audience = draftEntry.audience
        merged.organization = draftEntry.organization
        merged.contact_name = preserved.contact_name ? draftEntry.contact_name
        merged.contact_role = preserved.contact_role ? draftEntry.contact_role
        merged.contact_channel = preserved.contact_channel ? draftEntry.contact_channel
        merged.status = 'target_qualified'
        merged.rationale = preserved.rationale ? draftEntry.rationale
        merged.next_action = preserved.next_action ? draftEntry.next_action
        merged.review_required = if preserved.review_required? then preserved.review_required else true
        merged.source_candidate_id = target.candidate_id ? preserved.source_candidate_id ? null
        qualifiedEntries.push merged
      else
        qualifiedEntries.push draftEntry

    ledgerEntries = qualifiedEntries.concat ledgerEntries

    payload =
      generated_for: audienceProfiles.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: audienceProfiles.campaign_source_hash ? null
      ledger_count: ledgerEntries.length
      entries: ledgerEntries
      notes:
        placeholder_contacts_only: qualifiedEntries.length is 0
        qualified_target_entries: qualifiedEntries.length
        draft_only: true
        no_live_actions: true

    L.make 'contact_ledger', payload
    L.done()
    return
