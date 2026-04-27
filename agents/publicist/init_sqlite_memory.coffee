#!/usr/bin/env coffee

fs = require 'fs'
path = require 'path'
{ DatabaseSync } = require 'node:sqlite'

@step =
  desc: 'Initialize the dedicated publicist SQLite memory database.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    execRoot = M.theLowdown('env/EXEC')?.value ? process.cwd()
    sqlitePath = path.resolve String(M.getStepParam(stepName, 'sqlite_db') ? experiment.run?['runtime.sqlite'] ? 'runtime/publicist.sqlite')
    schemaPath = path.resolve execRoot, String(M.getStepParam(stepName, 'schema_path') ? 'db/publicist/schema.sql')

    throw new Error "[#{stepName}] Missing schema file '#{schemaPath}'" unless fs.existsSync(schemaPath)

    fs.mkdirSync path.dirname(sqlitePath), { recursive: true }
    schemaText = fs.readFileSync(schemaPath, 'utf8')
    dbExisted = fs.existsSync(sqlitePath)
    db = new DatabaseSync sqlitePath

    try
      db.exec schemaText
    finally
      db.close()

    report =
      generated_for: experiment.run?.campaign_name
      sqlite_path: sqlitePath
      schema_path: schemaPath
      db_existed_before: dbExisted
      db_available: true
      initialized_at: new Date().toISOString()

    L.make 'sqlite_init_report', report
    L.done()
    return
