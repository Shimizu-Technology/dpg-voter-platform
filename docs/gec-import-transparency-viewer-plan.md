# GEC Import Transparency Viewer Plan

**Status:** Implemented with stabilization and rerun audit findings
**Date:** 2026-03-10
**Owner:** Campaign Tracker team

## Status Update

This plan has now been implemented in the app, and follow-up import audits uncovered several important facts about the source files, parser behavior, and rerun stability.

### What is now working

- import history supports `View Import Data`
- import history supports `View Original`
- raw uploaded files are preserved separately from normalized import artifacts
- PDF imports run in the background with progress reporting
- the import viewer supports pagination, search, filters, and row-level errors
- each import persists row-level change records for `new`, `updated`, `removed`, and `transferred`

### Verified current state

Using clean local reruns with the current importer:

1. the February 25, 2026 official PDF can now be imported and re-imported with stable results
2. the January 25, 2026 official PDF can also be imported and re-imported with stable results
3. repeated same-file reruns no longer produce silent drift in `new`, `updated`, `transferred`, or `removed`

### Latest verified February state

- `50,932` total rows
- final stable February rerun: `50,932 matched_unchanged`
- `0` `new`
- `0` `updated`
- `0` `transferred`
- `0` `removed`
- `0` skipped rows

### Latest verified January state

- first January import from a clean February baseline: `50,936` total rows
- this establishes a legitimate month-to-month delta from February:
- `695` `new`
- `14` `updated`
- `50` `transferred`
- `691` `removed`
- `50,177` `matched_unchanged`
- `0` skipped rows
- second and third same-file January reruns after that baseline both produced:
- `50,936 matched_unchanged`
- `0` `new`
- `0` `updated`
- `0` `transferred`
- `0` `removed`
- `0` skipped rows

These import-summary numbers were verified against the persisted row-level change records during the audit work.

## Source File Interpretation

The campaign screenshots clarified that the two files are not the same kind of source material.

### December file

The December attachment appears to be a campaign quota workbook/report package, not the official monthly GEC voter roster.

Evidence from the email:

- it is labeled `Quota files`
- it contains campaign-operational notes about quotas, village referrals, duplicate submissions, and voter-ID notes
- it refers to quota submission behavior, not a direct GEC roster export

### January file

The January attachment appears to be the actual GEC voter list that should be used as the monthly audit input going forward.

Evidence from the email:

- it is described as the `January 25, 2026 Registered Voter List`
- the sender explicitly says it is the `January 25th voting roster`
- the email notes that GEC will no longer provide full birthdates and will provide only birth year

### Product implication

This means the December-to-January comparison is still useful as a QA benchmark, but it should not be interpreted as a perfect month-over-month GEC roster delta. The January file is the stronger source of truth for future recurring audits.

Going forward, the preferred import baseline for this feature should be consecutive official GEC lists, not campaign quota workbooks.

## Findings From Implementation

The large mismatch between December and January was caused by both real source-file differences and real app bugs.

### Source-file difference

- December workbook baseline contained `16,431` rows
- January GEC PDF now parses to `50,936` rows with the hardened parser

That gap alone explains why the January import legitimately shows a very large `new` bucket when compared against the December baseline.

### Bug fixes required to make the comparison trustworthy

#### 1. Placeholder registration numbers were causing false merges

The December workbook used placeholder values like `NEW` in the registration-number column. The import service was incorrectly treating those as real voter registration numbers, which caused unrelated voters to merge and created fake `updated` rows.

Fix:

- placeholder VRNs like `NEW` are now normalized to `nil`

#### 2. The January and February PDF parser needed richer line parsing

The PDF parser originally dropped many valid rows because it did not support letter-suffixed precincts such as `4A` or `18E`, missed some real village spellings, and relied too heavily on a flattened fallback path that could mistake address fragments for names.

Fix:

- parser now supports letter-suffixed precincts
- parser now recognizes more real village spellings from the GEC PDF
- parser now prefers direct line-based parsing for legacy year-only rows before falling back to flattened scanning
- village matching now uses a token boundary so names like `AGATHA` are not misread as village `AGAT`

Impact:

- January parse output increased from about `13k` rows to `50,936`
- February parse output increased from the unstable `50,550`/`53 skipped` state to a stable `50,932`/`0 skipped` state

#### 3. Simplified PDF-name matching caused rerun instability

The PDF import path keeps only the first given name when splitting `LAST, FIRST MIDDLE`, which means multiple distinct voters can collapse onto the same simplified identity. Earlier importer behavior could silently update or transfer the wrong active voter when the same file was re-run.

Fix:

- non-VRN matching now only considers active voters
- non-VRN matches must be unique or the row is skipped for review
- a voter cannot be matched twice in the same import
- collisions inside the same source file are detected up front
- when each colliding row has a unique VRN, the importer safely treats them as distinct voters instead of collapsing them together

