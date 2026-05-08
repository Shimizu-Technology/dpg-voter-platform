# Precinct Polling-Site Refresh (GEC Mapping)

Use this when GEC publishes updated polling locations and Campaign Tracker must be aligned.

## Files
- Template: `docs/precinct-polling-site-update-template.csv`
- Task: `api/lib/tasks/precincts.rake` (`ct:precincts:sync_polling_sites`)

## CSV format
Required headers:
- `village`
- `precinct_number`
- `polling_site`

Optional:
- `notes` (ignored by import task)

## 1) Dry run (recommended)

```bash
cd api
CSV_PATH=../docs/precinct-polling-site-update-template.csv \
DRY_RUN=true \
bundle exec rake ct:precincts:sync_polling_sites
```

Dry-run output includes:
- changed rows
- unchanged rows
- missing villages
- missing precincts
- invalid rows

## 2) Apply updates

```bash
cd api
CSV_PATH=../path/to/official-gec-mapping.csv \
DRY_RUN=false \
ACTOR_EMAIL=you@example.com \
CHANGE_NOTE="GEC polling-site refresh YYYY-MM-DD" \
bundle exec rake ct:precincts:sync_polling_sites
```

## Safety behavior
- Matches precinct by `(village, precinct_number)`
- Updates only `precincts.polling_site`
- Creates `audit_logs` entries for each changed precinct
- Leaves unchanged rows untouched

## Post-apply validation
1. Open **Admin → Precinct Settings** and spot-check updated rows.
2. Open **Poll Watcher** and verify polling sites display correctly.
3. Send campaign team summary:
   - total changed
   - missing village/precinct rows
   - effective date/source
