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

entryKeyByOrgAudience = (entry) ->
  "#{normalizeKey(entry?.audience)}::#{normalizeKey(entry?.organization)}"

dedupeStrings = (rows) ->
  seen = new Set()
  out = []
  for row in rows
    text = normalizeText row
    continue unless text.length
    key = text.toLowerCase()
    continue if seen.has key
    seen.add key
    out.push text
  out

dedupeForms = (rows) ->
  seen = new Set()
  out = []
  for row in rows when row?
    method = normalizeText(row.method ? 'GET').toUpperCase()
    url = normalizeText row.url
    continue unless url.length
    key = "#{method} #{url.toLowerCase()}"
    continue if seen.has key
    seen.add key
    out.push
      method: method
      url: url
  out

aggregateResults = (results) ->
  byCandidateId = {}
  byOrgAudience = {}
  for row in results when row?
    candidateIdKey = normalizeKey row.candidate_id
    orgAudienceKey = "#{normalizeKey(row.audience)}::#{normalizeKey(row.organization_name)}"
    summary =
      contact_page_url: normalizeText(row.redirect_target ? row.url)
      discovered_emails: dedupeStrings(row.found_emails ? [])
      discovered_contact_forms: dedupeForms(row.found_contact_forms ? [])
      discovered_social_links: dedupeStrings(row.found_social_links ? [])
      contact_discovery_status: if row.errors?.length then 'fetched_with_errors' else 'fetched'
      contact_discovery_notes: if row.errors?.length then "fetch errors: #{(row.errors ? []).join(' | ')}" else "fetched #{normalizeText(row.url)}"
      fetched_at: row.fetched_at ? null
      status_code: row.status_code ? null

    if candidateIdKey.length
      byCandidateId[candidateIdKey] ?= []
      byCandidateId[candidateIdKey].push summary
    if orgAudienceKey isnt '::'
      byOrgAudience[orgAudienceKey] ?= []
      byOrgAudience[orgAudienceKey].push summary

  pickMerged = (rows) ->
    return null unless rows?.length
    preferred = rows.find (row) -> row.contact_discovery_status is 'fetched' and row.status_code? and Number(row.status_code) < 400
    base = preferred ? rows[0]
    {
      contact_page_url: base.contact_page_url
      discovered_emails: dedupeStrings(rows.flatMap((row) -> row.discovered_emails ? []))
      discovered_contact_forms: dedupeForms(rows.flatMap((row) -> row.discovered_contact_forms ? []))
      discovered_social_links: dedupeStrings(rows.flatMap((row) -> row.discovered_social_links ? []))
      contact_discovery_status: if rows.some((row) -> row.contact_discovery_status is 'fetched') then 'fetched' else base.contact_discovery_status
      contact_discovery_notes: dedupeStrings(rows.map((row) -> row.contact_discovery_notes)).join(' | ')
    }

  {
    byCandidateId: Object.fromEntries(Object.entries(byCandidateId).map(([key, rows]) -> [key, pickMerged(rows)]))
    byOrgAudience: Object.fromEntries(Object.entries(byOrgAudience).map(([key, rows]) -> [key, pickMerged(rows)]))
  }

@step =
  desc: 'Merge approved contact page fetch results into the publicist contact ledger.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    contactLedgerKey = 'contact_ledger'
    contactPageResultsKey = 'contact_page_results'

    contactLedger = await L.need contactLedgerKey
    contactPageResults = await L.need contactPageResultsKey

    contactLedger = resolveArtifactPayload(M, experiment, contactLedgerKey, (value) -> Array.isArray(value?.entries)).value ? contactLedger
    contactPageResults = resolveArtifactPayload(M, experiment, contactPageResultsKey, (value) -> Array.isArray(value?.results)).value ? contactPageResults

    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless Array.isArray(contactLedger?.entries)
    throw new Error "[#{stepName}] Missing required artifact '#{contactPageResultsKey}'" unless Array.isArray(contactPageResults?.results)

    aggregates = aggregateResults contactPageResults.results
    enrichedCount = 0

    entries = contactLedger.entries.map (entry) ->
      candidateIdKey = normalizeKey entry.source_candidate_id
      orgAudienceKey = entryKeyByOrgAudience entry
      discovered = null
      if candidateIdKey.length and aggregates.byCandidateId[candidateIdKey]?
        discovered = aggregates.byCandidateId[candidateIdKey]
      else if aggregates.byOrgAudience[orgAudienceKey]?
        discovered = aggregates.byOrgAudience[orgAudienceKey]

      return entry unless discovered?

      enrichedCount += 1
      merged = Object.assign {}, entry
      merged.contact_page_url = if normalizeText(entry.contact_page_url).length then entry.contact_page_url else discovered.contact_page_url
      merged.discovered_emails = dedupeStrings((entry.discovered_emails ? []).concat(discovered.discovered_emails ? []))
      merged.discovered_contact_forms = dedupeForms((entry.discovered_contact_forms ? []).concat(discovered.discovered_contact_forms ? []))
      merged.discovered_social_links = dedupeStrings((entry.discovered_social_links ? []).concat(discovered.discovered_social_links ? []))
      merged.contact_discovery_status = if normalizeText(entry.contact_discovery_status).length then entry.contact_discovery_status else discovered.contact_discovery_status
      merged.contact_discovery_notes = if normalizeText(entry.contact_discovery_notes).length then entry.contact_discovery_notes else discovered.contact_discovery_notes
      merged.review_required = true
      merged

    payload = Object.assign {}, contactLedger,
      entries: entries
      ledger_count: entries.length
      notes: Object.assign {}, contactLedger.notes ? {},
        contact_page_results_merged: enrichedCount
        draft_only: true
        no_live_actions: true

    L.make 'contact_ledger_enriched', payload
    L.done()
    return