Impact:

- February same-file reruns now stay stable instead of producing phantom updates and transfers
- the review bucket dropped from `551` ambiguous rows to `53`, and then to `0` after parser fixes recovered the malformed rows safely

#### 4. Metadata-only DOB ambiguity changes were inflating `updated`

Many rows were being counted as `updated` even though the only change was the parser-confidence flag around ambiguous DOB parsing.

Fix:

- `dob_ambiguous`-only flips no longer count as public `updated` changes

#### 5. Transfers were being double-counted as updates

Transferred voters were correctly classified as `transferred`, but they were also being added into the import-level `updated_records` aggregate.

Fix:

- transfers now remain separate from `updated_records`

#### 6. January reruns exposed a narrower VRN trust gap

After the broader stability work, January still showed a small rerun-only issue: five voters were imported as `new` on the first January run and then had their VRNs filled in on rerun. In each case the VRN was unique and the birth year matched, but the stored and incoming names differed because of surname updates or normalization differences.

Fix:

- trusted VRN matching now also accepts a unique VRN when there is at least one overlapping name component and the birth data still agrees

Impact:

- January same-file reruns now settle to all-zero changes just like February

## Removed Record Audit

The `475` removals seen during the first fully clean February run needed special review.

### What they were

- they were recorded as `missing_from_full_list` removals
- they were not new skipped-row or parser failures
- they were overwhelmingly February-dated records created by earlier unstable February test runs

### What we found

- once the importer reached a zero-skip clean February run, purge detection was no longer suppressed
- that first clean purge removed stale February records that had been created by earlier imperfect imports
- after those stale rows were cleared, the next February rerun produced `0 removed`

### Interpretation

The `475` count should not be interpreted as a real campaign-facing February voter disappearance event. It was mainly cleanup of local test artifacts that had accumulated while the importer was still being hardened.

## Confidence And Interpretation

### What we trust now

- the January and February PDF parser outputs are now believable and QA-passing
- the import summary counts now match the persisted row-level change records
- same-file reruns for both January and February now stabilize at all-zero changes
- the biggest known false-positive sources in the comparison have been removed
- the `Changes` and `Skipped Rows` tabs are now materially trustworthy for import-level audit work

### What still requires human judgment

- December-to-January should not be read as a perfect roster-to-roster delta because the two files appear to come from different upstream purposes
- some apparent month-to-month deltas are still real voter-list differences, not bugs
- January now supplies birth year instead of full DOB, which reduces match precision compared with older spreadsheet-style sources

## Recommended Operating Guidance

For production use:

1. treat the January-style GEC list as the canonical recurring monthly audit source
2. use campaign quota workbooks as supplemental campaign data, not as the primary roster-comparison baseline
3. rely on the `Changes` tab for triage, but spot-check a sample of rows whenever a new source format appears
4. keep parser QA visible in the import flow so suspicious PDFs are reviewed before import

## Goal

Give campaign staff full transparency into GEC imports by letting them inspect:

- what the system imported and understood
- what source file was uploaded
- when and by whom the import happened

This should reduce ambiguity during QA, improve trust in the import flow, and make it easier to troubleshoot parsing or data-quality issues.

## Product Principle

Every GEC import should expose two distinct truths:

1. **View Import Data**: what the app parsed and used
2. **View Original**: the raw uploaded file, exactly as received

`Download` remains available as a utility action, but it should not be the only transparency feature.

## Recommended UX

For each row in GEC import history, expose these actions in the expanded details panel:

- `View Import Data`
- `View Original`
- `Download`

### Action semantics

#### `View Import Data`

Primary action. Opens an in-app modal that shows:

- import metadata
- parsed row preview
- row counts and import breakdown
- warnings and errors
- PDF QA summary when applicable
- sheet information for spreadsheets when applicable

This is the fastest and most useful way for campaign staff to validate what the system actually imported.

#### `View Original`

Secondary action. Opens the raw uploaded file when the raw file is preserved.

- PDFs should open inline in-app or in a new browser tab
- spreadsheets can initially fall back to browser/open/download behavior if a true workbook-style viewer is not implemented

#### `Download`

Tertiary utility action for users who want the file locally.

## Why this is the right model

Campaign staff need transparency at three levels:

- **Operational transparency**: what the app imported
- **Audit transparency**: what file was submitted
- **Recovery transparency**: the ability to compare parsed output against the source file

`Download Original` alone only solves audit transparency and does so poorly for quick review. `View Import Data` should ship first because it gives the most value immediately.

## Current State

### Already implemented

- async GEC imports with progress tracking
- import detail accordion in import history
- imported timestamp and uploader metadata
- S3-backed `Download Original` flow
- upload-time preview flow for spreadsheets and PDFs
- PDF QA summary and parsed sample-row preview during upload

