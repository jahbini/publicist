#!/usr/bin/env coffee

compactText = (value) ->
  String(value ? '')
    .replace(/\s+/g, ' ')
    .trim()

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

joinUnique = (rows) ->
  seen = new Set()
  out = []
  for row in rows
    text = compactText row
    continue unless text.length
    key = text.toLowerCase()
    continue if seen.has key
    seen.add key
    out.push text
  out

contactPageFormsText = (rows) ->
  joinUnique((rows ? []).map((row) -> "#{normalizeText(row?.method ? 'GET')} #{normalizeText(row?.url)}"))

buildTargetCallToAction = (entry) ->
  parts = [
    'Please review the project and consider whether this fits your audience.'
    'If it does, we would value a conversation, a technical referral, or guidance on the right editorial or program contact.'
  ]
  if String(entry?.status ? '') is 'target_qualified'
    parts.splice 1, 0, 'We are especially interested in whether there is technical interest or partner relevance here.'
  parts.join ' '

buildContextNotes = (profile, relatedResearchRows, enrichment) ->
  notes = []
  for row in relatedResearchRows.slice(0, 2)
    title = compactText row?.title ? row?.page_title
    excerpt = compactText row?.short_text_excerpt ? row?.clean_text_excerpt
    notes.push title if title.length
    notes.push excerpt if excerpt.length and excerpt isnt 'No useful content extracted'
  for item in (enrichment?.additional_talking_points ? []).slice(0, 2)
    notes.push item
  joinUnique notes

buildWhyThisTargetMayCare = (entry, profile, enrichment) ->
  joinUnique [
    entry?.rationale
    profile?.rationale
    profile?.angle
    (enrichment?.suggested_improvements ? []).join(' ')
    (enrichment?.additional_talking_points ? []).join(' ')
  ]

preserveHumanRevision = (draft, existingDraft, currentSourceHash) ->
  return draft unless existingDraft?.revised_by_human is true
  return draft unless String(existingDraft?.campaign_source_hash ? '') is String(currentSourceHash ? '')
  merged = Object.assign {}, draft
  merged.subject = existingDraft.subject if typeof existingDraft.subject is 'string'
  merged.email_body = existingDraft.email_body if typeof existingDraft.email_body is 'string'
  merged.revised_by_human = true
  merged.revised_at = existingDraft.revised_at ? new Date().toISOString()
  merged

