#!/usr/bin/env coffee

compactText = (value) ->
  String(value ? '')
    .replace(/\s+/g, ' ')
    .trim()

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

    baseHighlights = (sourceMaterial.highlights ? []).slice(0, 2).join(' ')
    drafts = audienceProfiles.profiles.map (profile) ->
      ledgerEntry = contactLedger.entries.find (entry) -> entry.audience is profile.audience_label
      hook = compactText(profile.angle)
      subject = "#{sourceMaterial.brand_name}: #{profile.audience_label} draft"
      emailBody = [
        "Hi #{ledgerEntry?.contact_name ? profile.audience_label},"
        ""
        "I’m sharing a draft outreach note for review regarding #{sourceMaterial.campaign_name} in #{sourceMaterial.launch_city ? 'the local market'}."
        "#{hook}"
        ""
        "#{baseHighlights}"
        ""
        "#{callToAction}"
        ""
        "Best,"
        signatureName
      ].join("\n")

      followUp = "Follow up with #{String(profile.audience_label ? '').toLowerCase()} only after human review and explicit approval."

      audience_key: profile.audience_key
      draft_id: "draft_#{profile.audience_key}"
      audience_label: profile.audience_label
      organization: ledgerEntry?.organization ? null
      contact_name: ledgerEntry?.contact_name ? null
      contact_role: ledgerEntry?.contact_role ? null
      contact_channel: ledgerEntry?.contact_channel ? null
      subject: subject
      pitch_summary: hook
      email_body: emailBody
      follow_up_note: followUp
      review_required: true

    payload =
      generated_for: sourceMaterial.campaign_name
      draft_count: drafts.length
      drafts: drafts
      constraints:
        live_send_enabled: false
        network_posting_enabled: false
        requires_human_review: true

    L.make 'message_drafts', payload
    L.done()
    return