### Important limitation in current implementation

For PDF uploads, the app currently converts the uploaded PDF into normalized CSV before the preserved import artifact is stored. That means the current preserved file is not always the literal original uploaded document.

This has two implications:

- `View Import Data` can be built now using current architecture
- a true `View Original` feature requires preserving the raw uploaded file separately

## Delivery Plan

## Phase 1: View Import Data

**Goal:** ship the most valuable transparency feature first using current architecture.

### Scope

Add an in-app viewer for existing import history entries that shows the parsed data used by the system.

### Backend work

Add a new endpoint for import-history preview, for example:

- `GET /api/v1/gec_voters/imports/:id/view_data`

Suggested response shape:

- `source_type`
- `filename`
- `original_filename`
- `created_at`
- `uploaded_by_email`
- `import_type`
- `status`
- `row_count`
- `preview_rows`
- `qa`
- `warnings`
- `sheets`
- `metadata`

Implementation notes:

- Parse from the preserved import artifact already associated with the import
- Reuse existing spreadsheet/PDF preview payload shape where possible
- Keep payload limited to a sample window for performance
- Return enough metadata to render the modal without extra requests

### Frontend work

In `web/src/pages/team/TeamGecPage.tsx`:

- add a `View Import Data` button to the import detail panel
- add modal state for the selected import preview
- fetch preview data on demand
- render a viewer modal using the existing app modal pattern
- reuse the current spreadsheet and PDF preview UI patterns from the upload flow

### Modal contents

- filename
- imported at
- imported by
- import type
- import status
- parsed row sample
- PDF QA summary when applicable
- warnings and row-level errors when present
- actions for `View Original` and `Download`

### Acceptance criteria

- a user can open parsed preview data from import history
- the modal clearly distinguishes parsed data from original file
- spreadsheet imports show a readable sample of parsed rows
- PDF imports show QA summary plus parsed sample rows
- errors and warnings are visible when present

## Phase 2: True View Original

**Goal:** support a truthful raw-file viewing experience.

### Scope

Preserve the raw uploaded file separately from the normalized import artifact and expose an inline viewing path where appropriate.

### Backend work

Add raw-file metadata fields to `gec_imports`, such as:

- `raw_file_s3_key`
- `raw_filename`
- `raw_content_type`

Preserve two assets for new imports:

1. raw uploaded source file
2. normalized import artifact used for parsing/import

Notes:

- for spreadsheets, raw file and import artifact may be identical
- for PDFs, the raw PDF and normalized CSV should both be preserved

Add a dedicated endpoint for original viewing, for example:

- `GET /api/v1/gec_voters/imports/:id/view_original`

Update S3 URL generation to support both:

- inline viewing
- attachment download

### Frontend work

- add `View Original` button only when raw file exists
- for PDFs, open inline in a modal or new tab
- for spreadsheets, either open externally or provide a browser-friendly fallback
- keep `Download` available separately

### Acceptance criteria

- new PDF imports preserve the raw PDF and the normalized CSV artifact
- new spreadsheet imports preserve the raw source file
- users can open the true original file from import history
- `View Original` behavior matches the actual underlying file

## Suggested Build Order

1. Add `View Import Data` endpoint
2. Add viewer modal in import history
3. Reuse upload preview rendering for history preview
4. Add tests for history preview endpoint
5. Add raw-file preservation fields
6. Update import job/controller to preserve raw uploads separately
7. Add `View Original` endpoint and UI
8. Add PDF inline viewing
9. Improve spreadsheet original-file experience if needed

## Testing Plan

### Automated

- controller test for `imports/:id/view_data`
- job/service test that new imports preserve raw file metadata correctly
- controller test for `imports/:id/view_original`
- PDF import test proving raw PDF and normalized CSV are both preserved

### Manual QA

Test with:

- `.xlsx` import
- `.csv` import
- `.pdf` import
- import with warnings
- historical import without raw-file preservation
- import where S3 is unavailable

Verify:

- parsed preview is readable and accurate
- metadata matches import history
- raw-file view behavior is truthful
- download still works

## Copy Guidance

Use clear labels so users understand the difference:

- `View Import Data`
- `View Original`
- `Download`

Avoid using `View Original` for parsed previews. That would create user confusion, especially for historical PDF imports created before raw-file preservation exists.

## Risks and Notes

- historical imports may not have enough preserved information to support true original-file viewing
- PDF viewing requires preserving the raw file going forward
- workbook-style in-browser spreadsheet viewing is optional and should not block Phase 1
- parsed preview should stay bounded to avoid large payloads and slow render times

## Recommendation Summary

Ship **Phase 1** immediately when ready: `View Import Data`.

Then build **Phase 2** so `View Original` becomes fully truthful for future imports.

This gives the campaign team a practical transparency feature quickly without misrepresenting what the system can currently show.
