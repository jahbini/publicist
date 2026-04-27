-- Publicist agent memory schema design.
-- This schema is documentation-only for now; do not create the database yet.
-- Artifact files remain the system of record for draft content and review packets.

-- audiences
-- Stores normalized audience rows so contacts, drafts, and events can join
-- against a stable audience identity instead of duplicating labels everywhere.
CREATE TABLE audiences (
  id INTEGER PRIMARY KEY,
  audience_key TEXT NOT NULL UNIQUE,
  audience_label TEXT NOT NULL,
  angle TEXT,
  rationale TEXT,
  review_required INTEGER NOT NULL DEFAULT 1,
  source_artifact_key TEXT,
  created_at TEXT,
  updated_at TEXT
);

-- contacts
-- Stores reviewed or placeholder contact metadata for outreach targets.
-- This table is for joinable lookup state only, not full outbound messages.
CREATE TABLE contacts (
  id INTEGER PRIMARY KEY,
  audience_id INTEGER NOT NULL,
  organization TEXT NOT NULL,
  contact_name TEXT,
  contact_role TEXT,
  contact_channel TEXT,
  status TEXT NOT NULL DEFAULT 'draft_only',
  rationale TEXT,
  next_action TEXT,
  review_required INTEGER NOT NULL DEFAULT 1,
  source_artifact_key TEXT,
  created_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (audience_id) REFERENCES audiences(id)
);

-- drafts
-- Stores lightweight draft metadata and artifact references.
-- Long draft bodies stay in YAML/MD artifacts rather than in SQLite.
CREATE TABLE drafts (
  id INTEGER PRIMARY KEY,
  draft_id TEXT NOT NULL UNIQUE,
  audience_id INTEGER,
  contact_id INTEGER,
  subject TEXT,
  pitch_summary TEXT,
  artifact_key TEXT NOT NULL,
  artifact_path TEXT,
  review_required INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'draft_only',
  created_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (audience_id) REFERENCES audiences(id),
  FOREIGN KEY (contact_id) REFERENCES contacts(id)
);

-- review_decisions
-- Stores per-draft human review state such as approve/reject/revise decisions,
-- reviewer notes, and whether a draft is approved for any later send workflow.
CREATE TABLE review_decisions (
  id INTEGER PRIMARY KEY,
  draft_id TEXT NOT NULL,
  decision TEXT NOT NULL DEFAULT 'pending_review',
  reviewer_notes TEXT NOT NULL DEFAULT '',
  approved_for_send INTEGER NOT NULL DEFAULT 0,
  reviewed_at TEXT,
  artifact_key TEXT,
  created_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (draft_id) REFERENCES drafts(draft_id)
);

-- outreach_events
-- Stores append-only outreach history metadata once reviewed send/log phases
-- exist. This is future-facing and should stay empty in the current draft-only
-- system.
CREATE TABLE outreach_events (
  id INTEGER PRIMARY KEY,
  draft_id TEXT,
  contact_id INTEGER,
  event_type TEXT NOT NULL,
  event_status TEXT NOT NULL,
  event_at TEXT,
  notes TEXT,
  artifact_key TEXT,
  created_at TEXT,
  FOREIGN KEY (draft_id) REFERENCES drafts(draft_id),
  FOREIGN KEY (contact_id) REFERENCES contacts(id)
);

CREATE INDEX idx_audiences_key ON audiences(audience_key);
CREATE INDEX idx_contacts_audience_id ON contacts(audience_id);
CREATE INDEX idx_drafts_audience_id ON drafts(audience_id);
CREATE INDEX idx_drafts_contact_id ON drafts(contact_id);
CREATE INDEX idx_review_decisions_draft_id ON review_decisions(draft_id);
CREATE INDEX idx_outreach_events_contact_id ON outreach_events(contact_id);
CREATE INDEX idx_outreach_events_draft_id ON outreach_events(draft_id);