@step =
  desc: 'Build reviewed outreach drafts from source material and audiences.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    sourceMaterialKey = 'source_material'
    audienceProfilesKey = 'audience_profiles'
    contactLedgerKey = 'contact_ledger'
    sourceMaterial = await L.need sourceMaterialKey
    audienceProfiles = await L.need audienceProfilesKey
    contactLedger = await L.need contactLedgerKey
    throw new Error "[#{stepName}] Missing required artifact '#{sourceMaterialKey}'" unless sourceMaterial?
    throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}'" unless audienceProfiles?.profiles?
    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless contactLedger?.entries?

    callToAction = M.getStepParam(stepName, 'call_to_action') ? 'Request review before any outreach is sent.'
    signatureName = M.getStepParam(stepName, 'signature_name') ? sourceMaterial.brand_name ? experiment.run?.brand_name ? 'Team'
    messageDraftsTarget = experiment.artifacts?.message_drafts?.target
    existingDoc = if messageDraftsTarget? then M.theLowdown(messageDraftsTarget)?.value else null
    existingDrafts = if Array.isArray(existingDoc?.drafts) then existingDoc.drafts else []
    qualifiedTargetsDoc = resolveArtifactPayload(M, experiment, 'qualified_targets', (value) -> Array.isArray(value?.qualified_targets)).value ? {}
    qualifiedTargets = if Array.isArray(qualifiedTargetsDoc?.qualified_targets) then qualifiedTargetsDoc.qualified_targets else []
    qualifiedByCandidateId = {}
    qualifiedByOrgAudience = {}
    for row in qualifiedTargets when row?
      qualifiedByCandidateId[normalizeKey(row.candidate_id)] = row if normalizeText(row.candidate_id).length
      qualifiedByOrgAudience["#{normalizeKey(row.audience)}::#{normalizeKey(row.organization_name)}"] = row if normalizeText(row.audience).length and normalizeText(row.organization_name).length

    enrichedDraftsDoc = resolveArtifactPayload(M, experiment, 'enriched_drafts', (value) -> Array.isArray(value?.enriched_drafts)).value ? {}
    enrichedByDraftId = {}
    for row in (enrichedDraftsDoc?.enriched_drafts ? []) when row?.draft_id?
      enrichedByDraftId[row.draft_id] = row

    researchResultsDoc = resolveArtifactPayload(M, experiment, 'research_results', (value) -> Array.isArray(value?.results)).value ? {}
    researchRows = if Array.isArray(researchResultsDoc?.results) then researchResultsDoc.results else []

    contactPageResultsDoc = resolveArtifactPayload(M, experiment, 'contact_page_results', (value) -> Array.isArray(value?.results)).value ? {}
    contactPageByCandidateId = {}
    for row in (contactPageResultsDoc?.results ? []) when normalizeText(row?.candidate_id).length
      key = normalizeKey row.candidate_id
      contactPageByCandidateId[key] ?= []
      contactPageByCandidateId[key].push row

    existingByDraftId = {}
    for draft in existingDrafts when draft?.draft_id?
      existingByDraftId[draft.draft_id] = draft

    baseHighlights = (sourceMaterial.highlights ? []).slice(0, 2).join(' ')
    drafts = audienceProfiles.profiles.map (profile) ->
      matchingEntries = contactLedger.entries.filter (entry) -> entry.audience is profile.audience_label
      ledgerEntry = matchingEntries.find((entry) -> String(entry?.status ? '') is 'target_qualified') ? matchingEntries[0]
      targetKey = if normalizeText(ledgerEntry?.source_candidate_id).length then normalizeKey(ledgerEntry.source_candidate_id) else null
      qualifiedTarget = if targetKey? and qualifiedByCandidateId[targetKey]? then qualifiedByCandidateId[targetKey] else qualifiedByOrgAudience["#{normalizeKey(ledgerEntry?.audience)}::#{normalizeKey(ledgerEntry?.organization)}"]
      hook = compactText(profile.angle)
      draftId = "draft_#{profile.audience_key}"
      subject = "#{sourceMaterial.brand_name}: #{profile.audience_label} draft"
      relatedResearchRows = researchRows.filter (row) ->
        normalizeKey(row?.audience) is normalizeKey(profile.audience_key) or
        normalizeKey(row?.audience) is normalizeKey(profile.audience_label) or
        (normalizeText(ledgerEntry?.organization).length and normalizeKey(row?.organization) is normalizeKey(ledgerEntry.organization))
      existingEnrichment = enrichedByDraftId[draftId]
      contextNotes = buildContextNotes profile, relatedResearchRows, existingEnrichment
      whyThisTargetMayCare = buildWhyThisTargetMayCare ledgerEntry, profile, existingEnrichment
      targetCallToAction = buildTargetCallToAction ledgerEntry
      emailBody = [
        "Hi #{ledgerEntry?.contact_name ? profile.audience_label},"
        ""
        "I’m sharing a draft outreach note for review regarding #{sourceMaterial.campaign_name}."
        "#{hook}"
        ""
        "#{baseHighlights}"
        ""
        (if contextNotes.length then "Context notes: #{contextNotes.join(' ')}" else null)
        (if whyThisTargetMayCare.length then "Why this target may care: #{whyThisTargetMayCare.join(' ')}" else null)
        ""
        (if String(ledgerEntry?.status ? '') is 'target_qualified' then targetCallToAction else callToAction)
        ""
        "Best,"
        signatureName
      ].filter((line) -> line? and String(line).length).join("\n")

      followUp = "Follow up with #{String(profile.audience_label ? '').toLowerCase()} only after human review and explicit approval."

      draft = 
        audience_key: profile.audience_key
        draft_id: draftId
        campaign_source_hash: sourceMaterial.source_hash ? null
        audience_label: profile.audience_label
        organization: ledgerEntry?.organization ? null
        contact_name: ledgerEntry?.contact_name ? null
        contact_role: ledgerEntry?.contact_role ? null
        contact_channel: ledgerEntry?.contact_channel ? null
        target_website: qualifiedTarget?.website ? ledgerEntry?.contact_channel ? null
        target_type: qualifiedTarget?.target_type ? ledgerEntry?.contact_role ? null
        target_rationale: qualifiedTarget?.relevance_reason ? ledgerEntry?.rationale ? null
        contact_page_url: ledgerEntry?.contact_page_url ? contactPageByCandidateId[targetKey]?[0]?.url ? null
        discovered_contact_forms: ledgerEntry?.discovered_contact_forms ? []
        discovered_social_links: ledgerEntry?.discovered_social_links ? []
        context_notes: contextNotes
        why_this_target_may_care: whyThisTargetMayCare
        subject: subject
        pitch_summary: hook
        email_body: emailBody
        follow_up_note: followUp
        review_required: true

      preserveHumanRevision draft, existingByDraftId[draftId], sourceMaterial.source_hash

    payload =
      generated_for: sourceMaterial.campaign_name
      campaign_source_hash: sourceMaterial.source_hash ? null
      draft_count: drafts.length
      drafts: drafts
      constraints:
        live_send_enabled: false
        network_posting_enabled: false
        requires_human_review: true

    L.make 'message_drafts', payload
    L.done()
    return
