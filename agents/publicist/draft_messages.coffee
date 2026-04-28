#!/usr/bin/env coffee

compactText = (value) ->
  String(value ? '')
    .replace(/\s+/g, ' ')
    .trim()

preserveHumanRevision = (draft, existingDraft, currentSourceHash) ->
  return draft unless existingDraft?.revised_by_human is true
  return draft unless String(existingDraft?.campaign_source_hash ? '') is String(currentSourceHash ? '')
  merged = Object.assign {}, draft
  merged.subject = existingDraft.subject if typeof existingDraft.subject is 'string'
  merged.email_body = existingDraft.email_body if typeof existingDraft.email_body is 'string'
  merged.revised_by_human = true
  merged.revised_at = existingDraft.revised_at ? new Date().toISOString()
  merged

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
    messageDraftsTarget = experiment.artifacts?.message_drafts?.target
    existingDoc = if messageDraftsTarget? then M.theLowdown(messageDraftsTarget)?.value else null
    existingDrafts = if Array.isArray(existingDoc?.drafts) then existingDoc.drafts else []
    existingByDraftId = {}
    for draft in existingDrafts when draft?.draft_id?
      existingByDraftId[draft.draft_id] = draft

    baseHighlights = (sourceMaterial.highlights ? []).slice(0, 2).join(' ')
    drafts = audienceProfiles.profiles.map (profile) ->
      ledgerEntry = contactLedger.entries.find (entry) -> entry.audience is profile.audience_label
      hook = compactText(profile.angle)
      draftId = "draft_#{profile.audience_key}"
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

      draft = 
        audience_key: profile.audience_key
        draft_id: draftId
        campaign_source_hash: sourceMaterial.source_hash ? null
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

      preserveHumanRevision draft, existingByDraftId[draftId], sourceMaterial.source_hash

    payload =
      generated_for: sourceMaterial.campaign_name
      campaign_source_hash: sourceMaterial.source_hash ? null
      draft_count: drafts.length
      drafts: drafts
      constraints:
        live_send_enabled: false
        network_posting_enabled: false
        requires_human_review: true

    L.make 'message_drafts', payload
    L.done()
    return
