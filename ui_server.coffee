#!/usr/bin/env coffee
###
UI server notes
---------------------------------------------------------------------------
- Preferred refresh workflow for testing:
  switch pipe or change pipeline from the UI.
- In this environment that reliably kills the old UI server and starts a new
  one, so use that before spawning a separate test instance on another port.
- `UI_PORT` still exists for fallback testing when needed.
###
fs = require 'fs'
path = require 'path'
http = require 'http'
yaml = require 'js-yaml'
{ spawn } = require 'child_process'
{ DatabaseSync } = require 'node:sqlite'

CWD = process.env.CWD ? process.cwd()
PORT = Number(process.env.UI_PORT ? 2345)
UI_BIND_MODE = String(process.env.UI_BIND_MODE ? (if process.argv[2] is 'net' then 'net' else 'local'))
HOST = if UI_BIND_MODE is 'net' then '0.0.0.0' else '127.0.0.1'
repeatLoop =
  enabled: false
  payload: null
  timer: null
  next_launch_at: null
UI_CONTROL_PATH = path.join(CWD, 'state', 'ui-control.json')
CONTROL_OVERRIDE_PATH = path.join(CWD, 'control_override.yaml')
OVERRIDE_PATH = path.join(CWD, 'override.yaml')
MERGE_RUN_PATH = path.join(CWD, 'state', 'merge-run.json')
PUBLICIST_SOURCE_RELATIVE_PATH = path.join('source', 'publicist_source.txt')
PUBLICIST_CAMPAIGN_CONFIG_RELATIVE_PATH = path.join('source', 'publicist_campaign.yaml')
DEFAULT_PUBLICIST_SOURCE_TEXT = "Describe this campaign here.\n"
DEFAULT_PUBLICIST_CAMPAIGN_CONFIG_TEXT = """priority_audiences:
  - technical_press
  - industry_partners
  - research_labs
  - pilot_customers
"""

readJson = (p, fallback = null) ->
  return fallback unless fs.existsSync(p)
  try JSON.parse(fs.readFileSync(p, 'utf8')) catch then fallback

readText = (p, fallback = '') ->
  return fallback unless fs.existsSync(p)
  try fs.readFileSync(p, 'utf8') catch then fallback

writeText = (p, text) ->
  fs.mkdirSync path.dirname(p), { recursive: true }
  fs.writeFileSync p, text, 'utf8'

normalizeText = (value) ->
  String(value ? '').trim()

ensurePublicistSourceFile = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  sourcePath = path.join(base, PUBLICIST_SOURCE_RELATIVE_PATH)
  unless fs.existsSync(sourcePath)
    writeText sourcePath, DEFAULT_PUBLICIST_SOURCE_TEXT
  sourcePath

ensurePublicistCampaignConfigFile = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  configPath = path.join(base, PUBLICIST_CAMPAIGN_CONFIG_RELATIVE_PATH)
  unless fs.existsSync(configPath)
    writeText configPath, DEFAULT_PUBLICIST_CAMPAIGN_CONFIG_TEXT
  configPath

looksLikeExecRoot = (candidate) ->
  return false unless typeof candidate is 'string' and candidate.length
  try
    fs.existsSync(path.join(candidate, 'ui', 'index.html')) and fs.existsSync(path.join(candidate, 'pipeline_runner.coffee'))
  catch
    false

resolveExecRoot = ->
  candidates = []
  seen = new Set()

  pushCandidate = (candidate) ->
    return unless typeof candidate is 'string' and candidate.length
    absolute = path.resolve(candidate)
    return if seen.has(absolute)
    seen.add absolute
    candidates.push absolute

  pushCandidate process.env.EXEC if process.env.EXEC?
  pushCandidate path.dirname(__filename)
  pushCandidate process.cwd()
  pushCandidate CWD
  pushCandidate path.dirname(CWD)
  pushCandidate path.dirname(path.dirname(CWD))

  for candidate in candidates when looksLikeExecRoot(candidate)
    return candidate

  candidates[0] ? path.dirname(__filename)

EXEC_ROOT = resolveExecRoot()
RUNNER = path.join(EXEC_ROOT, 'pipeline_runner.coffee')
MERGE_SCRIPT = path.join(EXEC_ROOT, 'merge_sqlite_dbs.coffee')

PIPES_ROOT = path.join(EXEC_ROOT, 'pipes')
DEFAULT_KAG_KEYWORDS = [
  'joy'
  'contentment'
  'sadness'
  'grief'
  'fear'
  'anxiety'
  'anger'
  'frustration'
  'disgust'
  'shame'
  'surprise'
  'neutral'
]

isProcessAlive = (pid) ->
  num = Number(pid)
  return false unless Number.isFinite(num) and num > 0
  try
    process.kill num, 0
    true
  catch
    false

normalizeUiRun = (run) ->
  current = if run? and typeof run is 'object' and not Array.isArray(run) then Object.assign({}, run) else {}
  pid = Number(current.pid ? 0)
  alive = isProcessAlive(pid)

  if alive and current.status in ['launching', 'running', 'skipped', 'killing']
    current.status = if current.status is 'killing' then 'killing' else 'running'
    current.pid = pid
    current.is_attached = true
    current.is_process_alive = true
    return current

  current.is_attached = false
  current.is_process_alive = alive
  current

normalizeMergeRun = (run) ->
  current = if run? and typeof run is 'object' and not Array.isArray(run) then Object.assign({}, run) else {}
  pid = Number(current.pid ? 0)
  alive = isProcessAlive(pid)

  if alive and current.status in ['launching', 'running']
    current.status = 'running'
    current.pid = pid
    current.is_process_alive = true
    return current

  current.is_process_alive = alive
  current

readMergeRun = ->
  normalizeMergeRun readJson(MERGE_RUN_PATH, {})

resolveCoffeeBin = ->
  localCoffee = path.join(EXEC_ROOT, 'node_modules', '.bin', 'coffee')
  return localCoffee if fs.existsSync(localCoffee)
  'coffee'

workspacePipeName = (workspacePath = CWD) ->
  rel = path.relative(PIPES_ROOT, workspacePath)
  return null if not rel? or rel.startsWith('..') or path.isAbsolute(rel) or rel is ''
  rel.split(path.sep)[0] ? null

inferModelIdFromPipeName = (pipeName) ->
  name = String(pipeName ? '').trim()
  return '' unless name.length
  underscoreIndex = name.indexOf('_')
  return '' unless underscoreIndex > 0 and underscoreIndex < name.length - 1
  organization = name.slice(0, underscoreIndex).trim()
  modelName = name.slice(underscoreIndex + 1).trim()
  return '' unless organization.length and modelName.length
  "#{organization}/#{modelName}"

listPipeDirectories = ->
  return [] unless fs.existsSync(PIPES_ROOT)
  names = fs.readdirSync(PIPES_ROOT).filter (name) ->
    full = path.join(PIPES_ROOT, name)
    try
      fs.statSync(full).isDirectory()
    catch
      false
  names.sort (a, b) -> String(a).localeCompare String(b)

buildPipeSummary = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  current = workspacePipeName(base)
  pipes = (name: name, is_active: name is current for name in listPipeDirectories())
  {
    root: PIPES_ROOT
    current: current
    workspace: base
    pipes: pipes
  }

writeUiRunPatch = (patch) ->
  runPath = path.join(CWD, 'state', 'ui-run.json')
  current = readJson(runPath, {})
  current = {} unless current? and typeof current is 'object' and not Array.isArray(current)
  next = Object.assign {}, current, patch
  writeText runPath, JSON.stringify(next, null, 2)
  next

readUiControl = ->
  current = readJson(UI_CONTROL_PATH, {})
  current = {} unless current? and typeof current is 'object' and not Array.isArray(current)
  current

writeUiControl = (patch) ->
  current = readUiControl()
  next = Object.assign {}, current, patch
  writeText UI_CONTROL_PATH, JSON.stringify(next, null, 2)
  next

dumpYaml = (value) ->
  yaml.dump value,
    lineWidth: 120
    noRefs: true

getByPath = (root, dottedPath) ->
  return undefined unless root? and typeof dottedPath is 'string' and dottedPath.length
  node = root
  for part in dottedPath.split('.')
    return undefined unless node? and typeof node is 'object'
    node = node[part]
  node

setByPath = (root, dottedPath, value) ->
  return root unless root? and typeof root is 'object' and typeof dottedPath is 'string' and dottedPath.length
  parts = dottedPath.split('.')
  node = root
  for part, index in parts
    if index is parts.length - 1
      node[part] = value
    else
      node[part] ?= {}
      node = node[part]
  root

deleteByPath = (root, dottedPath) ->
  return root unless root? and typeof root is 'object' and typeof dottedPath is 'string' and dottedPath.length
  parts = dottedPath.split('.')
  chain = []
  node = root
  for part in parts
    return root unless node? and typeof node is 'object'
    chain.push [node, part]
    node = node[part]

  [leafParent, leafKey] = chain[chain.length - 1]
  delete leafParent[leafKey]

  for index in [(chain.length - 2)..0]
    [parent, key] = chain[index]
    child = parent[key]
    break unless child? and typeof child is 'object' and not Array.isArray(child) and Object.keys(child).length is 0
    delete parent[key]

  root

