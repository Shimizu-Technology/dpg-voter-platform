# Campaign Team Meeting Feedback — Feb 15, 2026

**Attendees:** Leon + campaign team members
**Outcome:** Team loved it. Lots of actionable feedback below.

---

## Organized by Priority

### 🔴 P0 — Must Fix (Broken / Blocking Demo)

1. **QR Code flow not working properly** — Test and fix end-to-end
2. **ActionCable disconnects/timeouts** — Intermittent real-time drops
3. **Bulk SMS not sending to hundreds/thousands** — Verify at scale
4. **Village page: voters vs supporters numbers mismatch** — Confusing for staff

### 🟡 P1 — High Priority (Core Functionality Gaps)

5. **Split full name → first name + last name** — Voters need separate fields
6. **Configurable voter numbers** — Must be editable (get real numbers from mom)
7. **Duplicate detection + flagging** — Flag same email/phone/DOB/name but don't block signup. Staff reviews.
8. **Vetting/verification stage** — Supporters need a "verified" status before counting as official. Especially staff entry.
9. **Import functionality (Excel/CSV)** — CT-22 already created, team needs this ASAP
10. **Export to Excel (not CSV)** — Team prefers .xlsx format
11. **Export respects filters** — Whatever filters are active should apply to export
12. **Assign staff to specific areas** — They only see their assigned village/district (RBAC scoping already partially done)
13. **Communication opt-in checkbox** — On signup form: "I'd like to receive campaign updates" (text/email/both)
14. **Admin visibility of opt-in status** — Easy to see who opted in
15. **OCR form scanning review flow** — Flag uncertain fields for staff review before committing to system
16. **Customizable welcome SMS text** — Admin can edit the message sent on signup

### 🟢 P2 — Important Enhancements

17. **Event signup / interest form** — Simple email collection for event notifications
18. **Non-registered voter list** — Separate view/filter for unregistered voters
19. **Yard sign / motorcade tracking** — Filter/report for who wants yard signs or motorcade participation
20. **Event messaging** — Easy way to message people who signed up for specific events
21. **Email blast functionality** — In addition to SMS
22. **WhatsApp as communication channel** — Team interested in WhatsApp over SMS
23. **Quota periods** — Monthly/weekly quotas (not just overall)
24. **Absentee ballot handling** — Military/college voters, single document to sign. May need its own form. TBD.
25. **CTA after registration** — "Check out our social media!" on thank-you page
26. **Social media links** — Add to thank-you page and/or welcome message
27. **Disclaimer for text messages** — Consent notice before opting in

### 🔵 P3 — Branding / Setup

28. **Domain: joshtina.support** — Primary campaign domain
29. **Reference site: joshtina.info** — Check for info/styling
30. **Get branding from Austin and mom** — Logo, colors, fonts, style guide
31. **Test events flow end-to-end** — Verify create → RSVP → check-in → notifications
32. **Test war room + poll watcher** — Full election-day simulation

---

## Decisions Needed from Leon

- [ ] Absentee ballot approach — separate form? Field on existing form?
- [ ] WhatsApp vs SMS vs both? (WhatsApp API costs, setup complexity)
- [ ] Vetting workflow — auto-approve public signups or all go through review?
- [ ] Get branding assets from Austin/mom — timeline?
- [ ] Domain setup — who controls joshtina.support DNS?
- [ ] Email provider for blasts — Resend (transactional) vs dedicated (Mailchimp/SendGrid)?
