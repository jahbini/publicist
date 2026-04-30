#!/usr/bin/env coffee

resolveArtifactPayload = (M, experiment, artifactKey, validator) ->
  value = M.theLowdown(artifactKey)?.value
  return { value, key: artifactKey } if validator(value)

  targetKey = experiment?.artifacts?[artifactKey]?.target
  targetValue = M.theLowdown(targetKey)?.value
  return { value: targetValue, key: targetKey } if targetKey? and validator(targetValue)

  { value, key: artifactKey, targetKey, targetValue }

isApprovedTarget = (row) ->
  String(row?.review_status ? '').trim().toLowerCase() is 'approved'

@step =
  desc: 'Filter approved target candidates into qualified targets.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    targetCandidatesKey = 'target_candidates'
    targetCandidates = await L.need targetCandidatesKey
    targetArtifact = resolveArtifactPayload M, experiment, targetCandidatesKey, (value) -> Array.isArray(value?.target_candidates)
    targetCandidates = targetArtifact.value if Array.isArray(targetArtifact.value?.target_candidates)

    unless Array.isArray(targetCandidates?.target_candidates)
      attempted = [targetCandidatesKey]
      attempted.push targetArtifact.targetKey if targetArtifact.targetKey?
      throw new Error "[#{stepName}] Missing required artifact '#{targetCandidatesKey}' (attempted: #{attempted.join(', ')})"

    qualified = targetCandidates.target_candidates.filter(isApprovedTarget)
    byAudience = {}
    for row in qualified when row?.audience?
      byAudience[row.audience] = (byAudience[row.audience] ? 0) + 1

    payload =
      generated_for: targetCandidates.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: targetCandidates.campaign_source_hash ? null
      qualified_targets: qualified
      summary:
        total_qualified_targets: qualified.length
        by_audience: byAudience

    L.make 'qualified_targets', payload
    L.done()
    return