loadDropdownOptions = (specPath) ->
  return [] unless typeof specPath is 'string' and specPath.length
  if specPath is 'db/kag_keywords'
    dbPath = path.join CWD, 'runtime.sqlite'
    fallbackRows = ({ key, label: key } for key in DEFAULT_KAG_KEYWORDS)
    return fallbackRows unless fs.existsSync dbPath
    db = null
    try
      db = new DatabaseSync dbPath
      rows = db.prepare("""
        SELECT DISTINCT keyword
        FROM kag_entries
        WHERE keyword IS NOT NULL AND TRIM(keyword) != ''
        ORDER BY keyword ASC
      """).all()
      mapped = ({
        key: String(row.keyword)
        label: String(row.keyword)
      } for row in rows when row?.keyword?)
      return mapped if mapped.length
      return fallbackRows
    catch
      return fallbackRows
    finally
      try db?.close() catch then null
  parts = specPath.split('/')
  return [] unless parts.length >= 3
  filePath = path.join CWD, parts[0], parts[1]
  keyParts = parts.slice(2)
  doc = readYaml filePath
  node = doc
  for key in keyParts
    return [] unless node? and typeof node is 'object'
    node = node[key]
  return [] unless node? and typeof node is 'object'
  rows = []
  for own key, value of node
    label = value?.text ? value?.character ? value?.label ? key
    rows.push { key, label }
  rows.sort (a, b) -> String(a.label).localeCompare String(b.label)
  rows

scanUiFields = (recipe, override, uiControl) ->
  pendingUi = uiControl?.ui_values ? {}
  rows = []

  buildLabel = (pathText) ->
    parts = String(pathText ? '').split('.')
    return pathText unless parts.length
    if parts.length >= 2
      stepName = parts[0]
      keyName = parts[parts.length - 1]
      return "#{stepName}: #{keyName}"
    pathText

  walk = (node, prefix = '') ->
    return unless node? and typeof node is 'object'
    if Array.isArray(node)
      directive = String(node[0] ? '')
      if directive is 'UI_checkbox'
        defaultValue = node[1] is true
        chosenValue = if Object::hasOwnProperty.call(pendingUi, prefix)
          pendingUi[prefix] is true
        else
          overrideValue = getByPath override, prefix
          if typeof overrideValue is 'boolean' then overrideValue else defaultValue
        rows.push
          path: prefix
          label: buildLabel(prefix)
          type: 'checkbox'
          default_value: defaultValue
          value: chosenValue
      else if directive is 'UI_dropdown'
        sourcePath = String(node[1] ? '')
        defaultValue = String(node[2] ? '')
        chosenValue = if Object::hasOwnProperty.call(pendingUi, prefix)
          String(pendingUi[prefix] ? '')
        else
          overrideValue = getByPath override, prefix
          if typeof overrideValue is 'string' then overrideValue else defaultValue
        sourceParts = sourcePath.split('/')
        rows.push
          path: prefix
          label: buildLabel(prefix)
          type: 'dropdown'
          default_value: defaultValue
          value: chosenValue
          source_path: sourcePath
          options: loadDropdownOptions(sourcePath)
      return

    return unless not Array.isArray(node)
    for own key, value of node
      currentPath = if prefix.length then "#{prefix}.#{key}" else key
      walk value, currentPath

  walk recipe
  rows.sort (a, b) -> String(a.path).localeCompare String(b.path)
  rows

readRecipe = (pipeline) ->
  return {} unless typeof pipeline is 'string' and pipeline.length
  readYaml path.join(EXEC_ROOT, 'config', "#{pipeline}.yaml")

listTopLevelPipelines = ->
  configDir = path.join(EXEC_ROOT, 'config')
  return [] unless fs.existsSync(configDir)
  names = fs.readdirSync(configDir).filter (name) ->
    return false unless /\.ya?ml$/i.test(name)
    full = path.join(configDir, name)
    try
      fs.statSync(full).isFile()
    catch
      false
  names
    .map (name) -> name.replace(/\.ya?ml$/i, '')
    .sort (a, b) -> String(a).localeCompare String(b)

pad2 = (n) ->
  text = String(Number(n) ? 0)
  if text.length < 2 then "0#{text}" else text

buildRunTag = ->
  now = new Date()
  hhmm = "#{pad2(now.getHours())}_#{pad2(now.getMinutes())}"
  {
    hh_mm: hhmm
    logdir: "pipe_#{hhmm}"
  }

tailText = (p, maxLines = 120) ->
  text = readText(p, '')
  lines = text.split /\r?\n/
  lines.slice(Math.max(lines.length - maxLines, 0)).join "\n"

listFiles = (dir) ->
  return [] unless fs.existsSync(dir)
  names = fs.readdirSync(dir).sort()
  out = []
  for name in names
    full = path.join(dir, name)
    stat = fs.statSync(full)
    out.push
      name: name
      path: full
      is_dir: stat.isDirectory()
      size: stat.size
      mtime: stat.mtime.toISOString()
  out

readJsonlTail = (p, maxRows = 80) ->
  return [] unless fs.existsSync(p)
  text = fs.readFileSync(p, 'utf8')
  rows = []
  for line in text.split(/\r?\n/) when line.trim().length
    try rows.push JSON.parse(line) catch then null
  rows.slice Math.max(rows.length - maxRows, 0)

latestLogStem = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  logDir = path.join(base, 'logs')
  return null unless fs.existsSync(logDir)
  names = fs.readdirSync(logDir).filter (name) -> /^pipe_\d{2}_\d{2}\.(log|err)$/.test(name)
  return null unless names.length
  stems = {}
  for name in names
    stem = name.replace /\.(log|err)$/, ''
    stems[stem] = true
  ordered = Object.keys(stems).sort()
  ordered[ordered.length - 1]

collectStepStates = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  stateDir = path.join(base, 'state')
  return [] unless fs.existsSync(stateDir)
  names = fs.readdirSync(stateDir).filter (name) -> /^step-.*\.json$/.test(name)
  rows = []
  for name in names
    row = readJson path.join(stateDir, name), {}
    continue unless row?
    rows.push row
  rows.sort (a, b) ->
    String(a.step ? '').localeCompare String(b.step ? '')

readOverride = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  foundational = {}
  pipeName = workspacePipeName(base)
  inferredModel = inferModelIdFromPipeName(pipeName)
  overridePath = path.join(base, 'override.yaml')

  parsed = if fs.existsSync(overridePath)
    try yaml.load(fs.readFileSync(overridePath, 'utf8')) ? {} catch then {}
  else
    {}

  parsed = {} unless parsed? and typeof parsed is 'object' and not Array.isArray(parsed)
  needsWrite = false

  if inferredModel.length
    parsed.run = {} unless parsed.run? and typeof parsed.run is 'object' and not Array.isArray(parsed.run)
    currentModel = String(parsed.run.model ? '').trim()
    if currentModel.length is 0
      parsed.run.model = inferredModel
      needsWrite = true

  if needsWrite or (inferredModel.length and not fs.existsSync(overridePath))
    writeText overridePath, dumpYaml(parsed)

  parsed

readControlOverride = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  controlOverridePath = path.join(base, 'control_override.yaml')
  return {} unless fs.existsSync controlOverridePath
  try yaml.load(fs.readFileSync(controlOverridePath, 'utf8')) ? {} catch then {}

readYaml = (p) ->
  target = p
  if not fs.existsSync(target) and typeof p is 'string'
    rel = path.relative(CWD, p)
    if rel? and not rel.startsWith('..') and not path.isAbsolute(rel)
      fallback = path.join(EXEC_ROOT, rel)
      target = fallback if fs.existsSync(fallback)
  return {} unless fs.existsSync target
  try yaml.load(fs.readFileSync(target, 'utf8')) ? {} catch then {}

buildControls = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  override = readOverride(base)
  controlOverride = readControlOverride(base)
  uiControl = readUiControl()
  pending = uiControl.pending ? {}
  pipelineName = pending.pipeline ? controlOverride.pipeline ? override.pipeline ? ''
  recipe = readRecipe(pipelineName)
  libraryDoc = readYaml path.join(EXEC_ROOT, 'data', 'jim_story_library.yaml')
  library = libraryDoc?.library ? {}
  recipeStoryStep = recipe?.select_story_recipe ? {}
  controlStoryStep = controlOverride?.select_story_recipe ? {}

  makeOptions = (shelfName) ->
    shelf = library?[shelfName] ? {}
    rows = []
    for own key, value of shelf
      label = value?.text ? value?.character ? key
      rows.push { key, label }
    rows.sort (a, b) -> String(a.label).localeCompare String(b.label)
    rows

  overrideObject = buildOverrideObject
    pipeline: pipelineName
    scene: pending.scene ? controlStoryStep.scene ? recipeStoryStep.scene ? ''
    arrival: pending.arrival ? controlStoryStep.arrival ? recipeStoryStep.arrival ? ''
    disturbance: pending.disturbance ? controlStoryStep.disturbance ? recipeStoryStep.disturbance ? ''
    reflection: pending.reflection ? controlStoryStep.reflection ? recipeStoryStep.reflection ? ''
    realization: pending.realization ? controlStoryStep.realization ? recipeStoryStep.realization ? ''
    ui_values: Object.assign {}, (uiControl.ui_values ? {})

  controlOverrideText = if typeof uiControl.control_override_text is 'string' and uiControl.control_override_text.trim().length
    uiControl.control_override_text
  else
    dumpYaml overrideObject
  recipeText = if pipelineName.length then dumpYaml(recipe) else ''
  humanOverrideText = if fs.existsSync(path.join(base, 'override.yaml')) then readText(path.join(base, 'override.yaml'), '') else ''
  experimentText = if fs.existsSync(path.join(base, 'experiment.yaml')) then readText(path.join(base, 'experiment.yaml'), '') else ''
  uiFields = scanUiFields recipe, controlOverride, uiControl

  {
    pipeline: pipelineName
    scene: pending.scene ? controlStoryStep.scene ? recipeStoryStep.scene ? ''
    arrival: pending.arrival ? controlStoryStep.arrival ? recipeStoryStep.arrival ? ''
    disturbance: pending.disturbance ? controlStoryStep.disturbance ? recipeStoryStep.disturbance ? ''
    reflection: pending.reflection ? controlStoryStep.reflection ? recipeStoryStep.reflection ? ''
    realization: pending.realization ? controlStoryStep.realization ? recipeStoryStep.realization ? ''
    continuous: uiControl.continuous is true
    pipelines: listTopLevelPipelines()
    scene_options: makeOptions 'scenes'
    arrival_options: makeOptions 'characters'
    disturbance_options: makeOptions 'disturbances'
    reflection_options: makeOptions 'reflections'
    realization_options: makeOptions 'realizations'
    ui_fields: uiFields
    control_override_text: controlOverrideText
    human_override_text: humanOverrideText
    recipe_text: recipeText
    experiment_text: experimentText
  }

