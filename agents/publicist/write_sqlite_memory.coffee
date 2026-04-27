#!/usr/bin/env coffee

fs = require 'fs'
path = require 'path'
{ DatabaseSync } = require 'node:sqlite'

isBlank = (value) ->
  String(value ? '').trim().length is 0

boolToInt = (value) ->
  if value is true then 1 else 0

isFullyApprovedDecision = (decision) ->
  decision?.approved_for_send is true and
  String(decision?.decision ? '').trim().toLowerCase() is 'approved' and
  not isBlank(decision?.reviewed_at)

findLedgerEntryForDraft = (contactLedger, draft) ->
  return null unless Array.isArray(contactLedger?.entries)
  contactLedger.entries.find (entry) ->
    String(entry?.organization ? '') is String(draft?.organization ? '') and
    String(entry?.contact_name ? '') is String(draft?.contact_name ? '')

@step =
  desc: 'Write approved publicist contact/draft/review metadata into SQLite.'

  action: (L, stepName, M) ->
    experiment = M.theLowdown('experiment.yaml')?.value
    throw new Error "[#{stepName}] Missing experiment.yaml in Memo" unless experiment?

    contactLedgerKey = 'contact_ledger'
    messageDraftsKey = 'message_drafts'
    reviewDecisionsKey = 'review_decisions'

    contactLedger = await L.need contactLedgerKey
    messageDrafts = await L.need messageDraftsKey
    reviewDecisions = await L.need reviewDecisionsKey

    throw new Error "[#{stepName}] Missing required artifact '#{contactLedgerKey}'" unless contactLedger?.entries?
    throw new Error "[#{stepName}] Missing required artifact '#{messageDraftsKey}'" unless messageDrafts?.drafts?
    throw new Error "[#{stepName}] Missing required artifact '#{reviewDecisionsKey}'" unless reviewDecisions?.decisions?

    sqlitePath = path.resolve String(M.getStepParam(stepName, 'sqlite_db') ? experiment.run?['runtime.sqlite'] ? 'runtime/publicist.sqlite')
    report =
      generated_for: experiment.run?.campaign_name
      sqlite_path: sqlitePath
      approval_filter: 'approved_for_send = true'
      rows_written:
        contacts: 0
        drafts: 0
        review_decisions: 0
      skipped:
        not_fully_approved: 0
      errors: []

    unless fs.existsSync sqlitePath
      report.errors.push
        type: 'missing_sqlite_db'
        detail: "SQLite DB missing at #{sqlitePath}"
      report.summary =
        approved_count: 0
        skipped_not_fully_approved: report.skipped.not_fully_approved
        error_count: report.errors.length
        db_write_performed: false
      L.make 'sqlite_write_report', report
      L.done()
      return

    draftById = {}
    for draft in messageDrafts.drafts when draft?.draft_id?
      draftById[draft.draft_id] = draft

    approvedDecisions = []
    for decision in reviewDecisions.decisions
      if isFullyApprovedDecision(decision)
        approvedDecisions.push decision
      else
        report.skipped.not_fully_approved += 1

    db = new DatabaseSync sqlitePath

    dbWritePerformed = false

    try
      findAudienceByKeyStmt = db.prepare 'SELECT id, audience_key, audience_label FROM audiences WHERE audience_key = ? LIMIT 1'
      findAudienceByLabelStmt = db.prepare 'SELECT id, audience_key, audience_label FROM audiences WHERE audience_label = ? LIMIT 1'
      findContactStmt = db.prepare 'SELECT id FROM contacts WHERE audience_id = ? AND organization = ? AND ifnull(contact_name, "") = ifnull(?, "") LIMIT 1'
      insertContactStmt = db.prepare '''
        INSERT INTO contacts (
          audience_id, organization, contact_name, contact_role, contact_channel,
          status, rationale, next_action, review_required, source_artifact_key,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      '''
      updateContactStmt = db.prepare '''
        UPDATE contacts
        SET contact_role = ?, contact_channel = ?, status = ?, rationale = ?, next_action = ?,
            review_required = ?, source_artifact_key = ?, updated_at = ?
        WHERE id = ?
      '''
      findDraftStmt = db.prepare 'SELECT id FROM drafts WHERE draft_id = ? LIMIT 1'
      insertDraftStmt = db.prepare '''
        INSERT INTO drafts (
          draft_id, audience_id, contact_id, subject, pitch_summary, artifact_key,
          artifact_path, review_required, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      '''
      updateDraftStmt = db.prepare '''
        UPDATE drafts
        SET audience_id = ?, contact_id = ?, subject = ?, pitch_summary = ?, artifact_key = ?,
            artifact_path = ?, review_required = ?, status = ?, updated_at = ?
        WHERE id = ?
      '''
      findReviewDecisionStmt = db.prepare 'SELECT id FROM review_decisions WHERE draft_id = ? LIMIT 1'
      insertReviewDecisionStmt = db.prepare '''
        INSERT INTO review_decisions (
          draft_id, decision, reviewer_notes, approved_for_send, reviewed_at,
          artifact_key, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      '''
      updateReviewDecisionStmt = db.prepare '''
        UPDATE review_decisions
        SET decision = ?, reviewer_notes = ?, approved_for_send = ?, reviewed_at = ?,
            artifact_key = ?, updated_at = ?
        WHERE id = ?
      '''

      tx = db.transaction (rows) ->
        for decision in rows
          draftId = String(decision?.draft_id ? '').trim()
          draft = draftById[draftId]
          unless draft?
            report.errors.push
              type: 'missing_draft'
              draft_id: draftId
              detail: "No message_drafts row for approved draft_id '#{draftId}'"
            continue

          ledgerEntry = findLedgerEntryForDraft(contactLedger, draft)
          unless ledgerEntry?
            report.errors.push
              type: 'missing_contact_ledger_entry'
              draft_id: draftId
              detail: "No contact_ledger row for '#{draft.organization ? ''}::#{draft.contact_name ? ''}'"
            continue

          audienceRow = null
          if not isBlank(draft.audience_key)
            audienceRow = findAudienceByKeyStmt.get(draft.audience_key)
          if not audienceRow? and not isBlank(draft.audience_label)
            audienceRow = findAudienceByLabelStmt.get(draft.audience_label)
          if not audienceRow? and not isBlank(ledgerEntry.audience)
            audienceRow = findAudienceByLabelStmt.get(ledgerEntry.audience)
          unless audienceRow?
            report.errors.push
              type: 'missing_audience_row'
              draft_id: draftId
              detail: "No audiences row found for approved draft '#{draftId}'"
            continue

          now = new Date().toISOString()
          contactRow = findContactStmt.get audienceRow.id, ledgerEntry.organization, ledgerEntry.contact_name ? null
          if contactRow?
            updateContactStmt.run(
              ledgerEntry.contact_role ? null
              ledgerEntry.contact_channel ? null
              'approved_for_send'
              ledgerEntry.rationale ? null
              ledgerEntry.next_action ? null
              boolToInt(ledgerEntry.review_required)
              'contact_ledger'
              now
              contactRow.id
            )
            contactID = contactRow.id
            report.rows_written.contacts += 1
          else
            contactResult = insertContactStmt.run(
              audienceRow.id
              ledgerEntry.organization
              ledgerEntry.contact_name ? null
              ledgerEntry.contact_role ? null
              ledgerEntry.contact_channel ? null
              'approved_for_send'
              ledgerEntry.rationale ? null
              ledgerEntry.next_action ? null
              boolToInt(ledgerEntry.review_required)
              'contact_ledger'
              now
              now
            )
            contactID = contactResult.lastInsertRowid
            report.rows_written.contacts += 1

          draftRow = findDraftStmt.get draftId
          if draftRow?
            updateDraftStmt.run(
              audienceRow.id
              contactID
              draft.subject ? null
              draft.pitch_summary ? null
              'message_drafts'
              experiment.artifacts?.message_drafts?.target ? null
              boolToInt(draft.review_required)
              'approved_for_send'
              now
              draftRow.id
            )
            report.rows_written.drafts += 1
          else
            insertDraftStmt.run(
              draftId
              audienceRow.id
              contactID
              draft.subject ? null
              draft.pitch_summary ? null
              'message_drafts'
              experiment.artifacts?.message_drafts?.target ? null
              boolToInt(draft.review_required)
              'approved_for_send'
              now
              now
            )
            report.rows_written.drafts += 1

          reviewDecisionRow = findReviewDecisionStmt.get draftId
          if reviewDecisionRow?
            updateReviewDecisionStmt.run(
              decision.decision ? 'approved'
              decision.reviewer_notes ? ''
              boolToInt(decision.approved_for_send)
              decision.reviewed_at ? null
              'review_decisions'
              now
              reviewDecisionRow.id
            )
            report.rows_written.review_decisions += 1
          else
            insertReviewDecisionStmt.run(
              draftId
              decision.decision ? 'approved'
              decision.reviewer_notes ? ''
              boolToInt(decision.approved_for_send)
              decision.reviewed_at ? null
              'review_decisions'
              now
              now
            )
            report.rows_written.review_decisions += 1

      tx approvedDecisions
      dbWritePerformed = true
    catch err
      report.errors.push
        type: 'sqlite_write_failed'
        detail: String(err?.message ? err)
    finally
      db.close()

    report.summary =
      approved_count: approvedDecisions.length
      skipped_not_fully_approved: report.skipped.not_fully_approved
      error_count: report.errors.length
      db_write_performed: dbWritePerformed

    L.make 'sqlite_write_report', report
    L.done()
    return
