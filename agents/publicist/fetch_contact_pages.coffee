#!/usr/bin/env coffee

axios = require 'axios'
cheerio = require 'cheerio'

SEARCH_ENGINE_HOSTS = new Set([
  'google.com'
  'www.google.com'
  'bing.com'
  'www.bing.com'
  'search.yahoo.com'
  'duckduckgo.com'
  'www.duckduckgo.com'
  'yandex.com'
  'www.yandex.com'
])

isBlank = (value) ->
  String(value ? '').trim().length is 0

normalizeHost = (value) ->
  String(value ? '').trim().toLowerCase()

sameApprovedHost = (a, b) ->
  left = normalizeHost a
  right = normalizeHost b
  return false unless left.length and right.length
  return true if left is right
  return true if left is "www.#{right}"
  return true if right is "www.#{left}"
  false

extractEmails = (text) ->
  seen = new Set()
  out = []
  matches = String(text ? '').match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/ig) ? []
  for match in matches
    email = String(match).trim().toLowerCase()
    continue unless email.length
    continue if seen.has(email)
    seen.add email
    out.push email
  out

cleanSnippet = (value) ->
  String(value ? '')
    .replace(/\s+/g, ' ')
    .replace(/\b(privacy|terms|cookie settings|sign in|get started|menu|navigation|skip to content)\b/ig, ' ')
    .replace(/\s+/g, ' ')
    .trim()

extractContactPageDetails = (html, pageUrl) ->
  $ = cheerio.load String(html ? '')
  $('script, style, iframe, noscript, svg, canvas, nav, header, footer, aside, menu').remove()
  $('[class*="cookie"], [id*="cookie"], [class*="consent"], [id*="consent"], [class*="banner"], [id*="banner"]').remove()
  $('[class*="nav"], [id*="nav"], [class*="menu"], [id*="menu"], [class*="tracking"], [id*="tracking"], [src*="googletagmanager"], [href*="login"], [href*="account"]').remove()

  collectBlockText = (selector, limit = 24) ->
    rows = []
    $(selector).slice(0, limit).each (_, el) ->
      text = cleanSnippet($(el).text())
      return unless text.length
      return if /googletagmanager|window\.|document\.|localStorage|graphql|__BUILD_ID__/i.test(text)
      return if text.length < 20
      rows.push text
    rows

  pageTitle = cleanSnippet $('title').first().text()
  metaDescription = cleanSnippet $('meta[name="description"]').attr('content')
  headings = collectBlockText 'h1, h2', 12
  paragraphs = collectBlockText 'p', 24

  ordered = []
  seenText = new Set()
  pushUnique = (text) ->
    value = cleanSnippet text
    return unless value.length
    return if seenText.has value
    seenText.add value
    ordered.push value

  pushUnique metaDescription if metaDescription.length
  for text in headings
    pushUnique text
  for text in paragraphs
    pushUnique text

  cleanTextExcerpt = ordered.join(' ').replace(/\s+/g, ' ').trim()
  cleanTextExcerpt = if cleanTextExcerpt.length then cleanTextExcerpt.slice(0, 1000) else 'No useful content extracted'

  baseUrl = new URL pageUrl
  socialHosts = ['twitter.com', 'x.com', 'linkedin.com', 'facebook.com', 'instagram.com', 'youtube.com', 'bsky.app', 'mastodon.social']
  socialSeen = new Set()
  foundSocialLinks = []
  $('a[href]').each (_, el) ->
    href = String($(el).attr('href') ? '').trim()
    return unless href.length
    try
      absolute = new URL(href, baseUrl)
      host = normalizeHost absolute.hostname
      return unless socialHosts.some((prefix) -> host is prefix or host.endsWith(".#{prefix}"))
      text = absolute.toString()
      return if socialSeen.has text
      socialSeen.add text
      foundSocialLinks.push text
    catch
      return

  formSeen = new Set()
  foundContactForms = []
  $('form').each (_, el) ->
    action = String($(el).attr('action') ? '').trim()
    method = String($(el).attr('method') ? 'GET').trim().toUpperCase()
    try
      absolute = if action.length then new URL(action, baseUrl).toString() else pageUrl
      key = "#{method} #{absolute}"
      return if formSeen.has key
      formSeen.add key
      foundContactForms.push
        method: method
        url: absolute
    catch
      return

  {
    page_title: pageTitle
    clean_text_excerpt: cleanTextExcerpt
    found_emails: extractEmails("#{pageTitle}\n#{metaDescription}\n#{ordered.join("\n")}\n#{$.text()}")
    found_contact_forms: foundContactForms
    found_social_links: foundSocialLinks
  }

normalizeApprovedUrl = (raw) ->
  text = String(raw ? '').trim()
  return { error: 'blank_url' } unless text.length
  return { error: 'wildcards_not_allowed' } if /[*?]/.test(text)
  try
    parsed = new URL text
    return { error: 'invalid_protocol' } unless /^https?:$/i.test(parsed.protocol)
    host = normalizeHost parsed.hostname
    return { error: 'search_engine_domain_not_allowed' } if SEARCH_ENGINE_HOSTS.has(host)
    return { error: 'query_string_not_allowed' } if parsed.search?.length
    {
      url: parsed.toString()
      host: host
    }
  catch
    { error: 'invalid_url' }

