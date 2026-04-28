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

@step =
  desc: 'Build a reviewed draft-only contact ledger for outreach targets.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    audienceProfilesKey = 'audience_profiles'
    audienceProfiles = await L.need audienceProfilesKey
    throw new Error "[#{stepName}] Missing required artifact '#{audienceProfilesKey}'" unless audienceProfiles?.profiles?

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

    payload =
      generated_for: audienceProfiles.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: audienceProfiles.campaign_source_hash ? null
      ledger_count: ledgerEntries.length
      entries: ledgerEntries
      notes:
        placeholder_contacts_only: true
        draft_only: true
        no_live_actions: true

    L.make 'contact_ledger', payload
    L.done()
    return
