#!/usr/bin/env coffee

NOISE_TEXT_PATTERNS = [
  /googletagmanager/i
  /cookie/i
  /privacy/i
  /terms/i
  /sign in/i
  /get started/i
  /menu\b/i
  /navigation/i
  /sitemap/i
  /account/i
  /login/i
]

GENERIC_HOSTS = new Set([
  'medium.com'
  'substack.com'
])

normalizeWhitespace = (value) ->
  String(value ? '')
    .replace(/\s+/g, ' ')
    .trim()

isBlank = (value) ->
  normalizeWhitespace(value).length is 0

normalizeHostname = (value) ->
  text = String(value ? '').trim().toLowerCase()
  return '' unless text.length
  text.replace(/^www\./, '')

normalizeKey = (value) ->
  normalizeWhitespace(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')

containsNoise = (value) ->
  text = normalizeWhitespace(value)
  return true unless text.length
  NOISE_TEXT_PATTERNS.some (pattern) -> pattern.test(text)

cleanOrganizationName = (value) ->
  text = normalizeWhitespace(value)
  return null unless text.length
  text = text.replace(/\b(home|official site|official website)\b/ig, '').trim()
  return null unless text.length
  return null if containsNoise(text)
  text

formatHostnameName = (hostname) ->
  host = normalizeHostname(hostname)
  return null unless host.length
  root = host.split('.')[0] ? host
  return null unless root.length
  return null if GENERIC_HOSTS.has(host)
  if /^[a-z]{2,6}$/i.test(root)
    return root.toUpperCase()
  root
    .split(/[-_]+/)
    .map (part) -> part.charAt(0).toUpperCase() + part.slice(1)
    .join(' ')

extractWebsite = (urlText) ->
  try
    parsed = new URL(String(urlText ? ''))
    normalizeHostname(parsed.hostname)
  catch
    ''

titleCandidateName = (title) ->
  text = normalizeWhitespace(title)
  return null unless text.length
  primary = text.split(/\s+[|\-–—:]\s+/)[0] ? text
  cleanOrganizationName(primary)

excerptCandidateNames = (excerpt) ->
  text = normalizeWhitespace(excerpt)
  return [] unless text.length
  return [] if containsNoise(text)

  patterns = [
    /\b([A-Z][A-Za-z0-9&'’.-]+(?:\s+[A-Z][A-Za-z0-9&'’.-]+){0,5}\s+(?:Forum|Program|Initiative|Journal|Magazine|Review|Society|Association|Agency|Laboratory|Labs|Lab|Institute|Center|Centre|Community|Collective|Network|Conference|Workshop|Summit|School Days))\b/g
    /\b((?:NASA|ESA|AIAA|SpaceX|Blue Origin|Rocket Lab)(?:\s+[A-Z][A-Za-z0-9&'’.-]+){0,4})\b/g
  ]

  found = []
  seen = new Set()
  for pattern in patterns
    pattern.lastIndex = 0
    while (match = pattern.exec(text))?
      candidate = cleanOrganizationName(match[1])
      continue unless candidate?
      key = normalizeKey(candidate)
      continue unless key.length and not seen.has(key)
      seen.add key
      found.push candidate
  found

classifyTargetType = (organizationName, title, excerpt, audience, website = '') ->
  corpus = [
    organizationName
    title
    excerpt
    audience
  ].map((value) -> normalizeWhitespace(value).toLowerCase()).join(' ')

  return 'publication' if /\b(journal|magazine|newsletter|press|news|media|review|digest|blog)\b/.test(corpus)
  return 'lab' if /\b(lab|labs|laboratory|research institute|research center|research centre|observatory)\b/.test(corpus)
  return 'community' if /\b(community|collective|society|network|forum|guild|group)\b/.test(corpus)
  return 'program' if /\b(program|initiative|fellowship|accelerator|conference|workshop|summit|school)\b/.test(corpus)
  return 'organization' if /\b(agency|association|company|corp|corporation|foundation|organization|committee|team)\b/.test(corpus)
  return 'organization' if /\.(gov|int|org|edu)$/.test(normalizeHostname(website))
  'unknown'

pickConfidence = (sourceKind, organizationName, title, excerpt, website) ->
  hasTitle = not isBlank(title)
  hasExcerpt = not isBlank(excerpt)
  hasWebsite = not isBlank(website)
  if sourceKind is 'excerpt' and hasExcerpt and hasWebsite
    return 'high'
  if sourceKind is 'title' and hasTitle and hasWebsite
    return 'high'
  if sourceKind is 'hostname' and hasWebsite and not isBlank(organizationName)
    return 'medium'
  if sourceKind is 'request_context'
    return 'low'
  if hasTitle or hasExcerpt
    return 'medium'
  'low'

buildReason = (sourceKind, row, audienceLabel, organizationName) ->
  title = normalizeWhitespace(row?.title)
  excerpt = normalizeWhitespace(row?.short_text_excerpt)
  switch sourceKind
    when 'title'
      "Title suggests #{organizationName} is relevant for #{audienceLabel}: #{title}".slice(0, 220)
    when 'hostname'
      "Hostname suggests #{organizationName} may be a useful target for #{audienceLabel}."
    when 'excerpt'
      snippet = excerpt.slice(0, 180)
      "Excerpt mentions #{organizationName} in #{audienceLabel} context: #{snippet}".slice(0, 220)
    else
      "Request context suggests #{organizationName} may matter for #{audienceLabel}."

buildCandidateId = (audience, website, organizationName) ->
  audienceKey = normalizeKey(audience)
  siteKey = normalizeKey(website)
  orgKey = normalizeKey(organizationName)
  "candidate_#{audienceKey}_#{siteKey or orgKey}"

resolveArtifactPayload = (M, experiment, artifactKey, validator) ->
  value = M.theLowdown(artifactKey)?.value
  return { value, key: artifactKey } if validator(value)

  targetKey = experiment?.artifacts?[artifactKey]?.target
  targetValue = M.theLowdown(targetKey)?.value
  return { value: targetValue, key: targetKey } if targetKey? and validator(targetValue)

  { value, key: artifactKey, targetKey, targetValue }

indexExistingByCandidateId = (doc) ->
  rows = if Array.isArray(doc?.target_candidates) then doc.target_candidates else []
  out = {}
  for row in rows when row?.candidate_id?
    out[row.candidate_id] = row
  out

@step =
  desc: 'Extract suggestion-only target candidates from fetched research results.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    researchResultsKey = 'research_results'
    audienceProfilesKey = 'audience_profiles'
    researchResults = await L.need researchResultsKey
    audienceProfiles = await L.need audienceProfilesKey

    researchArtifact = resolveArtifactPayload M, experiment, researchResultsKey, (value) -> Array.isArray(value?.results)
    audienceArtifact = resolveArtifactPayload M, experiment, audienceProfilesKey, (value) -> Array.isArray(value?.profiles)

    researchResults = researchArtifact.value if Array.isArray(researchArtifact.value?.results)
    audienceProfiles = audienceArtifact.value if Array.isArray(audienceArtifact.value?.profiles)

    unless Array.isArray(researchResults?.results)
      attempted = [researchResultsKey]
      attempted.push researchArtifact.targetKey if researchArtifact.targetKey?
      throw new Error "[#{stepName}] Missing required artifact '#{researchResultsKey}' (attempted: #{attempted.join(', ')})"

    unless Array.isArray(audienceProfiles?.profiles)
      attempted = [audienceProfilesKey]
      attempted.push audienceArtifact.targetKey if audienceArtifact.targetKey?
      throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}' (attempted: #{attempted.join(', ')})"

    labelsByKey = {}
    for profile in audienceProfiles.profiles when profile?.audience_key?
      labelsByKey[profile.audience_key] = profile.audience_label ? profile.audience_key
      labelsByKey[profile.audience_label] = profile.audience_label ? profile.audience_key

    existingArtifact = resolveArtifactPayload M, experiment, 'target_candidates', (value) -> Array.isArray(value?.target_candidates)
    existingDoc = existingArtifact.value ? {}
    existingById = indexExistingByCandidateId(existingDoc)
    deduped = {}
    sourceRows = if Array.isArray(researchResults.results) then researchResults.results else []

    addCandidate = (row, audienceLabel, organizationName, website, sourceKind) ->
      cleanName = cleanOrganizationName(organizationName)
      return unless cleanName?

      host = normalizeHostname(website)
      return if GENERIC_HOSTS.has(host) and sourceKind is 'hostname'

      targetType = classifyTargetType cleanName, row?.title, row?.short_text_excerpt, audienceLabel, host
      keyBasis = if host.length then host else cleanName
      return unless normalizeKey(keyBasis).length

      candidateKey = "#{normalizeKey(audienceLabel)}::#{normalizeKey(keyBasis)}"
      sourceUrl = String(row?.url ? '').trim()
      candidate = deduped[candidateKey]
      unless candidate?
        candidateId = buildCandidateId(audienceLabel, host, cleanName)
        existing = existingById[candidateId] ? {}
        candidate =
          candidate_id: candidateId
          audience: audienceLabel
          source_request_id: row?.request_id ? ''
          organization_name: cleanName
          target_type: targetType
          website: host
          source_url: sourceUrl
          source_urls: []
          relevance_reason: buildReason(sourceKind, row, audienceLabel, cleanName)
          confidence: pickConfidence(sourceKind, cleanName, row?.title, row?.short_text_excerpt, host)
          extracted_from: sourceKind
          review_status: String(existing.review_status ? 'pending_review')
          reviewer_notes: String(existing.reviewer_notes ? '')
          reviewed_at: existing.reviewed_at ? null
        deduped[candidateKey] = candidate

      if sourceUrl.length and not candidate.source_urls.includes(sourceUrl)
        candidate.source_urls.push sourceUrl

      confidenceRank =
        low: 1
        medium: 2
        high: 3
      sourceRank =
        request_context: 1
        hostname: 2
        excerpt: 3
        title: 4

      nextConfidence = pickConfidence(sourceKind, cleanName, row?.title, row?.short_text_excerpt, host)
      shouldPromoteName = sourceRank[sourceKind] > (sourceRank[candidate.extracted_from] ? 0) or cleanName.length > String(candidate.organization_name ? '').length

      if shouldPromoteName
        candidate.organization_name = cleanName
        candidate.extracted_from = sourceKind
        candidate.relevance_reason = buildReason(sourceKind, row, audienceLabel, cleanName)

      if confidenceRank[nextConfidence] > confidenceRank[candidate.confidence]
        candidate.confidence = nextConfidence
      if shouldPromoteName and confidenceRank[nextConfidence] >= confidenceRank[candidate.confidence]
        candidate.extracted_from = sourceKind
        candidate.confidence = nextConfidence

      if candidate.target_type is 'unknown' and targetType isnt 'unknown'
        candidate.target_type = targetType

    for row in sourceRows when row?
      audienceKey = row?.audience ? ''
      audienceLabel = labelsByKey[audienceKey] ? audienceKey ? 'unknown'
      website = extractWebsite(row?.redirect_target ? row?.url)

      nameFromTitle = titleCandidateName(row?.title)
      addCandidate row, audienceLabel, nameFromTitle, website, 'title' if nameFromTitle?

      nameFromHost = formatHostnameName(website)
      addCandidate row, audienceLabel, nameFromHost, website, 'hostname' if nameFromHost?

      for excerptName in excerptCandidateNames(row?.short_text_excerpt)
        addCandidate row, audienceLabel, excerptName, website, 'excerpt'

      if isBlank(row?.title) and isBlank(row?.short_text_excerpt) and not isBlank(website)
        addCandidate row, audienceLabel, nameFromHost, website, 'request_context' if nameFromHost?

    candidates = Object.values(deduped)
      .filter (row) -> not isBlank(row.organization_name)
      .sort (a, b) ->
        audienceCmp = String(a.audience ? '').localeCompare(String(b.audience ? ''))
        return audienceCmp if audienceCmp isnt 0
        String(a.organization_name ? '').localeCompare(String(b.organization_name ? ''))

    groups = {}
    byAudience = {}
    byTargetType = {}
    byConfidence = {}
    for candidate in candidates
      groups[candidate.audience] ?= []
      groups[candidate.audience].push candidate
      byAudience[candidate.audience] = (byAudience[candidate.audience] ? 0) + 1
      byTargetType[candidate.target_type] = (byTargetType[candidate.target_type] ? 0) + 1
      byConfidence[candidate.confidence] = (byConfidence[candidate.confidence] ? 0) + 1

    payload =
      generated_for: researchResults.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: researchResults.campaign_source_hash ? audienceProfiles.campaign_source_hash ? null
      target_candidates: candidates
      groups_by_audience: groups
      summary:
        total_candidates: candidates.length
        by_audience: byAudience
        by_target_type: byTargetType
        by_confidence: byConfidence
        suggestion_only: true

    L.make 'target_candidates', payload
    L.done()
    return
