# Precinct Polling Site Refresh — Dry Run Report (2026-03-05)

## Source used
- GEC public file linked from `gec.guam.gov` (“2026 Primary Election Polling Sites”)
- Google Drive file id: `106Bzt4UgrCN5j-zYwYNJxJnCugclJhuD`
- File type: JPEG poster
- Local transcription file: `docs/precinct-polling-site-update-2026-03-05-provisional.csv`

## Dry-run command
```bash
cd api
export PATH="$HOME/.rbenv/shims:$PATH"
CSV_PATH=../docs/precinct-polling-site-update-2026-03-05-provisional.csv DRY_RUN=true bundle exec rake ct:precincts:sync_polling_sites
```

## Dry-run summary
- Rows: **59**
- Changed: **45**
- Unchanged: **14**
- Missing villages: **0**
- Missing precincts: **0**
- Invalid rows: **0**

## Interpretation
Most detected changes are naming normalization only (e.g., `Elem.` → `Elementary`, punctuation/diacritics), not actual site moves.

### Likely operational site changes
1. **Precinct 18G**: `Liguan Elem. School` → `Okkodo High School`
2. **Precinct 18H**: `Liguan Elem. School` → `Okkodo High School`

### Non-operational label/format changes (examples)
- `JFK High School` vs `J.F.K. High School`
- `Inalahan` vs `Inalåhan`
- `Merizo` vs `Malesso'`
- `Veritas Hall` suffix omitted in source image text

## Recommendation for safe apply
Apply only clear operational changes now:
- Precincts `18G`, `18H` to `Okkodo High School`

Hold purely formatting/name-normalization updates unless campaign team explicitly wants canonical text sync.

## Open verification item
- Yigo tail range on image OCR appears `19C-19F`; external snippets have shown `19D-19G` in some contexts. No update should be applied to 19* tail range unless confirmed from an official machine-readable source or clear image.
