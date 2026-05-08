# Shirley's Spreadsheet Analysis — "Copy of Let's Go Guam!"

**Source:** https://docs.google.com/spreadsheets/d/141zQNHrD1eP9iFFxEqAUfTrfVjcFLVzCVzBhuN2WPwo
**5 tabs total**

---

## Tab 1: Signs Tracking (gid=0)
**Purpose:** Tracks sign placement requests (billboard, yard, lollipop, truck)
**Columns:** Row#, Name, Contact No., Location/Residence Address, Date of Submission, Comments

**Sub-sections within one sheet:**
- Billboard Signs (1 entry: Victor Lujan)
- Yard Signs (7 entries + 2 location-only entries)
- Lollipop Signs (3 entries)
- Truck Signs (empty)

**Data:** 11 people total with names, ~10 with phone numbers

---

## Tab 2: Petition Signatures (gid=737401185)
**Purpose:** Tracks petition signing
**Columns:** Date, Name, Petition No.
**Data:** 4 entries (Victor Lujan #547, Octavius Concepcion #546, Michelle Santos #202, Jaineen Cruz #203)

---

## Tab 3: Poll Watcher Applications (gid=1122023589)  
**Purpose:** Tracks poll watcher volunteer applications
**Columns:** Row#, Name, Contact No., Date Application submitted to Chief, Date Application Submitted to HQ, Comments
**Data:** 3 entries (Mariana Burch, Shirley Cruz, Jaineen Cruz)

---

## Tab 4: Supporter List / Voter Data (gid=1466745334) ⭐ MAIN DATA
**Purpose:** This is the main voter/supporter roster — THE key import target
**Columns:** Row#, Name, Contact No., Date of Birth, Email Address, Street Address, Registered Y/N, Comments
**Data:** 50 entries with rich detail

**Sample fields present:**
- Full names (single field, various formats: "First Last", "First M. Last", "First Last (Maiden)")
- Phone numbers (671-XXX-XXXX format, some shared between family members)  
- DOB (M/D/YYYY format, one has typo "1/81948" = probably 1/8/1948)
- Email addresses (column exists but ALL empty in this dataset)
- Street addresses (partial — street only, no village explicitly stated, but ALL appear to be Barrigada based on context)
- Registered voter Y/N (mostly "Y", one "N" for a minor born 2008)
- Comments (empty for all)

---

## Tab 5: Election Observer Applications (gid=2095717840)
**Purpose:** Tracks election observer applications (different from poll watchers)
**Columns:** Row#, Name, Contact No., Date Application submitted to Chief, Date Application Submitted to HQ, Comments
**Data:** 4 entries (Mariana Burch, Barbara Santos, Ronnisha Santos, Gloria Santos)

---

## Key Observations for Import Feature

### 1. Multiple data types in one workbook
Not just supporter data — signs, petitions, poll watchers, observers. Import needs to handle tab selection.

### 2. The main import target is Tab 4 (Supporter List)
This has the richest data and maps best to our Supporter model:
- Name → needs splitting into first_name + last_name (already have logic for this)
- Contact No. → contact_number
- DOB → dob
- Email → email (empty in this sample but column exists)
- Street Address → street_address
- Registered Y/N → registered_voter (boolean)
- Village → NOT in the data — need to assign during import (this sheet is all Barrigada)

### 3. Data quality issues to handle
- **Name formats vary:** "First Last", "First M.I. Last", "First Last (Maiden)", couples like "Mel & Theresa Obispo"
- **DOB typo:** "1/81948" should be "1/8/1948"
- **Phone sharing:** Multiple family members share the same phone number (e.g., Santos family all use 671-747-1185)
- **Row numbering baked in:** Column A is just row numbers, not real data
- **Empty rows:** Lots of empty rows at the bottom (pre-allocated spaces)
- **No village column:** Village must be inferred or selected during import
- **No email data:** Column exists but empty — should still map it

### 4. Other tabs could become separate import types later
- Signs → could track in a separate "signs" feature
- Petitions → could become petition tracking  
- Poll watchers / Observers → already have poll watcher feature, could import

### 5. Import Design Recommendations
1. **Tab selector** — Let user pick which tab to import from
2. **Column mapping** — Auto-detect columns but allow manual override
3. **Village assignment** — Required dropdown since village isn't in the data
4. **Preview with review** — Show parsed data before committing
5. **Skip empty rows** — Filter out rows where Name is blank
6. **Name splitting** — Reuse existing sync_print_name logic
7. **Duplicate detection** — Run DuplicateDetector on each imported record
8. **DOB parsing** — Handle M/D/YYYY, with fuzzy error handling
9. **Registered voter mapping** — "Y" → true, "N" → false, blank → nil
10. **Batch import with progress** — Could be 50+ rows, show progress
11. **Source tagging** — Set source="bulk_import" for all imported records
