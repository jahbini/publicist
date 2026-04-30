#!/usr/bin/env coffee

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

normalizeWebsite = (value) ->
  text = normalizeText(value).replace(/^https?:\/\//i, '').replace(/\/+$/, '')
  text.replace(/^www\./i, '')

requestIdFor = (target) ->
  "contact_discovery_#{normalizeKey(target?.candidate_id ? target?.organization_name ? 'target')}"

buildProposedUrls = (website) ->
  host = normalizeWebsite website
  return [] unless host.length
  base = "https://#{host}"
  [
    "#{base}/contact"
    "#{base}/about"
    "#{base}/media"
    "#{base}/press"
    "#{base}/newsroom"
  ]

indexExisting = (doc) ->
  rows = if Array.isArray(doc?.contact_discovery_requests) then doc.contact_discovery_requests else []
  out = {}
  for row in rows when row?.request_id?
    urls = {}
    for proposed in (row.proposed_urls ? []) when proposed?.url?
      urls[normalizeKey(proposed.url)] = proposed
    out[row.request_id] =
      request: row
      urls: urls
  out

@step =
  desc: 'Plan contact/about/press URL discovery for approved qualified targets.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    qualifiedTargetsKey = 'qualified_targets'
    qualifiedTargets = await L.need qualifiedTargetsKey
    qualifiedArtifact = resolveArtifactPayload M, experiment, qualifiedTargetsKey, (value) -> Array.isArray(value?.qualified_targets)
    qualifiedTargets = qualifiedArtifact.value if Array.isArray(qualifiedArtifact.value?.qualified_targets)

    unless Array.isArray(qualifiedTargets?.qualified_targets)
      attempted = [qualifiedTargetsKey]
      attempted.push qualifiedArtifact.targetKey if qualifiedArtifact.targetKey?
      throw new Error "[#{stepName}] Missing required artifact '#{qualifiedTargetsKey}' (attempted: #{attempted.join(', ')})"

    existingArtifact = resolveArtifactPayload M, experiment, 'contact_discovery_requests', (value) -> Array.isArray(value?.contact_discovery_requests)
    existingByRequestId = indexExisting existingArtifact.value ? {}

    requests = []
    for target in qualifiedTargets.qualified_targets when normalizeText(target?.website).length
      requestId = requestIdFor target
      existing = existingByRequestId[requestId] ? {}
      existingRequest = existing.request ? {}
      existingUrls = existing.urls ? {}
      proposedUrls = buildProposedUrls target.website
        .map (url) ->
          prior = existingUrls[normalizeKey(url)] ? {}
          url: url
          review_status: normalizeText(prior.review_status) or 'planned_only'
          reviewer_notes: normalizeText(prior.reviewer_notes)

      request =
        request_id: requestId
        candidate_id: target.candidate_id ? ''
        organization_name: target.organization_name ? ''
        audience: target.audience ? ''
        proposed_urls: proposedUrls
        status: normalizeText(existingRequest.status) or 'planned_only'
        reviewer_notes: normalizeText(existingRequest.reviewer_notes)

      requests.push request

    payload =
      generated_for: qualifiedTargets.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: qualifiedTargets.campaign_source_hash ? null
      contact_discovery_requests: requests
      summary:
        total_requests: requests.length
        total_proposed_urls: requests.reduce(((sum, row) -> sum + (row.proposed_urls ? []).length), 0)
        suggestion_only: true

    L.make 'contact_discovery_requests', payload
    L.done()
    return
