# PostgreSQL Advisory Lock Registry

Advisory locks are application-global. To prevent collisions, register all
key pairs used in this codebase here.

| key1 | key2 | Owner | Purpose |
|------|------|-------|---------|
| 81   | 1    | `GecImportService` | Serialize GEC full_list imports (purge detection requires global serialization). changes_only imports use process-level IMPORT_MUTEX only. |

## Convention

- **key1** = subsystem ID (pick any unused integer)
- **key2** = operation discriminator within that subsystem

Before adding a new advisory lock, check this table and choose unused key values.
