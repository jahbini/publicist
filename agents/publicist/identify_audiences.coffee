#!/usr/bin/env coffee

isBlank = (value) ->
  String(value ? '').trim().length is 0

DEFAULT_CAMPAIGN_CONFIG_PATH = 'source/publicist_campaign.yaml'

audienceMap =
  technical_press:
    label: 'Technical press'
    angle: 'Explain the technical novelty and why the build system matters now.'
    rationale: 'Trade and engineering writers can translate the system for informed readers.'
  industry_partners:
    label: 'Industry partners'
    angle: 'Show where the campaign fits into real deployment, manufacturing, or integration work.'
    rationale: 'Potential partners need a concrete collaboration frame and mutual benefit.'
  research_labs:
    label: 'Research labs'
    angle: 'Emphasize experimental value, validation paths, and scientific relevance.'
    rationale: 'Labs and institutes respond to rigor, feasibility, and research utility.'
  pilot_customers:
    label: 'Pilot customers'
    angle: 'Focus on the practical use case, first deployment path, and near-term value.'
    rationale: 'Prospective adopters need a clear reason to trial the work.'
  arts_press:
    label: 'Arts press'
    angle: 'Frame the campaign as a distinct artistic launch with a clear voice and audience.'
    rationale: 'Arts writers look for a compelling creative point of view and cultural relevance.'
  curators_programmers:
    label: 'Curators and programmers'
    angle: 'Highlight why the work fits a program, season, or event context.'
    rationale: 'Programmers need curation-ready language and a concrete fit.'
  venue_partners:
    label: 'Venue partners'
    angle: 'Focus on live presentation, audience experience, and operational fit.'
    rationale: 'Venues need confidence that the work belongs in their room and calendar.'
  creative_collaborators:
    label: 'Creative collaborators'
    angle: 'Describe what kinds of artists, producers, or makers could build on the work.'
    rationale: 'Collaborators need to see the opening for joint creation.'
  industry_press:
    label: 'Industry press'
    angle: 'Present the campaign as a meaningful development in its field.'
    rationale: 'General trade coverage helps establish baseline visibility.'
  strategic_partners:
    label: 'Strategic partners'
    angle: 'Clarify the shared opportunity and why the campaign matters to both sides.'
    rationale: 'Partnership outreach needs a mutual-value frame.'
  community_allies:
    label: 'Community allies'
    angle: 'Connect the campaign to the community it serves or activates.'
    rationale: 'Community groups amplify work that aligns with their mission.'
  direct_opportunities:
    label: 'Direct opportunities'
    angle: 'Focus on immediate openings for placement, collaboration, or response.'
    rationale: 'This keeps the outreach practical when the category is still forming.'

inferAudienceKeys = (sourceMaterial) ->
  text = String(sourceMaterial?.source_text ? '').toLowerCase()
  if /(orbit|orbital|space|robot|robots|structur|triangle|triangular|frame|frames|assembly)/.test(text)
    return ['technical_press', 'industry_partners', 'research_labs', 'pilot_customers']
  if /(audio|visual|music|musician|studio|ensemble|composition|performance|live session|immersive|resonance)/.test(text)
    return ['arts_press', 'curators_programmers', 'venue_partners', 'creative_collaborators']
  ['industry_press', 'strategic_partners', 'community_allies', 'direct_opportunities']

readCampaignAudienceConfig = (M) ->
  doc = M.theLowdown(DEFAULT_CAMPAIGN_CONFIG_PATH)?.value
  return null unless doc? and typeof doc is 'object' and not Array.isArray(doc)
  doc

buildProfile = (audienceKey, index, campaignName, proofPoints, overrideSpec = {}) ->
  spec = Object.assign {}, audienceMap[audienceKey] ? {}, overrideSpec ? {}
  recommendedChannel = if String(spec.recommended_channel ? '').trim().length then spec.recommended_channel else 'reviewed_email_draft'
  audience_index: index + 1
  audience_key: audienceKey
  audience_label: spec.label ? audienceKey
  angle: spec.angle ? 'General awareness of the campaign.'
  rationale: spec.rationale ? 'Relevant audience for reviewed outreach drafts.'
  recommended_channel: recommendedChannel
  campaign_name: campaignName
  proof_points: proofPoints.slice(0, 2)
  review_required: true

@step =
  desc: 'Identify audience profiles from workspace campaign configuration or inferred source context.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    artifactKey = 'source_material'
    sourceMaterial = await L.need artifactKey
    throw new Error "[#{stepName}] Missing required artifact '#{artifactKey}'" unless sourceMaterial?

    campaignConfig = readCampaignAudienceConfig(M)
    configuredAudiences = if Array.isArray(campaignConfig?.priority_audiences) then campaignConfig.priority_audiences else null
    audienceOverrides = if campaignConfig?.audience_overrides? and typeof campaignConfig.audience_overrides is 'object' then campaignConfig.audience_overrides else {}
    selectedAudienceKeys = if configuredAudiences?.length then configuredAudiences else inferAudienceKeys(sourceMaterial)

    throw new Error "[#{stepName}] Could not determine any audiences" unless Array.isArray(selectedAudienceKeys) and selectedAudienceKeys.length > 0

    proofPoints = sourceMaterial.highlights ? []
    campaignName = sourceMaterial.campaign_name ? experiment.run?.campaign_name

    profiles = selectedAudienceKeys.map (audienceKey, index) ->
      buildProfile audienceKey, index, campaignName, proofPoints, audienceOverrides[audienceKey]

    payload =
      generated_for: campaignName
      campaign_source_hash: sourceMaterial.source_hash ? null
      audience_count: profiles.length
      profiles: profiles
      notes:
        source_material_key: 'source_material'
        campaign_config_path: DEFAULT_CAMPAIGN_CONFIG_PATH
        used_campaign_config: Array.isArray(configuredAudiences) and configuredAudiences.length > 0
        review_owner: experiment.run?.review_owner
        draft_only: true

    L.make 'audience_profiles', payload
    L.done()
    return
