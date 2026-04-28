#!/usr/bin/env coffee

isBlank = (value) ->
  String(value ? '').trim().length is 0

DEFAULT_CAMPAIGN_CONFIG_PATH = 'source/publicist_campaign.yaml'

uniqueRows = (rows) ->
  seen = new Set()
  out = []
  for row in rows when row?.name?
    key = String(row.name).trim()
    continue unless key.length
    continue if seen.has(key)
    seen.add key
    out.push row
  out

spaceSuggestions = [
  {
    name: 'space_architecture'
    description: 'Researchers and engineers working on orbital structures'
    rationale: 'Matches phi-based geometric construction and space scaffolding.'
    example_targets: [
      'NASA research groups'
      'ESA structural engineering teams'
      'aerospace journals'
    ]
  }
  {
    name: 'advanced_manufacturing'
    description: 'Teams focused on modular fabrication, robotics, and assembly systems'
    rationale: 'The source text emphasizes simple-part inventory and robotic assembly.'
    example_targets: [
      'robotics labs'
      'modular manufacturing programs'
      'industrial systems publications'
    ]
  }
  {
    name: 'alternative_science_communities'
    description: 'Independent science and systems-thinking communities'
    rationale: 'The geometric and systems framing can resonate beyond mainstream aerospace channels.'
    example_targets: [
      'independent research collectives'
      'systems design forums'
      'future infrastructure newsletters'
    ]
  }
]

artsSuggestions = [
  {
    name: 'experimental_music_press'
    description: 'Writers and editors covering contemporary, immersive, and hybrid performance'
    rationale: 'The source text describes an audio-visual studio with layered resonance and live sessions.'
    example_targets: [
      'contemporary music journals'
      'experimental arts magazines'
      'performance criticism newsletters'
    ]
  }
  {
    name: 'curatorial_networks'
    description: 'Programmers and curators looking for distinctive interdisciplinary work'
    rationale: 'The work appears suitable for festivals, curated programs, and venue partnerships.'
    example_targets: [
      'festival curators'
      'new media programmers'
      'residency organizers'
    ]
  }
  {
    name: 'creative_technology_communities'
    description: 'Communities interested in sound, visual systems, and immersive production'
    rationale: 'The launch blends composition, studio practice, and audiovisual presentation.'
    example_targets: [
      'creative coding groups'
      'immersive media communities'
      'sound art networks'
    ]
  }
]

genericSuggestions = [
  {
    name: 'industry_observers'
    description: 'Publications and analysts watching meaningful developments in the field'
    rationale: 'A generic baseline audience for campaigns that need external framing.'
    example_targets: [
      'trade publications'
      'field-specific newsletters'
      'industry analysts'
    ]
  }
  {
    name: 'strategic_collaborators'
    description: 'Organizations that could amplify, support, or collaborate on the campaign'
    rationale: 'Partnership-oriented audiences are useful even before direct outreach is approved.'
    example_targets: [
      'aligned organizations'
      'program partners'
      'mission-adjacent communities'
    ]
  }
]

inferSuggestions = (sourceText) ->
  text = String(sourceText ? '').toLowerCase()
  if /(orbit|orbital|space|robot|robots|structur|triangle|triangular|frame|frames|assembly|aerospace)/.test(text)
    return spaceSuggestions
  if /(audio|visual|music|musician|studio|ensemble|composition|performance|live session|immersive|resonance)/.test(text)
    return artsSuggestions
  genericSuggestions

workspaceConfiguredAudienceRows = (campaignConfig) ->
  configured = if Array.isArray(campaignConfig?.priority_audiences) then campaignConfig.priority_audiences else []
  overrides = if campaignConfig?.audience_overrides? and typeof campaignConfig.audience_overrides is 'object' then campaignConfig.audience_overrides else {}
  configured.map (name) ->
    override = overrides[name] ? {}
    {
      name: String(name)
      description: override.label ? String(name).replace(/_/g, ' ')
      rationale: override.angle ? override.rationale ? 'Already configured in workspace campaign settings.'
      example_targets: override.example_targets ? []
    }

@step =
  desc: 'Suggest possible audiences from workspace source text without changing audience_profiles.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    sourceMaterialKey = 'source_material'
    sourceMaterial = await L.need sourceMaterialKey
    throw new Error "[#{stepName}] Missing required artifact '#{sourceMaterialKey}'" unless sourceMaterial?

    campaignConfig = M.theLowdown(DEFAULT_CAMPAIGN_CONFIG_PATH)?.value
    suggestions = inferSuggestions(sourceMaterial.source_text)
    configuredRows = workspaceConfiguredAudienceRows(campaignConfig)

    payload =
      generated_for: sourceMaterial.campaign_name ? experiment.run?.campaign_name
      campaign_source_hash: sourceMaterial.source_hash ? null
      campaign_config_path: DEFAULT_CAMPAIGN_CONFIG_PATH
      configured_priority_audiences: if Array.isArray(campaignConfig?.priority_audiences) then campaignConfig.priority_audiences else []
      audience_suggestions: uniqueRows(suggestions)
      configured_audience_hints: uniqueRows(configuredRows)
      summary:
        suggestion_count: suggestions.length
        configured_priority_count: if Array.isArray(campaignConfig?.priority_audiences) then campaignConfig.priority_audiences.length else 0
        suggestion_only: true
        used_campaign_config: Array.isArray(campaignConfig?.priority_audiences) and campaignConfig.priority_audiences.length > 0

    L.make 'audience_suggestions', payload
    L.done()
    return
