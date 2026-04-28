#!/usr/bin/env coffee

axios = require 'axios'
cheerio = require 'cheerio'

isBlank = (value) ->
  String(value ? '').trim().length is 0

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

normalizeAllowedTarget = (raw, allowQueryString = false) ->
  text = String(raw ? '').trim()
  return null unless text.length
  return { error: 'wildcards_not_allowed' } if /[*?]/.test(text)
  if /^https?:\/\//i.test(text)
    try
      parsed = new URL(text)
      return null unless /^https?:$/i.test(parsed.protocol)
      host = parsed.hostname.toLowerCase()
      return { error: 'search_engine_domain_not_allowed' } if SEARCH_ENGINE_HOSTS.has(host)
      return { error: 'query_string_not_allowed' } if parsed.search?.length and allowQueryString isnt true
      return
        source: text
        host: host
        url: parsed.toString()
        isFullUrl: true
    catch
      return { error: 'invalid_url' }

  host = text.replace(/^https?:\/\//i, '').replace(/\/.*$/, '').trim().toLowerCase()
  return null unless host.length
  return { error: 'search_engine_domain_not_allowed' } if SEARCH_ENGINE_HOSTS.has(host)
  {
    source: text
    host: host
    url: "https://#{host}/"
    isFullUrl: false
  }

extractTitleAndText = (html) ->
  $ = cheerio.load String(html ? '')
  title = $('title').first().text().replace(/\s+/g, ' ').trim()
  text = $('body').text().replace(/\s+/g, ' ').trim()
  {
    title: title
    short_text_excerpt: text.slice(0, 500)
  }

isApprovedResearchRequest = (request) ->
  String(request?.status ? '').trim().toLowerCase() is 'approved_for_research' and Array.isArray(request?.allowed_domains) and request.allowed_domains.length > 0

sameApprovedHost = (a, b) ->
  left = String(a ? '').trim().toLowerCase()
  right = String(b ? '').trim().toLowerCase()
  return false unless left.length and right.length
  return true if left is right
  return true if left is "www.#{right}"
  return true if right is "www.#{left}"
  false

@step =
  desc: 'Fetch allowlisted read-only research content for approved publicist requests.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    researchRequestsKey = 'research_requests'
    researchRequests = await L.need researchRequestsKey
    throw new Error "[#{stepName}] Missing required artifact '#{researchRequestsKey}'" unless Array.isArray(researchRequests?.research_requests)

    timeoutMs = Number(M.getStepParam(stepName, 'timeout_ms') ? 5000)
    maxResponseBytes = Number(M.getStepParam(stepName, 'max_response_bytes') ? 262144)

    results = []
    skipped = []

    for request in researchRequests.research_requests
      requestId = request?.request_id ? ''
      unless String(request?.status ? '').trim().toLowerCase() is 'approved_for_research'
        skipped.push
          request_id: requestId
          reason: 'status_not_approved_for_research'
        continue

      unless Array.isArray(request?.allowed_domains) and request.allowed_domains.length > 0
        skipped.push
          request_id: requestId
          reason: 'allowed_domains_empty'
        continue

      allowQueryString = request?.allow_query_string is true
      normalizedTargets = []
      invalidReasons = []
      for target in request.allowed_domains
        normalized = normalizeAllowedTarget(target, allowQueryString)
        if normalized?.error?
          invalidReasons.push "#{String(target ? '').trim()}:#{normalized.error}"
          continue
        normalizedTargets.push normalized if normalized?
      unless normalizedTargets.length
        skipped.push
          request_id: requestId
          reason: 'allowed_domains_invalid'
          detail: invalidReasons
        continue

      for target in normalizedTargets
        row =
          request_id: requestId
          audience: request.audience ? ''
          organization: request.organization ? ''
          contact_name: request.contact_name ? ''
          query_terms: request.suggested_search_terms ? []
          url: target.url
          status_code: null
          title: ''
          short_text_excerpt: ''
          fetched_at: null
          redirect_target: null
          errors: []

        try
          response = await axios.get target.url,
            timeout: timeoutMs
            maxContentLength: maxResponseBytes
            maxBodyLength: maxResponseBytes
            responseType: 'text'
            maxRedirects: 5
            validateStatus: -> true
            beforeRedirect: (options, responseDetails) ->
              nextHost = String(options?.hostname ? '').toLowerCase()
              throw new Error "redirect_outside_allowed_hostname" unless sameApprovedHost(nextHost, target.host)
            headers:
              'User-Agent': 'publicist-research-fetch/1.0'
              'Accept': 'text/html, text/plain;q=0.9, */*;q=0.1'

          row.status_code = response.status
          row.fetched_at = new Date().toISOString()
          finalUrl = String(response.request?.res?.responseUrl ? target.url)
          try
            finalHost = new URL(finalUrl).hostname.toLowerCase()
            unless sameApprovedHost(finalHost, target.host)
              row.errors.push 'redirect_outside_allowed_hostname'
            else if finalUrl isnt target.url
              row.redirect_target = finalUrl
          catch
            row.errors.push 'invalid_final_url'
          contentType = String(response.headers?['content-type'] ? '')
          if /^text\/html\b/i.test(contentType) or contentType.length is 0
            extracted = extractTitleAndText response.data
            row.title = extracted.title
            row.short_text_excerpt = extracted.short_text_excerpt
          else if /^text\//i.test(contentType)
            text = String(response.data ? '').replace(/\s+/g, ' ').trim()
            row.short_text_excerpt = text.slice(0, 500)
          else
            row.errors.push "unsupported_content_type: #{contentType}"
        catch err
          row.fetched_at = new Date().toISOString()
          row.errors.push String(err?.message ? err)

        results.push row

    payload =
      generated_for: experiment.run?.campaign_name
      fetch_mode: 'approved_allowlist_get_only'
      timeout_ms: timeoutMs
      max_response_bytes: maxResponseBytes
      results: results
      skipped: skipped
      summary:
        approved_request_count: researchRequests.research_requests.filter(isApprovedResearchRequest).length
        fetched_result_count: results.length
        skipped_count: skipped.length

    L.make 'research_results', payload
    L.done()
    return
