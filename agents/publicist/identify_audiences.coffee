#!/usr/bin/env coffee

defaultAudienceMap =
  local_food_press:
    label: 'Local food press'
    angle: 'Fresh local dining story with a neighborhood hook.'
    rationale: 'Writers covering openings and chef-driven community stories.'
  neighborhood_newsletters:
    label: 'Neighborhood newsletters'
    angle: 'Practical event details for nearby residents.'
    rationale: 'Newsletter editors need concise local happenings and dates.'
  community_partners:
    label: 'Community partners'
    angle: 'Shared benefit for nearby makers, markets, and organizers.'
    rationale: 'Partners can amplify the event through trusted local channels.'
  event_calendars:
    label: 'Event calendars'
    angle: 'Structured listing with date, place, and short reason to attend.'
    rationale: 'Calendar teams want clean listing-ready copy.'

@step =
  desc: 'Identify draft audience profiles from source material.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    artifactKey = 'source_material'
    sourceMaterial = await L.need artifactKey
    throw new Error "[#{stepName}] Missing required artifact '#{artifactKey}'" unless sourceMaterial?

    configuredAudiences = M.getStepParam(stepName, 'priority_audiences') ? []
    throw new Error "[#{stepName}] priority_audiences must be a non-empty array" unless Array.isArray(configuredAudiences) and configuredAudiences.length > 0

    proofPoints = sourceMaterial.highlights ? []
    campaignName = sourceMaterial.campaign_name ? experiment.run?.campaign_name

    profiles = configuredAudiences.map (audienceKey, index) ->
      spec = defaultAudienceMap[audienceKey] ? {}
      audience_index: index + 1
      audience_key: audienceKey
      audience_label: spec.label ? audienceKey
      angle: spec.angle ? 'General awareness of the campaign.'
      rationale: spec.rationale ? 'Relevant audience for reviewed outreach drafts.'
      recommended_channel: if audienceKey is 'event_calendars' then 'listing_submission' else 'reviewed_email_draft'
      campaign_name: campaignName
      proof_points: proofPoints.slice(0, 2)
      review_required: true

    payload =
      generated_for: campaignName
      audience_count: profiles.length
      profiles: profiles
      notes:
        source_material_key: 'source_material'
        review_owner: experiment.run?.review_owner
        draft_only: true

    L.make 'audience_profiles', payload
    L.done()
    return
