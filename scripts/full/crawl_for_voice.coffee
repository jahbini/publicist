fs = require 'fs'
path = require 'path'
axios = require 'axios'
cheerio = require 'cheerio'

@step =
  desc: "Crawl site pages and build memo-resident voice dataset"

  action: (S) ->
    base = S.param 'base'
    outputKey = S.param 'output_key'
    validFraction = Number S.param 'valid_fraction'
    minStoryWords = parseInt S.param 'min_story_words'
    maxPages = parseInt S.param 'max_pages', 1000
    pauseSec = Number S.param 'pause_sec', 0.4
    userAgent = S.param 'user_agent', 'Mozilla/5.0'
    requestTimeout = parseInt S.param 'request_timeout', 15000
    evalDir = S.param 'eval_dir'

    fs.mkdirSync evalDir, recursive: true
    logPath = path.join evalDir, "#{S.stepName}.log"
    log = (msg) ->
      line = "[#{new Date().toISOString()}] #{msg}"
      try fs.appendFileSync logPath, line + "\n" catch then null
      console.log line

    sleep = (ms) -> new Promise (resolve) -> setTimeout resolve, ms
    startUrl = "https://#{base}/"

    getHtml = (target) ->
      axios.get(target,
        timeout: requestTimeout
        headers: { 'User-Agent': userAgent }
      ).then((r) -> r.data).catch (e) ->
        log "crawl error #{target}: #{e.message}"
        ''

    discoverPages = async ->
      queue = [startUrl]
      seen = new Set()
      pages = []
      while queue.length and pages.length < maxPages
        url = queue.shift()
        continue if seen.has url
        seen.add url
        html = await getHtml url
        continue unless html
        pages.push [url, html]
        $ = cheerio.load html
        $('a[href]').each (_, node) ->
          href = $(node).attr 'href'
          return unless href?.endsWith '.html'
          nextUrl = new URL(href, startUrl).href
          queue.push nextUrl unless seen.has(nextUrl) or queue.includes(nextUrl)
        await sleep pauseSec * 1000
      pages

    normalize = (s) -> String(s ? '').replace(/\s+/g, ' ').trim()
    splitParagraphs = (txt) -> (p.trim() for p in String(txt).split(/\n{2,}/) when p.trim().length)

    pages = await discoverPages()
    examples = []
    for [pageUrl, html] in pages
      $ = cheerio.load html
      title = $('h2').eq(1).text()?.trim() or $('title').text()?.trim() or 'Untitled'
      body = normalize $('#bloviation').text()
      continue unless body.split(/\s+/).length >= minStoryWords
      for para, idx in splitParagraphs(body)
        examples.push
          meta:
            title: title
            url: pageUrl
            paragraph_index: idx + 1
          prompt: "This is paragraph #{idx + 1} from \"#{title}\". Summarize it and describe its tone."
          completion: ''

    examples.sort -> Math.random() - 0.5
    validN = Math.max 1, Math.floor(examples.length * validFraction)
    valid = examples.slice 0, validN
    train = examples.slice validN

    S.saveThis "#{outputKey}:train", train
    S.saveThis "#{outputKey}:valid", valid
    S.saveThis "#{S.stepName}:train_count", train.length
    S.saveThis "#{S.stepName}:valid_count", valid.length
    S.done()
    return
