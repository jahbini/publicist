#!/usr/bin/env coffee

isBlank = (value) ->
  String(value ? '').trim().length is 0

slugify = (value) ->
  String(value ? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')

makeSearchTerms = (parts...) ->
  terms = []
  seen = new Set()
  for part in parts when not isBlank(part)
    text = String(part).trim()
    continue if seen.has(text)
    seen.add text
    terms.push text
  terms

@step =
  desc: 'Plan publicist research requests without performing web access.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    contactLedgerKey = 'contact_ledger'
    audienceProfilesKey = 'audience_profiles'
    nextActionsKey = 'next_actions'

    contactLedger = await L.need contactLedgerKey
    audienceProfiles = await L.need audienceProfilesKey
    nextActions = await L.need nextActionsKey

    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless contactLedger?.entries?
    throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}'" unless audienceProfiles?.profiles?
    throw new Error "[#{stepName}] Missing required artifact '#{nextActionsKey}'" unless nextActions?
    currentSourceHash = String(nextActions?.campaign_source_hash ? contactLedger?.campaign_source_hash ? audienceProfiles?.campaign_source_hash ? '')

    researchRequestsTarget = experiment.artifacts?.research_requests?.target
    existingDoc = if researchRequestsTarget? then M.theLowdown(researchRequestsTarget)?.value else null
    existingRequests = if Array.isArray(existingDoc?.research_requests) then existingDoc.research_requests else []
    existingByRequestId = {}
    for entry in existingRequests when entry?.request_id?
      existingByRequestId[entry.request_id] = entry

    ledgerByAudience = {}
    ledgerByIdentity = {}
    for entry in contactLedger.entries
      ledgerByAudience[entry.audience] = entry if entry?.audience?
      identity = "#{entry.organization ? ''}::#{entry.contact_name ? ''}"
      ledgerByIdentity[identity] = entry

    profileByLabel = {}
    for profile in audienceProfiles.profiles when profile?.audience_label?
      profileByLabel[profile.audience_label] = profile

    requests = []
    seenRequestIds = new Set()
    preservedCount = 0
    newCount = 0

    pushRequest = (payload) ->
      requestId = payload.request_id
      return unless requestId? and requestId.length
      return if seenRequestIds.has(requestId)
      seenRequestIds.add requestId
      existingEntry = existingByRequestId[requestId]
      sameCampaign = String(existingEntry?.campaign_source_hash ? '') is currentSourceHash and currentSourceHash.length > 0
      if sameCampaign
        merged = Object.assign {}, payload
        merged.suggested_search_terms = existingEntry.suggested_search_terms if Array.isArray(existingEntry.suggested_search_terms)
        for field in ['status', 'allowed_domains', 'reviewer_notes', 'reviewed_at', 'review_required']
          merged[field] = existingEntry[field] if existingEntry[field]?
        requests.push merged
        preservedCount += 1
      else
        requests.push payload
        newCount += 1

    for row in (nextActions.follow_up_contacts ? [])
      identity = "#{row.organization ? ''}::#{row.contact_name ? ''}"
      ledgerEntry = ledgerByIdentity[identity]
      audience = row.audience_label ? ledgerEntry?.audience ? ''
      pushRequest
        request_id: "research_follow_up_#{slugify(row.draft_id ? identity ? audience)}"
        audience: audience
        organization: row.organization ? ledgerEntry?.organization ? ''
        contact_name: row.contact_name ? ledgerEntry?.contact_name ? ''
        research_goal: 'Gather context that would improve a reviewed follow-up plan for an already approved target.'
        suggested_search_terms: makeSearchTerms(
          row.organization
          row.contact_name
          audience
          experiment.run?.campaign_name
          experiment.run?.launch_city
        )
        allowed_domains: []
        status: 'planned_only'
        review_required: true

    for row in (nextActions.audiences_to_expand ? [])
      profile = profileByLabel[row.audience_label]
      ledgerEntry = ledgerByAudience[row.audience_label]
      pushRequest
        request_id: "research_expand_#{slugify(row.audience_key ? row.audience_label)}"
        audience: row.audience_label ? ''
        organization: ledgerEntry?.organization ? ''
        contact_name: ledgerEntry?.contact_name ? ''
        research_goal: 'Find better-fit outlets, editors, or context to expand coverage for an audience with zero approved drafts.'
        suggested_search_terms: makeSearchTerms(
          row.audience_label
          profile?.angle
          profile?.rationale
          experiment.run?.campaign_name
          experiment.run?.launch_city
        )
        allowed_domains: []
        status: 'planned_only'
        review_required: true

    for row in (nextActions.drafts_needing_review ? [])
      identity = "#{row.organization ? ''}::#{row.contact_name ? ''}"
      ledgerEntry = ledgerByIdentity[identity]
      audience = ledgerEntry?.audience ? ''
      profile = profileByLabel[audience]
      pushRequest
        request_id: "research_review_#{slugify(row.draft_id ? identity ? audience)}"
        audience: audience
        organization: row.organization ? ledgerEntry?.organization ? ''
        contact_name: row.contact_name ? ledgerEntry?.contact_name ? ''
        research_goal: 'Collect background context that would help a human reviewer strengthen or reframe a pending draft.'
        suggested_search_terms: makeSearchTerms(
          row.organization
          row.contact_name
          audience
          profile?.angle
          experiment.run?.campaign_name
        )
        allowed_domains: []
        status: 'planned_only'
        review_required: true

    hasExplicitNextActions =
      (nextActions.follow_up_contacts ? []).length > 0 or
      (nextActions.audiences_to_expand ? []).length > 0 or
      (nextActions.drafts_needing_review ? []).length > 0

    unless hasExplicitNextActions
      for profile in audienceProfiles.profiles
        audienceId = profile.audience_key ? profile.audience_label ? 'audience'
        audienceName = profile.audience_label ? profile.audience_key ? ''
        pushRequest
          request_id: "research_#{slugify(audienceId)}_background"
          audience: audienceName
          organization: ""
          contact_name: ""
          research_goal: 'General background and positioning research for this audience.'
          suggested_search_terms: [
            "#{audienceName} publications"
            "#{audienceName} outreach opportunities"
            "#{audienceName} relevant organizations"
          ]
          allowed_domains: []
          status: 'planned_only'
          review_required: true

    for entry in existingRequests when entry?.request_id? and not seenRequestIds.has(entry.request_id)
      continue unless String(entry?.campaign_source_hash ? '') is currentSourceHash and currentSourceHash.length > 0
      seenRequestIds.add entry.request_id
      requests.push entry

    for request in requests
      request.campaign_source_hash = currentSourceHash or null

    payload =
      generated_for: nextActions.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: currentSourceHash or null
      request_count: requests.length
      preserved_count: preservedCount
      new_count: newCount
      approved_count: requests.filter((row) -> String(row?.status ? '').trim().toLowerCase() is 'approved_for_research').length
      research_requests: requests
      summary:
        planned_only: true
        follow_up_contacts_source_count: (nextActions.follow_up_contacts ? []).length
        audiences_to_expand_source_count: (nextActions.audiences_to_expand ? []).length
        drafts_needing_review_source_count: (nextActions.drafts_needing_review ? []).length
        used_fallback_planner: not hasExplicitNextActions

    L.make 'research_requests', payload
    L.done()
    return
