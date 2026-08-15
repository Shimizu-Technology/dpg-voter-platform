# DPG Platform Service Pause Runbook

**Last updated:** August 15, 2026
**Scope:** Democratic Party of Guam voter engagement platform only

## Purpose

This runbook keeps the DPG public site clear and useful while the paid API and worker services are intentionally suspended. It preserves DPG data and a reversible return-to-service path without presenting a backend outage as an application failure.

The paused frontend does not initialize Clerk, PostHog, React Query, or the DPG application. It does not call the API. Every browser route renders the same intentional DPG holding page.

## Service modes

The frontend reads `VITE_SERVICE_MODE` at build time:

| Mode | Behavior | Intended use |
| --- | --- | --- |
| `paused` | Render the DPG holding page without starting application providers or checking the API | Intentional production pause |
| `live` | Start the application normally | Deliberate production reactivation and local development |
| `auto` | Check the Rails `/up` endpoint before starting the application; show a separate temporary-interruption state if it is unreachable | Recovery testing and controlled previews |

Production fails closed: a missing or invalid mode resolves to `paused`. Local development defaults to `live`. The checked-in Netlify configuration explicitly sets production to `paused`.

## Pause procedure

Do not delete Render services or the Neon project.

1. Merge and deploy the paused frontend.
2. Check `/`, `/signup`, `/signup/<code>`, `/staff`, `/admin`, and an unknown route in a private browser window.
3. Confirm every route shows the paused page and that browser network activity contains no DPG API, Clerk, or PostHog requests.
4. Confirm the official DPG website and email links work.
5. Confirm there are no active imports, sends, staff operations, or other in-flight writes.
6. Allow important Solid Queue work to finish. Record any work that will intentionally remain queued.
7. Create an encrypted PostgreSQL logical backup, record its checksum, and verify a restore in an isolated temporary database.
8. Suspend the Render background worker.
9. Suspend the Render API web service.
10. Confirm the Neon compute scales to zero and the public frontend remains available.
11. Record the pause date, deployed frontend commit, backup location/checksum, and service states in the private operations record.

## Verification checklist

- [ ] Production frontend reports `paused` mode.
- [ ] Public signup cannot be opened or submitted.
- [ ] Staff and admin routes do not initialize authentication.
- [ ] PostHog autocapture and session recording are disabled in live mode as an additional privacy safeguard.
- [ ] No DPG API, Clerk, PostHog, ClickSend, or Resend request occurs from the paused page.
- [ ] Mobile layout works at 320 CSS pixels without horizontal overflow.
- [ ] Keyboard focus is visible on both actions.
- [ ] Reduced-motion users do not receive required motion.
- [ ] The service-worker cache has advanced to `dpg-voter-platform-v2`.
- [ ] Render worker and API show suspended status.
- [ ] Neon compute reaches inactive/scale-to-zero status.
- [ ] The backup checksum and restore verification are recorded privately.

## Reactivation procedure

Reactivation requires DPG approval, confirmed operational ownership, and a supervised workflow rehearsal. Before broader use, resolve the documented U.S.-region data-hosting and backup requirements.

1. Confirm the intended release commit and production environment variables.
2. Confirm the Neon project and database credentials are healthy.
3. Resume the Render API first.
4. Run migrations and verify the Rails `/up` endpoint.
5. Resume the background worker and inspect the queue before allowing new work.
6. Build a private preview with `VITE_SERVICE_MODE=auto` and complete public/staff smoke tests.
7. Verify Clerk origin/redirect settings, DPG-only CORS origins, and outbound outreach gates.
8. Change the checked-in Netlify mode to `VITE_SERVICE_MODE=live` in the reactivation PR, or explicitly export `VITE_SERVICE_MODE=live` for a manual production build, and deploy.
9. Verify signup, authentication, API requests, queue processing, and audit logging with safe test records.
10. Record the reactivation date and responsible DPG operator.

Do not make the public frontend live before the API, worker, authentication, database, and operating team are ready.