approvedRows = (doc) ->
  rows = []
  for request in (doc?.contact_discovery_requests ? [])
    for proposed in (request?.proposed_urls ? [])
      status = String(proposed?.review_status ? 'planned_only').trim().toLowerCase()
      continue unless status is 'approved'
      rows.push
        request_id: request.request_id ? ''
        candidate_id: request.candidate_id ? ''
        organization_name: request.organization_name ? ''
        audience: request.audience ? ''
        url: proposed.url ? ''
        reviewer_notes: proposed.reviewer_notes ? ''
  rows

@step =
  desc: 'Fetch approved contact/about/press pages for qualified targets.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    contactDiscoveryKey = 'contact_discovery_requests'
    contactDiscovery = await L.need contactDiscoveryKey
    throw new Error "[#{stepName}] Missing required artifact '#{contactDiscoveryKey}'" unless Array.isArray(contactDiscovery?.contact_discovery_requests)

    timeoutMs = Number(M.getStepParam('fetch_research', 'timeout_ms') ? 5000)
    maxResponseBytes = Number(M.getStepParam('fetch_research', 'max_response_bytes') ? 262144)

    results = []
    skipped = []

    for row in approvedRows(contactDiscovery)
      normalized = normalizeApprovedUrl row.url
      if normalized?.error?
        skipped.push
          request_id: row.request_id
          url: row.url
          reason: normalized.error
        continue

      result =
        request_id: row.request_id
        candidate_id: row.candidate_id
        organization_name: row.organization_name
        audience: row.audience
        url: normalized.url
        status_code: null
        page_title: ''
        clean_text_excerpt: ''
        found_emails: []
        found_contact_forms: []
        found_social_links: []
        fetched_at: null
        redirect_target: null
        errors: []

      try
        response = await axios.get normalized.url,
          timeout: timeoutMs
          maxContentLength: maxResponseBytes
          maxBodyLength: maxResponseBytes
          responseType: 'text'
          maxRedirects: 5
          validateStatus: -> true
          beforeRedirect: (options) ->
            nextHost = String(options?.hostname ? '').toLowerCase()
            throw new Error 'redirect_outside_allowed_hostname' unless sameApprovedHost(nextHost, normalized.host)
          headers:
            'User-Agent': 'publicist-contact-fetch/1.0'
            'Accept': 'text/html, text/plain;q=0.9, */*;q=0.1'

        result.status_code = response.status
        result.fetched_at = new Date().toISOString()
        finalUrl = String(response.request?.res?.responseUrl ? normalized.url)

        try
          finalHost = new URL(finalUrl).hostname.toLowerCase()
          unless sameApprovedHost(finalHost, normalized.host)
            result.errors.push 'redirect_outside_allowed_hostname'
          else if finalUrl isnt normalized.url
            result.redirect_target = finalUrl
        catch
          result.errors.push 'invalid_final_url'

        contentType = String(response.headers?['content-type'] ? '')
        if /^text\/html\b/i.test(contentType) or contentType.length is 0
          details = extractContactPageDetails response.data, finalUrl
          result.page_title = details.page_title
          result.clean_text_excerpt = details.clean_text_excerpt
          result.found_emails = details.found_emails
          result.found_contact_forms = details.found_contact_forms
          result.found_social_links = details.found_social_links
        else if /^text\//i.test(contentType)
          text = String(response.data ? '').replace(/\s+/g, ' ').trim()
          result.clean_text_excerpt = if text.length then text.slice(0, 1000) else 'No useful content extracted'
          result.found_emails = extractEmails text
        else
          result.errors.push "unsupported_content_type: #{contentType}"
          result.clean_text_excerpt = 'No useful content extracted'
      catch err
        result.fetched_at = new Date().toISOString()
        result.clean_text_excerpt = 'No useful content extracted'
        result.errors.push String(err?.message ? err)

      results.push result

    for request in (contactDiscovery.contact_discovery_requests ? [])
      for proposed in (request.proposed_urls ? [])
        status = String(proposed?.review_status ? 'planned_only').trim().toLowerCase()
        continue if status is 'approved'
        skipped.push
          request_id: request.request_id ? ''
          url: proposed.url ? ''
          reason: if status is 'rejected' then 'url_rejected' else 'url_not_approved'

    payload =
      generated_for: contactDiscovery.generated_for ? experiment.run?.campaign_name
      campaign_source_hash: contactDiscovery.campaign_source_hash ? null
      fetch_mode: 'approved_contact_page_get_only'
      timeout_ms: timeoutMs
      max_response_bytes: maxResponseBytes
      results: results
      skipped: skipped
      summary:
        approved_url_count: approvedRows(contactDiscovery).length
        fetched_result_count: results.length
        skipped_count: skipped.length

    L.make 'contact_page_results', payload
    L.done()
    return
