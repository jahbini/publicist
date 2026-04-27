#!/usr/bin/env coffee

fs = require 'fs'
path = require 'path'
{ DatabaseSync } = require 'node:sqlite'

@step =
  desc: 'Read-only SQLite insights for approved publicist memory.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    sqlitePath = path.resolve String(M.getStepParam(stepName, 'sqlite_db') ? experiment.run?['runtime.sqlite'] ? 'runtime/publicist.sqlite')
    report =
      generated_for: experiment.run?.campaign_name
      sqlite_path: sqlitePath
      counts_by_audience: []
      pending_outreach: []
      empty_audiences: []
      recent_activity: []
      summary:
        db_available: false

    unless fs.existsSync sqlitePath
      L.make 'sqlite_insights', report
      L.done()
      return

    db = new DatabaseSync sqlitePath, readOnly: true

    try
      countsByAudienceStmt = db.prepare '''
        SELECT
          a.audience_key,
          a.audience_label,
          COUNT(d.draft_id) AS approved_drafts
        FROM audiences a
        LEFT JOIN drafts d
          ON d.audience_id = a.id
         AND d.status = 'approved_for_send'
        GROUP BY a.id, a.audience_key, a.audience_label
        ORDER BY a.audience_label COLLATE NOCASE
      '''

      pendingOutreachStmt = db.prepare '''
        SELECT
          d.draft_id,
          a.audience_label,
          c.organization,
          c.contact_name,
          rd.reviewed_at
        FROM drafts d
        JOIN review_decisions rd
          ON rd.draft_id = d.draft_id
         AND rd.approved_for_send = 1
         AND lower(rd.decision) = 'approved'
        LEFT JOIN contacts c
          ON c.id = d.contact_id
        LEFT JOIN audiences a
          ON a.id = d.audience_id
        LEFT JOIN outreach_events oe
          ON oe.draft_id = d.draft_id
        WHERE oe.id IS NULL
        ORDER BY rd.reviewed_at DESC, d.draft_id
      '''

      emptyAudiencesStmt = db.prepare '''
        SELECT
          a.audience_key,
          a.audience_label
        FROM audiences a
        LEFT JOIN drafts d
          ON d.audience_id = a.id
         AND d.status = 'approved_for_send'
        WHERE d.id IS NULL
        ORDER BY a.audience_label COLLATE NOCASE
      '''

      recentActivityStmt = db.prepare '''
        SELECT
          rd.draft_id,
          rd.reviewed_at,
          a.audience_label,
          c.organization,
          c.contact_name
        FROM review_decisions rd
        LEFT JOIN drafts d
          ON d.draft_id = rd.draft_id
        LEFT JOIN audiences a
          ON a.id = d.audience_id
        LEFT JOIN contacts c
          ON c.id = d.contact_id
        WHERE rd.reviewed_at IS NOT NULL
          AND trim(rd.reviewed_at) <> ''
        ORDER BY rd.reviewed_at DESC, rd.draft_id
        LIMIT 10
      '''

      report.counts_by_audience = countsByAudienceStmt.all().map (row) ->
        audience_key: row.audience_key
        audience_label: row.audience_label
        approved_drafts: Number(row.approved_drafts ? 0)

      report.pending_outreach = pendingOutreachStmt.all().map (row) ->
        draft_id: row.draft_id
        audience_label: row.audience_label
        organization: row.organization
        contact_name: row.contact_name
        reviewed_at: row.reviewed_at

      report.empty_audiences = emptyAudiencesStmt.all().map (row) ->
        audience_key: row.audience_key
        audience_label: row.audience_label

      report.recent_activity = recentActivityStmt.all().map (row) ->
        draft_id: row.draft_id
        reviewed_at: row.reviewed_at
        audience_label: row.audience_label
        organization: row.organization
        contact_name: row.contact_name

      report.summary =
        db_available: true
        counts_by_audience_count: report.counts_by_audience.length
        pending_outreach_count: report.pending_outreach.length
        empty_audiences_count: report.empty_audiences.length
        recent_activity_count: report.recent_activity.length
    finally
      db.close()

    L.make 'sqlite_insights', report
    L.done()
    return