describeOutputFile = (relativePath, runStart = null, workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  fullPath = path.join(base, relativePath)
  exists = fs.existsSync(fullPath)
  stat = if exists then fs.statSync(fullPath) else null
  mtime = if stat? then stat.mtime.toISOString() else null
  fresh = false
  if stat? and runStart?
    started = new Date(runStart)
    fresh = not Number.isNaN(started.getTime()) and stat.mtime.getTime() >= started.getTime()

  {
    name: path.basename(relativePath)
    path: relativePath
    exists: exists
    size: stat?.size ? null
    mtime: mtime
    is_fresh: fresh
  }

collectExpectedOutputs = (run, workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  override = readOverride(base)
  controlOverride = readControlOverride(base)
  pipeline = controlOverride.pipeline ? override.pipeline ? run?.pipeline ? null
  return { out_files: [], diary_files: [] } unless pipeline?

  configPath = path.join(EXEC_ROOT, 'config', "#{pipeline}.yaml")
  recipe = readYaml(configPath)
  artifacts = recipe?.artifacts ? {}
  runStart = run?.started_at ? null

  outFiles = []
  diaryFiles = []
  seen = new Set()

  for own artifactKey, spec of artifacts
    continue unless spec? and typeof spec is 'object' and typeof spec.target is 'string'
    target = String(spec.target)
    continue if seen.has(target)
    seen.add target
    row = describeOutputFile target, runStart, base
    if /^diary\//.test(target)
      diaryFiles.push row
    else
      outFiles.push row

  if pipeline in ['diary_ite', 'diary_translate_ite'] and run?.hh_mm?
    diaryBase = "diary/diary_#{run.hh_mm}.txt"
    diaryAdapter = "diary/diary_#{run.hh_mm}.adapter.txt"
    for target in [diaryBase, diaryAdapter] when not seen.has(target)
      seen.add target
      diaryFiles.push describeOutputFile target, runStart, base

  outFiles.sort (a, b) -> String(a.path).localeCompare String(b.path)
  diaryFiles.sort (a, b) -> String(a.path).localeCompare String(b.path)

  {
    out_files: outFiles
    diary_files: diaryFiles
  }

isUsableWorkspace = (candidate) ->
  return false unless typeof candidate is 'string' and candidate.length
  try
    fs.existsSync(candidate) and fs.statSync(candidate).isDirectory()
  catch
    false

resolveStatusWorkspace = (run = null) ->
  return path.resolve(CWD) if workspacePipeName(CWD)?
  runCwd = String(run?.cwd ? '').trim()
  return path.resolve(runCwd) if isUsableWorkspace(runCwd)
  CWD

publicistArtifactPaths = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  relative = (name) -> path.join('out', name)
  {
    source_material: relative('source_material.yaml')
    audience_suggestions: relative('audience_suggestions.yaml')
    audience_profiles: relative('audience_profiles.yaml')
    contact_ledger: relative('contact_ledger.yaml')
    message_drafts: relative('message_drafts.yaml')
    review_decisions: relative('review_decisions.yaml')
    outreach_log: relative('outreach_log.yaml')
    sqlite_load_report: relative('sqlite_load_report.yaml')
    sqlite_init_report: relative('sqlite_init_report.yaml')
    sqlite_write_report: relative('sqlite_write_report.yaml')
    sqlite_insights: relative('sqlite_insights.yaml')
    next_actions: relative('next_actions.yaml')
    research_requests: relative('research_requests.yaml')
    research_results: relative('research_results.yaml')
    target_candidates: relative('target_candidates.yaml')
    qualified_targets: relative('qualified_targets.yaml')
    contact_discovery_requests: relative('contact_discovery_requests.yaml')
    contact_page_results: relative('contact_page_results.yaml')
    enriched_drafts: relative('enriched_drafts.yaml')
    review_packet: relative('review_packet.md')
  }

resolveReviewDecisionsPaths = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  {
    workspace: base
    decisionsPath: path.join(base, 'out', 'review_decisions.yaml')
    draftsPath: path.join(base, 'out', 'message_drafts.yaml')
    enrichedDraftsPath: path.join(base, 'out', 'enriched_drafts.yaml')
    packetPath: path.join(base, 'out', 'review_packet.md')
  }

readPublicistReviewUi = (workspacePath = CWD) ->
  { workspace: base, decisionsPath, draftsPath, enrichedDraftsPath, packetPath } = resolveReviewDecisionsPaths(workspacePath)
  artifactPaths = publicistArtifactPaths(base)

  decisionsDoc = if fs.existsSync(decisionsPath) then readYaml(decisionsPath) else {}
  decisions = if Array.isArray(decisionsDoc?.decisions) then decisionsDoc.decisions else []
  draftsDoc = if fs.existsSync(draftsPath) then readYaml(draftsPath) else {}
  drafts = if Array.isArray(draftsDoc?.drafts) then draftsDoc.drafts else []
  draftsById = {}
  for draft in drafts when draft?.draft_id?
    draftsById[draft.draft_id] = draft
  matchedDraftCount = 0

  groups =
    pending_review: []
    approved: []
    rejected: []
    revise: []

  for entry in decisions
    joinedEntry = Object.assign {}, entry
    if draftsById[joinedEntry.draft_id]?
      joinedEntry.draft = draftsById[joinedEntry.draft_id]
      matchedDraftCount += 1
    decision = String(entry?.decision ? 'pending_review').trim().toLowerCase()
    if decision in ['approved', 'approve'] or entry?.approved_for_send is true
      groups.approved.push joinedEntry
    else if decision in ['rejected', 'reject']
      groups.rejected.push joinedEntry
    else if decision is 'revise'
      groups.revise.push joinedEntry
    else
      groups.pending_review.push joinedEntry

  reviewPacketPath = if fs.existsSync(packetPath) then path.relative(base, packetPath) else 'out/review_packet.md'

  {
    path: if fs.existsSync(decisionsPath) then path.relative(base, decisionsPath) else 'out/review_decisions.yaml'
    workspace: base
    drafts_path: if fs.existsSync(draftsPath) then path.relative(base, draftsPath) else 'out/message_drafts.yaml'
    enriched_drafts_path: if fs.existsSync(enrichedDraftsPath) then path.relative(base, enrichedDraftsPath) else 'out/enriched_drafts.yaml'
    review_packet_path: reviewPacketPath
    source_material_path: artifactPaths.source_material
    audience_profiles_path: artifactPaths.audience_profiles
    contact_ledger_path: artifactPaths.contact_ledger
    matched_draft_count: matchedDraftCount
    draft_count: drafts.length
    counts:
      pending_review: groups.pending_review.length
      approved: groups.approved.length
      rejected: groups.rejected.length
      revise: groups.revise.length
    groups: groups
  }

readPublicistEnrichedDraftsUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  enrichedPath = path.join(base, 'out', 'enriched_drafts.yaml')
  doc = if fs.existsSync(enrichedPath) then readYaml(enrichedPath) else {}
  rows = if Array.isArray(doc?.enriched_drafts) then doc.enriched_drafts else []
  rowsByDraftId = {}
  for row in rows when row?.draft_id?
    rowsByDraftId[row.draft_id] = row

  {
    path: if fs.existsSync(enrichedPath) then path.relative(base, enrichedPath) else 'out/enriched_drafts.yaml'
    workspace: base
    summary: doc?.summary ? {}
    draft_count: doc?.draft_count ? rows.length
    enriched_count: doc?.enriched_count ? 0
    enriched_drafts: rows
    by_draft_id: rowsByDraftId
  }

readPublicistSqliteInsightsUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  insightsPath = path.join(base, 'out', 'sqlite_insights.yaml')
  insightsDoc = if fs.existsSync(insightsPath) then readYaml(insightsPath) else {}
  artifactPaths = publicistArtifactPaths(base)

  {
    path: if fs.existsSync(insightsPath) then path.relative(base, insightsPath) else 'out/sqlite_insights.yaml'
    workspace: base
    sqlite_load_report_path: artifactPaths.sqlite_load_report
    sqlite_init_report_path: artifactPaths.sqlite_init_report
    sqlite_write_report_path: artifactPaths.sqlite_write_report
    summary: insightsDoc?.summary ? { db_available: false }
    counts_by_audience: if Array.isArray(insightsDoc?.counts_by_audience) then insightsDoc.counts_by_audience else []
    pending_outreach: if Array.isArray(insightsDoc?.pending_outreach) then insightsDoc.pending_outreach else []
    empty_audiences: if Array.isArray(insightsDoc?.empty_audiences) then insightsDoc.empty_audiences else []
    recent_activity: if Array.isArray(insightsDoc?.recent_activity) then insightsDoc.recent_activity else []
  }

readPublicistResearchRequestsUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  requestsPath = path.join(base, 'out', 'research_requests.yaml')
  requestsDoc = if fs.existsSync(requestsPath) then readYaml(requestsPath) else {}
  artifactPaths = publicistArtifactPaths(base)
  requests = if Array.isArray(requestsDoc?.research_requests) then requestsDoc.research_requests else []

  groups =
    approved_for_research: []
    rejected: []
    planned_only: []

  for entry in requests
    status = String(entry?.status ? 'planned_only').trim().toLowerCase()
    if status is 'approved_for_research'
      groups.approved_for_research.push entry
    else if status is 'rejected'
      groups.rejected.push entry
    else
      groups.planned_only.push entry

  {
    path: if fs.existsSync(requestsPath) then path.relative(base, requestsPath) else 'out/research_requests.yaml'
    workspace: base
    next_actions_path: artifactPaths.next_actions
    summary: requestsDoc?.summary ? {}
    counts:
      approved_for_research: groups.approved_for_research.length
      rejected: groups.rejected.length
      planned_only: groups.planned_only.length
    groups: groups
  }

readPublicistResearchResultsUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  resultsPath = path.join(base, 'out', 'research_results.yaml')
  resultsDoc = if fs.existsSync(resultsPath) then readYaml(resultsPath) else {}
  artifactPaths = publicistArtifactPaths(base)

  {
    path: if fs.existsSync(resultsPath) then path.relative(base, resultsPath) else 'out/research_results.yaml'
    workspace: base
    target_candidates_path: artifactPaths.target_candidates
    enriched_drafts_path: artifactPaths.enriched_drafts
    review_packet_path: artifactPaths.review_packet
    summary: resultsDoc?.summary ? {}
    results: if Array.isArray(resultsDoc?.results) then resultsDoc.results else []
    skipped: if Array.isArray(resultsDoc?.skipped) then resultsDoc.skipped else []
  }

readPublicistTargetCandidatesUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  candidatesPath = path.join(base, 'out', 'target_candidates.yaml')
  candidatesDoc = if fs.existsSync(candidatesPath) then readYaml(candidatesPath) else {}
  candidates = if Array.isArray(candidatesDoc?.target_candidates) then candidatesDoc.target_candidates else []
  artifactPaths = publicistArtifactPaths(base)

  groups = {}
  for row in candidates when row?.audience?
    groups[row.audience] ?= []
    groups[row.audience].push row

  {
    path: if fs.existsSync(candidatesPath) then path.relative(base, candidatesPath) else 'out/target_candidates.yaml'
    workspace: base
    research_results_path: artifactPaths.research_results
    qualified_targets_path: artifactPaths.qualified_targets
    contact_discovery_requests_path: artifactPaths.contact_discovery_requests
    review_packet_path: artifactPaths.review_packet
    summary: candidatesDoc?.summary ? {}
    target_candidates: candidates
    groups: groups
  }

readPublicistContactDiscoveryUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  requestsPath = path.join(base, 'out', 'contact_discovery_requests.yaml')
  doc = if fs.existsSync(requestsPath) then readYaml(requestsPath) else {}
  requests = if Array.isArray(doc?.contact_discovery_requests) then doc.contact_discovery_requests else []
  artifactPaths = publicistArtifactPaths(base)

  counts =
    approved: 0
    rejected: 0
    planned_only: 0

  for request in requests
    for row in (request.proposed_urls ? [])
      status = String(row?.review_status ? 'planned_only').trim().toLowerCase()
      if status is 'approved'
        counts.approved += 1
      else if status is 'rejected'
        counts.rejected += 1
      else
        counts.planned_only += 1

  {
    path: if fs.existsSync(requestsPath) then path.relative(base, requestsPath) else 'out/contact_discovery_requests.yaml'
    workspace: base
    qualified_targets_path: artifactPaths.qualified_targets
    contact_page_results_path: artifactPaths.contact_page_results
    summary: doc?.summary ? {}
    counts: counts
    contact_discovery_requests: requests
  }

readPublicistContactPageResultsUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  resultsPath = path.join(base, 'out', 'contact_page_results.yaml')
  doc = if fs.existsSync(resultsPath) then readYaml(resultsPath) else {}
  artifactPaths = publicistArtifactPaths(base)

  {
    path: if fs.existsSync(resultsPath) then path.relative(base, resultsPath) else 'out/contact_page_results.yaml'
    workspace: base
    contact_discovery_requests_path: artifactPaths.contact_discovery_requests
    review_packet_path: artifactPaths.review_packet
    summary: doc?.summary ? {}
    results: if Array.isArray(doc?.results) then doc.results else []
    skipped: if Array.isArray(doc?.skipped) then doc.skipped else []
  }

readPublicistOutreachLogUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  logPath = path.join(base, 'out', 'outreach_log.yaml')
  doc = if fs.existsSync(logPath) then readYaml(logPath) else {}
  entries = if Array.isArray(doc?.entries) then doc.entries else []
  artifactPaths = publicistArtifactPaths(base)
  groups =
    not_sent: []
    sent_manually: []
    replied: []
    follow_up_needed: []
    closed: []
  for entry in entries
    status = String(entry?.status ? 'not_sent').trim().toLowerCase()
    if groups[status]?
      groups[status].push entry
    else
      groups.not_sent.push entry
  {
    path: if fs.existsSync(logPath) then path.relative(base, logPath) else 'out/outreach_log.yaml'
    workspace: base
    message_drafts_path: artifactPaths.message_drafts
    review_decisions_path: artifactPaths.review_decisions
    summary: doc?.summary ? {}
    groups: groups
    entries: entries
  }

saveTargetCandidateUpdate = (workspacePath, payload) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  candidatesPath = path.join(base, 'out', 'target_candidates.yaml')
  return { ok: false, error: 'target candidates file not found', path: candidatesPath } unless fs.existsSync(candidatesPath)

  doc = readYaml(candidatesPath)
  candidates = if Array.isArray(doc?.target_candidates) then doc.target_candidates.slice() else []
  candidateId = String(payload?.candidate_id ? '').trim()
  return { ok: false, error: 'candidate_id is required', path: candidatesPath } unless candidateId.length

  statusText = String(payload?.review_status ? '').trim().toLowerCase()
  normalizedStatus = switch statusText
    when 'approved', 'approve' then 'approved'
    when 'rejected', 'reject' then 'rejected'
    when 'maybe_later', 'maybe', 'later', 'pending', 'pending_review' then 'maybe_later'
    else null
  return { ok: false, error: "invalid review_status '#{statusText}'", path: candidatesPath } unless normalizedStatus?

  entryIndex = candidates.findIndex (entry) -> String(entry?.candidate_id ? '').trim() is candidateId
  return { ok: false, error: "candidate_id not found '#{candidateId}'", path: candidatesPath } unless entryIndex >= 0

  currentEntry = candidates[entryIndex] ? {}
  nextEntry = Object.assign {}, currentEntry,
    review_status: normalizedStatus
    reviewer_notes: String(payload?.reviewer_notes ? '')
    reviewed_at: new Date().toISOString()

  candidates[entryIndex] = nextEntry

  groups = {}
  byAudience = {}
  byTargetType = {}
  byConfidence = {}
  for row in candidates when row?.audience?
    groups[row.audience] ?= []
    groups[row.audience].push row
    byAudience[row.audience] = (byAudience[row.audience] ? 0) + 1
    if row?.target_type?
      byTargetType[row.target_type] = (byTargetType[row.target_type] ? 0) + 1
    if row?.confidence?
      byConfidence[row.confidence] = (byConfidence[row.confidence] ? 0) + 1

  nextDoc = if doc? and typeof doc is 'object' and not Array.isArray(doc) then Object.assign({}, doc) else {}
  nextDoc.target_candidates = candidates
  nextDoc.groups_by_audience = groups
  nextDoc.summary = Object.assign {}, nextDoc.summary ? {},
    total_candidates: candidates.length
    by_audience: byAudience
    by_target_type: byTargetType
    by_confidence: byConfidence
    suggestion_only: true

  writeText candidatesPath, dumpYaml(nextDoc)

  {
    ok: true
    workspace: base
    path: candidatesPath
    candidate: nextEntry
  }

saveContactDiscoveryUpdate = (workspacePath, payload) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  requestsPath = path.join(base, 'out', 'contact_discovery_requests.yaml')
  return { ok: false, error: 'contact discovery requests file not found', path: requestsPath } unless fs.existsSync(requestsPath)

  doc = readYaml(requestsPath)
  requests = if Array.isArray(doc?.contact_discovery_requests) then doc.contact_discovery_requests.slice() else []
  requestId = String(payload?.request_id ? '').trim()
  urlText = String(payload?.url ? '').trim()
  return { ok: false, error: 'request_id is required', path: requestsPath } unless requestId.length
  return { ok: false, error: 'url is required', path: requestsPath } unless urlText.length

  statusText = String(payload?.review_status ? '').trim().toLowerCase()
  normalizedStatus = switch statusText
    when 'approved', 'approve' then 'approved'
    when 'rejected', 'reject' then 'rejected'
    when 'planned_only', 'pending' then 'planned_only'
    else null
  return { ok: false, error: "invalid review_status '#{statusText}'", path: requestsPath } unless normalizedStatus?

  requestIndex = requests.findIndex (entry) -> String(entry?.request_id ? '').trim() is requestId
  return { ok: false, error: "request_id not found '#{requestId}'", path: requestsPath } unless requestIndex >= 0

  request = Object.assign {}, requests[requestIndex]
  proposedUrls = if Array.isArray(request.proposed_urls) then request.proposed_urls.slice() else []
  urlIndex = proposedUrls.findIndex (entry) -> String(entry?.url ? '').trim() is urlText
  return { ok: false, error: "url not found '#{urlText}'", path: requestsPath } unless urlIndex >= 0

  currentUrl = proposedUrls[urlIndex] ? {}
  nextUrl = Object.assign {}, currentUrl,
    review_status: normalizedStatus
    reviewer_notes: String(payload?.reviewer_notes ? '')
    reviewed_at: new Date().toISOString()

  proposedUrls[urlIndex] = nextUrl
  request.proposed_urls = proposedUrls
  requests[requestIndex] = request

  counts =
    approved: 0
    rejected: 0
    planned_only: 0
  for row in requests
    for proposed in (row.proposed_urls ? [])
      status = String(proposed?.review_status ? 'planned_only').trim().toLowerCase()
      if status is 'approved'
        counts.approved += 1
      else if status is 'rejected'
        counts.rejected += 1
      else
        counts.planned_only += 1

  nextDoc = if doc? and typeof doc is 'object' and not Array.isArray(doc) then Object.assign({}, doc) else {}
  nextDoc.contact_discovery_requests = requests
  nextDoc.summary = Object.assign {}, nextDoc.summary ? {},
    total_requests: requests.length
    total_proposed_urls: requests.reduce(((sum, row) -> sum + (row.proposed_urls ? []).length), 0)
    suggestion_only: true
  writeText requestsPath, dumpYaml(nextDoc)

  {
    ok: true
    workspace: base
    path: requestsPath
    proposed_url: nextUrl
    counts: counts
  }

readPublicistSourceUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  sourcePath = ensurePublicistSourceFile(base)
  {
    path: path.relative(base, sourcePath)
    workspace: base
    text: readText(sourcePath, DEFAULT_PUBLICIST_SOURCE_TEXT)
  }

readPublicistCampaignConfigUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  configPath = ensurePublicistCampaignConfigFile(base)
  {
    path: path.relative(base, configPath)
    workspace: base
    text: readText(configPath, DEFAULT_PUBLICIST_CAMPAIGN_CONFIG_TEXT)
  }

readPublicistAudienceSuggestionsUi = (workspacePath = CWD) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  suggestionsPath = path.join(base, 'out', 'audience_suggestions.yaml')
  doc = if fs.existsSync(suggestionsPath) then readYaml(suggestionsPath) else {}
  {
    path: if fs.existsSync(suggestionsPath) then path.relative(base, suggestionsPath) else 'out/audience_suggestions.yaml'
    workspace: base
    summary: doc?.summary ? {}
    audience_suggestions: if Array.isArray(doc?.audience_suggestions) then doc.audience_suggestions else []
    configured_audience_hints: if Array.isArray(doc?.configured_audience_hints) then doc.configured_audience_hints else []
    configured_priority_audiences: if Array.isArray(doc?.configured_priority_audiences) then doc.configured_priority_audiences else []
  }

saveReviewDecisionUpdate = (workspacePath, payload) ->
  { workspace, decisionsPath } = resolveReviewDecisionsPaths(workspacePath)
  return { ok: false, error: 'review decisions file not found', path: decisionsPath } unless fs.existsSync(decisionsPath)

  doc = readYaml(decisionsPath)
  decisions = if Array.isArray(doc?.decisions) then doc.decisions.slice() else []
  draftId = String(payload?.draft_id ? '').trim()
  return { ok: false, error: 'draft_id is required', path: decisionsPath } unless draftId.length

  decisionText = String(payload?.decision ? '').trim().toLowerCase()
  normalizedDecision = switch decisionText
    when 'approved', 'approve' then 'approved'
    when 'rejected', 'reject' then 'rejected'
    when 'revise' then 'revise'
    when 'pending', 'pending_review' then 'pending_review'
    else null
  return { ok: false, error: "invalid decision '#{decisionText}'", path: decisionsPath } unless normalizedDecision?

  reviewerNotes = String(payload?.reviewer_notes ? '')
  entryIndex = decisions.findIndex (entry) -> String(entry?.draft_id ? '').trim() is draftId
  return { ok: false, error: "draft_id not found '#{draftId}'", path: decisionsPath } unless entryIndex >= 0

  reviewedAt = new Date().toISOString()
  currentEntry = decisions[entryIndex] ? {}
  nextEntry = Object.assign {}, currentEntry,
    decision: normalizedDecision
    reviewer_notes: reviewerNotes
    approved_for_send: normalizedDecision is 'approved'
    reviewed_at: reviewedAt

  decisions[entryIndex] = nextEntry
  nextDoc = if doc? and typeof doc is 'object' and not Array.isArray(doc) then Object.assign({}, doc) else {}
  nextDoc.decisions = decisions
  nextDoc.decision_count = decisions.length
  writeText decisionsPath, dumpYaml(nextDoc)

  {
    ok: true
    workspace: workspace
    path: decisionsPath
    entry: nextEntry
  }

saveDraftUpdate = (workspacePath, payload) ->
  { workspace, draftsPath } = resolveReviewDecisionsPaths(workspacePath)
  return { ok: false, error: 'message drafts file not found', path: draftsPath } unless fs.existsSync(draftsPath)

  doc = readYaml(draftsPath)
  drafts = if Array.isArray(doc?.drafts) then doc.drafts.slice() else []
  draftId = String(payload?.draft_id ? '').trim()
  return { ok: false, error: 'draft_id is required', path: draftsPath } unless draftId.length

  entryIndex = drafts.findIndex (entry) -> String(entry?.draft_id ? '').trim() is draftId
  return { ok: false, error: "draft_id not found '#{draftId}'", path: draftsPath } unless entryIndex >= 0

  currentEntry = drafts[entryIndex] ? {}
  nextEntry = Object.assign {}, currentEntry

  if typeof payload.subject is 'string'
    nextEntry.subject = payload.subject
  if typeof payload.email_body is 'string'
    nextEntry.email_body = payload.email_body
  nextEntry.revised_by_human = true
  nextEntry.revised_at = new Date().toISOString()

  drafts[entryIndex] = nextEntry
  nextDoc = if doc? and typeof doc is 'object' and not Array.isArray(doc) then Object.assign({}, doc) else {}
  nextDoc.drafts = drafts
  nextDoc.draft_count = drafts.length
  writeText draftsPath, dumpYaml(nextDoc)

  {
    ok: true
    workspace: workspace
    path: draftsPath
    draft: nextEntry
  }

saveResearchRequestUpdate = (workspacePath, payload) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  requestsPath = path.join(base, 'out', 'research_requests.yaml')
  return { ok: false, error: 'research requests file not found', path: requestsPath } unless fs.existsSync(requestsPath)

  doc = readYaml(requestsPath)
  requests = if Array.isArray(doc?.research_requests) then doc.research_requests.slice() else []
  requestId = String(payload?.request_id ? '').trim()
  return { ok: false, error: 'request_id is required', path: requestsPath } unless requestId.length

  statusText = String(payload?.status ? '').trim().toLowerCase()
  normalizedStatus = switch statusText
    when 'approved_for_research', 'approve', 'approved' then 'approved_for_research'
    when 'rejected', 'reject' then 'rejected'
    when 'planned_only', 'pending' then 'planned_only'
    else null
  return { ok: false, error: "invalid status '#{statusText}'", path: requestsPath } unless normalizedStatus?

  entryIndex = requests.findIndex (entry) -> String(entry?.request_id ? '').trim() is requestId
  return { ok: false, error: "request_id not found '#{requestId}'", path: requestsPath } unless entryIndex >= 0

  currentEntry = requests[entryIndex] ? {}
  nextEntry = Object.assign {}, currentEntry,
    status: normalizedStatus
    review_required: true
    reviewed_at: new Date().toISOString()

  if typeof payload.allowed_domains is 'string'
    nextEntry.allowed_domains = String(payload.allowed_domains)
      .split(',')
      .map((value) -> String(value ? '').trim())
      .filter((value) -> value.length)
  else if Array.isArray(payload.allowed_domains)
    nextEntry.allowed_domains = payload.allowed_domains
      .map((value) -> String(value ? '').trim())
      .filter((value) -> value.length)

  if typeof payload.reviewer_notes is 'string'
    nextEntry.reviewer_notes = payload.reviewer_notes

  requests[entryIndex] = nextEntry
  nextDoc = if doc? and typeof doc is 'object' and not Array.isArray(doc) then Object.assign({}, doc) else {}
  nextDoc.research_requests = requests
  nextDoc.request_count = requests.length
  writeText requestsPath, dumpYaml(nextDoc)

  {
    ok: true
    workspace: base
    path: requestsPath
    request: nextEntry
  }

saveOutreachLogUpdate = (workspacePath, payload) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  logPath = path.join(base, 'out', 'outreach_log.yaml')
  return { ok: false, error: 'outreach log file not found', path: logPath } unless fs.existsSync(logPath)

  doc = readYaml(logPath)
  entries = if Array.isArray(doc?.entries) then doc.entries.slice() else []
  draftId = String(payload?.draft_id ? '').trim()
  return { ok: false, error: 'draft_id is required', path: logPath } unless draftId.length

  validStatuses = new Set(['not_sent', 'sent_manually', 'replied', 'follow_up_needed', 'closed'])
  statusText = String(payload?.status ? '').trim().toLowerCase()
  return { ok: false, error: "invalid status '#{statusText}'", path: logPath } unless validStatuses.has(statusText)

  entryIndex = entries.findIndex (entry) -> String(entry?.draft_id ? '').trim() is draftId
  return { ok: false, error: "draft_id not found '#{draftId}'", path: logPath } unless entryIndex >= 0

  currentEntry = entries[entryIndex] ? {}
  nextEntry = Object.assign {}, currentEntry,
    status: statusText

  if typeof payload.sent_manually_at is 'string'
    nextEntry.sent_manually_at = String(payload.sent_manually_at).trim() or null
  else if statusText is 'sent_manually' and not normalizeText(currentEntry.sent_manually_at).length
    nextEntry.sent_manually_at = new Date().toISOString()

  if typeof payload.response_status is 'string'
    nextEntry.response_status = String(payload.response_status).trim() or 'none'
  if typeof payload.follow_up_date is 'string'
    nextEntry.follow_up_date = String(payload.follow_up_date).trim() or null
  if typeof payload.notes is 'string'
    nextEntry.notes = payload.notes

  entries[entryIndex] = nextEntry
  nextDoc = if doc? and typeof doc is 'object' and not Array.isArray(doc) then Object.assign({}, doc) else {}
  nextDoc.entries = entries
  nextDoc.entry_count = entries.length
  nextDoc.summary =
    not_sent: entries.filter((entry) -> String(entry?.status ? 'not_sent') is 'not_sent').length
    sent_manually: entries.filter((entry) -> String(entry?.status ? '') is 'sent_manually').length
    replied: entries.filter((entry) -> String(entry?.status ? '') is 'replied').length
    follow_up_needed: entries.filter((entry) -> String(entry?.status ? '') is 'follow_up_needed').length
    closed: entries.filter((entry) -> String(entry?.status ? '') is 'closed').length
  writeText logPath, dumpYaml(nextDoc)

  {
    ok: true
    workspace: base
    path: logPath
    entry: nextEntry
  }

savePublicistSourceUpdate = (workspacePath, payload) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  sourcePath = ensurePublicistSourceFile(base)
  text = if typeof payload?.text is 'string' then payload.text else ''
  writeText sourcePath, text
  {
    ok: true
    workspace: base
    path: sourcePath
    text: readText(sourcePath, '')
  }

savePublicistCampaignConfigUpdate = (workspacePath, payload) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  configPath = path.join(base, PUBLICIST_CAMPAIGN_CONFIG_RELATIVE_PATH)
  text = if typeof payload?.text is 'string' then payload.text else ''
  try
    parsed = yaml.load(text)
    throw new Error 'campaign config must parse to an object or array' unless parsed? and typeof parsed is 'object'
  catch err
    return {
      ok: false
      error: "yaml parse failed: #{String(err?.message ? err)}"
      workspace: base
      path: configPath
    }

  writeText configPath, text
  {
    ok: true
    workspace: base
    path: configPath
    text: readText(configPath, '')
  }

addAudienceSuggestionToCampaignConfig = (workspacePath, payload) ->
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  configPath = ensurePublicistCampaignConfigFile(base)
  audienceName = String(payload?.name ? '').trim()
  return { ok: false, error: 'name is required', workspace: base, path: configPath } unless audienceName.length

  doc = readYaml(configPath)
  doc = {} unless doc? and typeof doc is 'object' and not Array.isArray(doc)
  priorities = if Array.isArray(doc.priority_audiences) then doc.priority_audiences.slice() else []
  unless priorities.includes(audienceName)
    priorities.push audienceName
  doc.priority_audiences = priorities
  writeText configPath, dumpYaml(doc)
  {
    ok: true
    workspace: base
    path: configPath
    added: audienceName
    text: readText(configPath, '')
  }

buildStatus = ->
  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  statusWorkspace = resolveStatusWorkspace(run)
  mergeRun = readMergeRun()
  pipelineState = readJson path.join(statusWorkspace, 'pipeline.json'), null
  expectedOutputs = collectExpectedOutputs(run, statusWorkspace)
  pipeSummary = buildPipeSummary(statusWorkspace)
  loraRemaining = readJson path.join(statusWorkspace, 'out', 'lora_remaining_count.json'), null
  oracleRemaining = readJson path.join(statusWorkspace, 'out', 'oracle_remaining_count.json'), null
  storiesRemaining = if oracleRemaining? then oracleRemaining else loraRemaining
  events = readJsonlTail path.join(statusWorkspace, 'state', 'ui-events.jsonl')
  steps = collectStepStates(statusWorkspace)
  stem = if run?.logdir? then String(run.logdir) else latestLogStem(statusWorkspace)
  latestLog = if stem? then readText(path.join(statusWorkspace, 'logs', "#{stem}.log")) else ''
  latestErr = if stem? then readText(path.join(statusWorkspace, 'logs', "#{stem}.err")) else ''

  {
    run: run
    exec_root: EXEC_ROOT
    server_cwd: CWD
    active_workspace: statusWorkspace
    active_exec: String(run?.exec ? EXEC_ROOT)
    merge_run: mergeRun
    pipeline_state: pipelineState
    pipe: pipeSummary
    lora_remaining_count: loraRemaining
    oracle_remaining_count: oracleRemaining
    stories_remaining_count: storiesRemaining
    controls: buildControls(statusWorkspace)
    steps: steps
    events: events
    latest_log_stem: stem
    latest_log: latestLog
    latest_err: latestErr
    out_files: expectedOutputs.out_files
    diary_files: expectedOutputs.diary_files
    publicist_review: readPublicistReviewUi(statusWorkspace)
    publicist_source: readPublicistSourceUi(statusWorkspace)
    publicist_campaign_config: readPublicistCampaignConfigUi(statusWorkspace)
    publicist_audience_suggestions: readPublicistAudienceSuggestionsUi(statusWorkspace)
    publicist_enriched_drafts: readPublicistEnrichedDraftsUi(statusWorkspace)
    publicist_sqlite_insights: readPublicistSqliteInsightsUi(statusWorkspace)
    publicist_research_requests: readPublicistResearchRequestsUi(statusWorkspace)
    publicist_research_results: readPublicistResearchResultsUi(statusWorkspace)
    publicist_target_candidates: readPublicistTargetCandidatesUi(statusWorkspace)
    publicist_contact_discovery_requests: readPublicistContactDiscoveryUi(statusWorkspace)
    publicist_contact_page_results: readPublicistContactPageResultsUi(statusWorkspace)
    publicist_outreach_log: readPublicistOutreachLogUi(statusWorkspace)
  }

isAllowedFilePath = (relativePath) ->
  return false unless typeof relativePath is 'string' and relativePath.length
  normalized = path.normalize(relativePath)
  return false if normalized.startsWith('..') or path.isAbsolute(normalized)
  /^logs\//.test(normalized) or /^out\//.test(normalized) or /^diary\//.test(normalized) or /^build\//.test(normalized)

readViewerFile = (relativePath, workspacePath = CWD) ->
  return null unless isAllowedFilePath(relativePath)
  base = if isUsableWorkspace(workspacePath) then path.resolve(workspacePath) else CWD
  fullPath = path.join(base, relativePath)
  return null unless fs.existsSync(fullPath)
  stat = fs.statSync(fullPath)
  return null unless stat.isFile()
  {
    path: relativePath
    workspace: base
    size: stat.size
    mtime: stat.mtime.toISOString()
    text: readText(fullPath, '')
  }

sendJson = (res, code, payload) ->
  body = JSON.stringify(payload, null, 2)
  res.writeHead code,
    'Content-Type': 'application/json; charset=utf-8'
    'Content-Length': Buffer.byteLength(body)
    'Cache-Control': 'no-store'
  res.end body

sendHtml = (res, p) ->
  body = readText p, ''
  if not body.length
    console.error "[ui_server] missing html:", p
    console.error "[ui_server] EXEC_ROOT:", EXEC_ROOT
    console.error "[ui_server] CWD:", CWD
    console.error "[ui_server] __filename:", __filename
    res.writeHead 404, 'Content-Type': 'text/plain; charset=utf-8'
    res.end 'ui/index.html not found'
    return
  res.writeHead 200,
    'Content-Type': 'text/html; charset=utf-8'
    'Content-Length': Buffer.byteLength(body)
    'Cache-Control': 'no-store'
  res.end body

readRequestBody = (req) ->
  new Promise (resolve, reject) ->
    chunks = []
    req.on 'data', (chunk) -> chunks.push chunk
    req.on 'end', ->
      text = Buffer.concat(chunks).toString('utf8')
      resolve text
    req.on 'error', reject

clearStepState = ->
  stateDir = path.join(CWD, 'state')
  return unless fs.existsSync stateDir
  for name in fs.readdirSync(stateDir) when /^step-.*\.json$/.test(name) or /^ui-run\.(json|jsonl)$/.test(name) or /^ui-events\.(json|jsonl)$/.test(name)
    fs.unlinkSync path.join(stateDir, name)

  pipelinePath = path.join(CWD, 'pipeline.json')
  fs.unlinkSync(pipelinePath) if fs.existsSync(pipelinePath)

seedUiRun = (launch, override) ->
  runPath = path.join(CWD, 'state', 'ui-run.json')
  current = readJson(runPath, {})
  current = {} unless current? and typeof current is 'object' and not Array.isArray(current)

  seeded =
    pipeline: current.pipeline ? override.pipeline ? null
    pid: current.pid ? launch.pid
    cwd: current.cwd ? CWD
    exec: current.exec ? EXEC_ROOT
    hh_mm: current.hh_mm ? launch.hh_mm
    logdir: current.logdir ? launch.logdir
    status: current.status ? 'launching'
    started_at: current.started_at ? new Date().toISOString()
    finished_at: current.finished_at ? null

  writeText runPath, JSON.stringify(seeded, null, 2)

findActiveWorkspaceRun = ->
  runPath = path.join(CWD, 'state', 'ui-run.json')
  run = normalizeUiRun readJson(runPath, {}), {}
  return null unless run.is_process_alive is true and Number(run.pid ? 0) > 0
  run

markUiRunExited = (launch, patch = {}) ->
  runPath = path.join(CWD, 'state', 'ui-run.json')
  current = readJson(runPath, {})
  return unless current? and typeof current is 'object' and not Array.isArray(current)
  return unless current.pid is launch.pid
  return unless current.status in ['launching', 'running']

  next = Object.assign {}, current,
    status: patch.status ? 'exited'
    finished_at: patch.finished_at ? new Date().toISOString()
  , patch

  writeText runPath, JSON.stringify(next, null, 2)

markMergeRunExited = (launch, patch = {}) ->
  current = readJson(MERGE_RUN_PATH, {})
  return unless current? and typeof current is 'object' and not Array.isArray(current)
  return unless current.pid is launch.pid
  return unless current.status in ['launching', 'running']

  next = Object.assign {}, current,
    status: patch.status ? 'exited'
    finished_at: patch.finished_at ? new Date().toISOString()
  , patch

  writeText MERGE_RUN_PATH, JSON.stringify(next, null, 2)

stopRepeatLoop = ->
  if repeatLoop.timer?
    clearTimeout repeatLoop.timer
  repeatLoop.enabled = false
  repeatLoop.payload = null
  repeatLoop.timer = null
  repeatLoop.next_launch_at = null
  writeUiControl continuous: false

buildLaunchPayloadFromControl = ->
  uiControl = readUiControl()
  pending = uiControl.pending ? {}
  payload =
    pipeline: pending.pipeline ? readOverride().pipeline ? ''
    continuous: uiControl.continuous is true

  for key in ['scene', 'arrival', 'disturbance', 'reflection', 'realization']
    payload[key] = pending[key] if pending[key]?
  payload.ui_values = Object.assign {}, (uiControl.ui_values ? {})

  payload

buildOverrideObject = (payload) ->
  override = {}
  pipelineName = String(payload.pipeline ? readOverride().pipeline ? '')
  recipe = readRecipe(pipelineName)
  recipeStory = recipe?.select_story_recipe ? {}
  override.pipeline = pipelineName
  diaryPipelines = ['diary_ite', 'diary_translate_ite']

  if override.pipeline in diaryPipelines
    override.select_story_recipe ?= {}

  if override.pipeline in diaryPipelines
    for key in ['scene', 'arrival', 'disturbance', 'reflection', 'realization']
      value = String(payload[key] ? '').trim()
      recipeValue = String(recipeStory[key] ? '')
      if value.length and value isnt recipeValue
        override.select_story_recipe[key] = value
      else
        delete override.select_story_recipe[key]

    delete override.select_story_recipe if Object.keys(override.select_story_recipe).length is 0
  else
    delete override.select_story_recipe

  uiFields = scanUiFields recipe, override, { ui_values: payload.ui_values ? {} }
  for field in uiFields
    chosenValue = if payload?.ui_values? and Object::hasOwnProperty.call(payload.ui_values, field.path)
      payload.ui_values[field.path]
    else
      field.value

    if chosenValue is field.default_value
      deleteByPath override, field.path
    else
      setByPath override, field.path, chosenValue

  override

writeControlOverrideText = (text) ->
  writeText CONTROL_OVERRIDE_PATH, text
  parsed = readYaml CONTROL_OVERRIDE_PATH
  throw new Error 'control_override.yaml must parse to an object' unless parsed? and typeof parsed is 'object' and not Array.isArray(parsed)
  throw new Error 'control_override.yaml must include pipeline' unless typeof parsed.pipeline is 'string' and parsed.pipeline.trim().length
  parsed

writeHumanOverrideText = (text) ->
  trimmed = String(text ? '').trim()
  if trimmed.length is 0
    parsed = readOverride()
    return parsed

  writeText OVERRIDE_PATH, text
  parsed = readYaml OVERRIDE_PATH
  throw new Error 'override.yaml must parse to an object' unless parsed? and typeof parsed is 'object' and not Array.isArray(parsed)
  pipeName = workspacePipeName(CWD)
  inferredModel = inferModelIdFromPipeName(pipeName)
  if inferredModel.length
    parsed.run = {} unless parsed.run? and typeof parsed.run is 'object' and not Array.isArray(parsed.run)
    currentModel = String(parsed.run.model ? '').trim()
    if currentModel.length is 0
      parsed.run.model = inferredModel
      writeText OVERRIDE_PATH, dumpYaml(parsed)
  parsed

scheduleRepeatLaunch = ->
  return unless repeatLoop.enabled

  pipelineState = readJson path.join(CWD, 'pipeline.json'), null
  if pipelineState?.status is 'shutdown'
    stopRepeatLoop()
    writeUiRunPatch
      loop_enabled: false
      countdown_seconds: null
      next_launch_at: null
    return

  delayMs = 60 * 1000
  repeatLoop.next_launch_at = new Date(Date.now() + delayMs).toISOString()
  writeUiRunPatch
    status: 'cooldown'
    loop_enabled: true
    countdown_seconds: 60
    next_launch_at: repeatLoop.next_launch_at

  repeatLoop.timer = setTimeout ->
    return unless repeatLoop.enabled
    pipelineStateNow = readJson path.join(CWD, 'pipeline.json'), null
    if pipelineStateNow?.status is 'shutdown'
      stopRepeatLoop()
      writeUiRunPatch
        loop_enabled: false
        countdown_seconds: null
        next_launch_at: null
      return

    uiControl = readUiControl()
    launchPayload = buildLaunchPayloadFromControl()
    overrideText = if typeof uiControl.control_override_text is 'string' and uiControl.control_override_text.trim().length
      uiControl.control_override_text
    else
      dumpYaml buildOverrideObject(launchPayload)
    override = writeControlOverrideText overrideText
    clearStepState()
    launch = startRunner()
    seedUiRun launch, override
    writeUiRunPatch
      loop_enabled: true
      countdown_seconds: null
      next_launch_at: null
  , delayMs

startRunner = ->
  runTag = buildRunTag()
  logDir = path.join(CWD, 'logs')
  fs.mkdirSync logDir, { recursive: true }
  logPath = path.join(logDir, "#{runTag.logdir}.log")
  errPath = path.join(logDir, "#{runTag.logdir}.err")
  fs.writeFileSync logPath, '', 'utf8'
  fs.writeFileSync errPath, '', 'utf8'
  outFd = fs.openSync logPath, 'a'
  errFd = fs.openSync errPath, 'a'

  child = spawn 'coffee', [RUNNER],
    cwd: CWD
    detached: true
    stdio: ['ignore', outFd, errFd]
    env: Object.assign {}, process.env,
      EXEC: EXEC_ROOT
      CWD: CWD
      PWD: CWD
      HH_MM: runTag.hh_mm
      LOGDIR: runTag.logdir

  child.unref()
  child.on 'error', (err) ->
    markUiRunExited {
      pid: child.pid
      hh_mm: runTag.hh_mm
      logdir: runTag.logdir
    },
      status: 'failed'
      error: String(err?.message ? err)

  child.on 'exit', (code, signal) ->
    status = if code is 0 then 'done' else 'failed'
    markUiRunExited {
      pid: child.pid
      hh_mm: runTag.hh_mm
      logdir: runTag.logdir
    },
      status: status
      exit_code: code
      signal: signal ? null

    if repeatLoop.enabled
      if status is 'done'
        scheduleRepeatLaunch()
      else
        stopRepeatLoop()
        writeUiRunPatch
          loop_enabled: false
          countdown_seconds: null
          next_launch_at: null

  {
    pid: child.pid
    hh_mm: runTag.hh_mm
    logdir: runTag.logdir
  }

startMerge = (pipeName) ->
  stamp = buildRunTag()
  logDir = path.join(CWD, 'logs')
  fs.mkdirSync logDir, { recursive: true }
  logStem = "merge_#{stamp.hh_mm}"
  logPath = path.join(logDir, "#{logStem}.log")
  errPath = path.join(logDir, "#{logStem}.err")
  fs.writeFileSync logPath, '', 'utf8'
  fs.writeFileSync errPath, '', 'utf8'
  outFd = fs.openSync logPath, 'a'
  errFd = fs.openSync errPath, 'a'

  child = spawn resolveCoffeeBin(), [MERGE_SCRIPT, '--pipe', pipeName],
    cwd: EXEC_ROOT
    detached: true
    stdio: ['ignore', outFd, errFd]
    env: Object.assign {}, process.env,
      EXEC: EXEC_ROOT
      CWD: CWD
      PWD: EXEC_ROOT

  payload =
    pipe: pipeName
    pid: child.pid
    status: 'launching'
    started_at: new Date().toISOString()
    finished_at: null
    logdir: logStem
    log_path: path.relative(CWD, logPath)
    err_path: path.relative(CWD, errPath)

  writeText MERGE_RUN_PATH, JSON.stringify(payload, null, 2)

  child.unref()
  child.on 'error', (err) ->
    markMergeRunExited {
      pid: child.pid
      logdir: logStem
    },
      status: 'failed'
      error: String(err?.message ? err)

  child.on 'exit', (code, signal) ->
    status = if code is 0 then 'done' else 'failed'
    markMergeRunExited {
      pid: child.pid
      logdir: logStem
    },
      status: status
      exit_code: code
      signal: signal ? null

  payload

handleLaunch = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  pipeline = String(payload.pipeline ? '').trim()
  return sendJson(res, 400, { ok: false, error: 'pipeline is required' }) unless pipeline.length

  writeUiControl
    pending:
      pipeline: pipeline
      scene: payload.scene ? ''
      arrival: payload.arrival ? ''
      disturbance: payload.disturbance ? ''
      reflection: payload.reflection ? ''
      realization: payload.realization ? ''
    ui_values: if payload.ui_values? and typeof payload.ui_values is 'object' then payload.ui_values else {}

  if payload.continuous is true
    repeatLoop.enabled = true
    repeatLoop.payload = Object.assign {}, payload
    writeUiControl continuous: true
  else
    stopRepeatLoop()
  overrideText = if typeof payload.control_override_text is 'string' and payload.control_override_text.trim().length
    payload.control_override_text
  else
    dumpYaml buildOverrideObject(payload)
  writeUiControl control_override_text: overrideText
  override = writeControlOverrideText overrideText
  attachedRun = findActiveWorkspaceRun()
  if attachedRun?
    writeUiRunPatch
      status: 'running'
      pid: attachedRun.pid
      loop_enabled: repeatLoop.enabled
      countdown_seconds: null
      next_launch_at: null
    return sendJson res, 200,
      ok: true
      attached: true
      pid: attachedRun.pid
      hh_mm: attachedRun.hh_mm ? null
      logdir: attachedRun.logdir ? null
      override: override

  clearStepState()
  launch = startRunner()
  seedUiRun launch, override
  writeUiRunPatch
    loop_enabled: repeatLoop.enabled
    countdown_seconds: null
    next_launch_at: null

  sendJson res, 200,
    ok: true
    pid: launch.pid
    hh_mm: launch.hh_mm
    logdir: launch.logdir
    override: override

handleKill = (req, res) ->
  stopRepeatLoop()
  runPath = path.join(CWD, 'state', 'ui-run.json')
  run = readJson(runPath, {})
  pid = Number(run?.pid ? 0)
  targetKind = 'run'

  if Array.isArray(run?.other_runners) and run.other_runners.length > 0
    first = run.other_runners[0]
    if typeof first?.pid is 'number' and first.pid > 0
      pid = Number(first.pid)
      targetKind = 'blocking_runner'
    else
      firstText = String(first ? '')
      match = firstText.match(/^\s*(\d+)\b/)
      if match?
        pid = Number(match[1])
        targetKind = 'blocking_runner'

  return sendJson(res, 400, { ok: false, error: 'no active run pid recorded' }) unless pid > 0

  try
    process.kill pid, 'SIGTERM'
  catch err
    return sendJson res, 500,
      ok: false
      error: String(err?.message ? err)

  next = Object.assign {}, run,
    status: 'killing'
    kill_requested_at: new Date().toISOString()
    loop_enabled: false
    countdown_seconds: null
    next_launch_at: null
  writeText runPath, JSON.stringify(next, null, 2)

  sendJson res, 200,
    ok: true
    pid: pid
    target_kind: targetKind

handleControl = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  pipeline = String(payload.pipeline ? '').trim()
  current = readUiControl()
  currentPipeline = String(current?.pending?.pipeline ? readOverride().pipeline ? '')
  pipelineChanged = pipeline.length and pipeline isnt currentPipeline
  baseUiValues = if pipelineChanged then {} else (current?.ui_values ? {})
  next =
    continuous: if payload.continuous is true then true else false
    pending:
      pipeline: if pipeline.length then pipeline else (current?.pending?.pipeline ? readOverride().pipeline ? '')
      scene: if pipelineChanged then '' else String(payload.scene ? '')
      arrival: if pipelineChanged then '' else String(payload.arrival ? '')
      disturbance: if pipelineChanged then '' else String(payload.disturbance ? '')
      reflection: if pipelineChanged then '' else String(payload.reflection ? '')
      realization: if pipelineChanged then '' else String(payload.realization ? '')
    ui_values: if payload.ui_values? and typeof payload.ui_values is 'object'
      Object.assign {}, baseUiValues, payload.ui_values
    else
      baseUiValues
    control_override_text: if typeof payload.control_override_text is 'string' then payload.control_override_text else null

  unless typeof payload.control_override_text is 'string'
    next.control_override_text = dumpYaml buildOverrideObject
      pipeline: next.pending.pipeline
      scene: next.pending.scene
      arrival: next.pending.arrival
      disturbance: next.pending.disturbance
      reflection: next.pending.reflection
      realization: next.pending.realization
      ui_values: next.ui_values

  writeUiControl next
  controlOverride = writeControlOverrideText next.control_override_text
  if next.continuous is true
    repeatLoop.enabled = true
  else
    stopRepeatLoop()
    writeUiRunPatch
      loop_enabled: false
      countdown_seconds: null
      next_launch_at: null

  sendJson res, 200,
    ok: true
    control: next
    control_override: controlOverride

handleHumanOverride = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  text = if typeof payload.human_override_text is 'string' then payload.human_override_text else ''
  override = writeHumanOverrideText text
  sendJson res, 200,
    ok: true
    override: override

handleReviewDecisionUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = saveReviewDecisionUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handleDraftUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = saveDraftUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handleResearchRequestUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = saveResearchRequestUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handleTargetCandidateUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = saveTargetCandidateUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handleContactDiscoveryUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = saveContactDiscoveryUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handleOutreachLogUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = saveOutreachLogUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handleOutreachLogUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = saveOutreachLogUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handlePublicistSourceUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = savePublicistSourceUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handlePublicistCampaignConfigUpdate = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = savePublicistCampaignConfigUpdate(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handleAddAudienceSuggestion = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  result = addAudienceSuggestionToCampaignConfig(workspace, payload)
  return sendJson(res, 400, result) unless result.ok is true

  sendJson res, 200, result

handleClearPipelineState = (req, res) ->
  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  workspace = resolveStatusWorkspace(run)
  pipelinePath = path.join(workspace, 'pipeline.json')
  removed = false
  if fs.existsSync(pipelinePath)
    fs.unlinkSync pipelinePath
    removed = true

  sendJson res, 200,
    ok: true
    removed: removed
    workspace: workspace

handleSwitchPipe = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  pipeName = String(payload.pipe ? '').trim()
  return sendJson(res, 400, { ok: false, error: 'pipe is required' }) unless pipeName.length
  return sendJson(res, 400, { ok: false, error: 'invalid pipe name' }) if pipeName.includes('/') or pipeName.includes(path.sep) or pipeName is '.' or pipeName is '..'

  targetCwd = path.join(PIPES_ROOT, pipeName)
  return sendJson(res, 404, { ok: false, error: 'pipe directory not found' }) unless fs.existsSync(targetCwd) and fs.statSync(targetCwd).isDirectory()
  return sendJson(res, 200, { ok: true, pipe: pipeName, cwd: targetCwd, unchanged: true }) if path.resolve(targetCwd) is path.resolve(CWD)

  fs.mkdirSync path.join(targetCwd, 'state'), { recursive: true }
  fs.mkdirSync path.join(targetCwd, 'logs'), { recursive: true }

  sendJson res, 200,
    ok: true
    pipe: pipeName
    cwd: targetCwd
    restarting: true

  launchArgs = ['-lc', "sleep 1; exec coffee #{JSON.stringify(path.join(EXEC_ROOT, 'ui_server.coffee'))}"]
  child = spawn 'bash', launchArgs,
    cwd: targetCwd
    detached: true
    stdio: 'ignore'
    env: Object.assign {}, process.env,
      EXEC: EXEC_ROOT
      CWD: targetCwd
      UI_PORT: String(PORT)
      UI_BIND_MODE: UI_BIND_MODE

  child.unref()
  setTimeout((-> process.exit(0)), 150)

handleMergePipe = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  pipeName = workspacePipeName(CWD)
  return sendJson(res, 400, { ok: false, error: 'current workspace is not under pipes/' }) unless pipeName?

  mergeRun = readMergeRun()
  if mergeRun.is_process_alive is true and Number(mergeRun.pid ? 0) > 0 and mergeRun.status in ['launching', 'running']
    return sendJson res, 200,
      ok: true
      attached: true
      merge_run: mergeRun

  launch = startMerge pipeName
  sendJson res, 200,
    ok: true
    merge_run: launch

server = http.createServer (req, res) ->
  url = req.url ? '/'
  if url is '/' or url is '/index.html'
    return sendHtml res, path.join(EXEC_ROOT, 'ui', 'index.html')
  if url is '/api/status'
    return sendJson res, 200, buildStatus()
  if url.startsWith('/api/file?')
    query = new URL(url, 'http://127.0.0.1').searchParams
    relativePath = query.get('path')
    run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
    workspace = resolveStatusWorkspace(run)
    payload = readViewerFile(relativePath, workspace)
    return sendJson(res, 404, { ok: false, error: 'file not found' }) unless payload?
    return sendJson res, 200, { ok: true, file: payload }
  if url is '/api/launch' and req.method is 'POST'
    return Promise.resolve(handleLaunch(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/control' and req.method is 'POST'
    return Promise.resolve(handleControl(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/human_override' and req.method is 'POST'
    return Promise.resolve(handleHumanOverride(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/review_decision' and req.method is 'POST'
    return Promise.resolve(handleReviewDecisionUpdate(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/message_draft' and req.method is 'POST'
    return Promise.resolve(handleDraftUpdate(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/research_request' and req.method is 'POST'
    return Promise.resolve(handleResearchRequestUpdate(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/target_candidate' and req.method is 'POST'
    return Promise.resolve(handleTargetCandidateUpdate(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/contact_discovery_request' and req.method is 'POST'
    return Promise.resolve(handleContactDiscoveryUpdate(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/outreach_log' and req.method is 'POST'
    return Promise.resolve(handleOutreachLogUpdate(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/publicist_source' and req.method is 'POST'
    return Promise.resolve(handlePublicistSourceUpdate(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/publicist_campaign_config' and req.method is 'POST'
    return Promise.resolve(handlePublicistCampaignConfigUpdate(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/publicist_campaign_add_audience' and req.method is 'POST'
    return Promise.resolve(handleAddAudienceSuggestion(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/clear_pipeline_state' and req.method is 'POST'
    return Promise.resolve(handleClearPipelineState(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/switch_pipe' and req.method is 'POST'
    return Promise.resolve(handleSwitchPipe(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/merge_pipe' and req.method is 'POST'
    return Promise.resolve(handleMergePipe(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/kill' and req.method is 'POST'
    return Promise.resolve(handleKill(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  res.writeHead 404, 'Content-Type': 'text/plain; charset=utf-8'
  res.end 'not found'

server.listen PORT, HOST, ->
  console.log "[ui_server] listening on http://#{HOST}:#{PORT}"

setInterval ->
  return unless repeatLoop.enabled and repeatLoop.next_launch_at?
  run = readJson path.join(CWD, 'state', 'ui-run.json'), {}
  return unless run?.status is 'cooldown'
  remainingMs = Math.max(0, new Date(repeatLoop.next_launch_at).getTime() - Date.now())
  seconds = Math.ceil(remainingMs / 1000)
  writeUiRunPatch
    loop_enabled: true
    countdown_seconds: seconds
    next_launch_at: repeatLoop.next_launch_at
, 1000
