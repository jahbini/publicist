#!/usr/bin/env coffee

isBlank = (value) ->
  String(value ? '').trim().length is 0

compactText = (value) ->
  String(value ? '')
    .replace(/\s+/g, ' ')
    .trim()

titleToOrganization = (title) ->
  text = compactText(title)
  return null unless text.length
  candidate = text.split(/\s+[|\-–—:]\s+/)[0] ? text
  candidate = candidate.replace(/\b(home|official site|official website)\b/i, '').trim()
  candidate or null

hostnameToOrganization = (hostname) ->
  text = String(hostname ? '').trim().toLowerCase()
  return null unless text.length
  text = text.replace(/^www\./, '')
  root = text.split('.')[0] ? text
  return null unless root.length
  root
    .split(/[-_]+/)
    .map (part) -> part.charAt(0).toUpperCase() + part.slice(1)
    .join(' ')

pickConfidence = (row) ->
  if not isBlank(row?.title) and not isBlank(row?.short_text_excerpt)
    'high'
  else if not isBlank(row?.title) or not isBlank(row?.short_text_excerpt)
    'medium'
  else
    'low'

excerptReason = (row, audienceLabel) ->
  excerpt = compactText(row?.short_text_excerpt ? '')
  base = if excerpt.length then excerpt.slice(0, 180) else "Relevant fetched context for #{audienceLabel ? 'this audience'}."
  base

extractWebsite = (urlText) ->
  try
    parsed = new URL(String(urlText ? ''))
    parsed.hostname.toLowerCase()
  catch
    null

resolveArtifactPayload = (M, experiment, artifactKey, validator) ->
  value = M.theLowdown(artifactKey)?.value
  return { value, key: artifactKey } if validator(value)

  targetKey = experiment?.artifacts?[artifactKey]?.target
  targetValue = M.theLowdown(targetKey)?.value
  return { value: targetValue, key: targetKey } if targetKey? and validator(targetValue)

  { value, key: artifactKey, targetKey, targetValue }

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

    labelsByName = {}
    for profile in audienceProfiles.profiles when profile?.audience_key?
      labelsByName[profile.audience_key] = profile.audience_label ? profile.audience_key
      labelsByName[profile.audience_label] = profile.audience_label

    grouped = {}
    raw = []

    for row in researchResults.results
      audienceType = row?.audience ? ''
      audienceLabel = labelsByName[audienceType] ? audienceType ? 'unknown'
      website = extractWebsite row?.url
      organizationName = titleToOrganization(row?.title) ? hostnameToOrganization(website) ? audienceLabel
      candidate =
        organization_name: organizationName
        website: website
        relevance_reason: excerptReason(row, audienceLabel)
        audience_type: audienceType
        confidence_score: pickConfidence(row)
        source_request_id: row?.request_id ? ''
        source_url: row?.url ? ''

      grouped[audienceType] ?= []
      grouped[audienceType].push candidate
      raw.push candidate

    payload =
      generated_for: researchResults.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: researchResults.campaign_source_hash ? audienceProfiles.campaign_source_hash ? null
      target_candidates: grouped
      raw_candidates: raw
      summary:
        audience_group_count: Object.keys(grouped).length
        raw_candidate_count: raw.length
        suggestion_only: true

    L.make 'target_candidates', payload
    L.done()
    return
