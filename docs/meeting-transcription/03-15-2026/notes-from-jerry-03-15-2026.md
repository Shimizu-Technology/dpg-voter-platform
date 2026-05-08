[3/15/26 7:33 PM] Jerry: Okay, I've re-read the full transcript carefully against what I documented. Here's what I missed or under-documented the first time through:

───

🔍 Items I missed or didn't emphasize enough:

1. GEC Data Changes (Critical Context)

• GEC removed full date of birth from the voter list — now only provides birth year
• Registration numbers may have changed between lists (the system tracks this)
• This creates a disambiguation problem: multiple people with same name + same birth year (e.g., "4-5 John Cruzes born in 1994")
• Leon's plan: cross-reference GEC's online lookup tool using address + DOB to distinguish. During validation, flag ambiguous records for manual resolution.
• GEC removed data because someone on a prior campaign requested extra info, GEC's legal counsel reviewed, and they pulled back what they were sharing. "Messed up the system for everyone."

2. The GEC Only Provides PDFs — Intentionally

• They don't want campaigns manipulating the data
• GEC contracts out the list creation, gives parties only PDFs
• This is why Leon's PDF parsing work was so time-intensive — it's not optional, there's no Excel alternative for the official voter list

3. Import Comparison Between Lists

• December list: 16,000 active voters (this was the campaign's OWN list, not the full GEC list)
• January GEC list: 51,250 active voters, 19 villages
• Between Dec and Jan: 4,000 removed, 1,400 transferred, 667 updated records, 38,000 new
• The December list was actually from 2023 — it was a placeholder they had

4. Public Signup Tracking

• The system tracks whether a signup is "public" vs "staff-entered" — this distinction matters
• Public signups show separately in the voter check queue
• There's a counter showing pending public signups (the "1" they saw when Leon tested)

5. Form Scanning / OCR Testing

• They tested taking a picture of a physical blue form and uploading
• Handwriting recognition is the main challenge
• The green editable fields let you correct OCR errors before submitting to the queue
• You can rescan if needed
• They want to test more with real forms — Trisha gave Leon physical Q1 forms to test with

6. Dafne's Name Used for Testing

• They tested the signup form with "Dafne Dutch Shaz zoo at Gmail.com (http://gmail.com/)" (Dafne Shimizu — Leon's mom)
• Trisha wanted to test the joshtina.info (http://joshtina.info/) form to see who's monitoring it and where submissions go
• This was to investigate the competing system

7. The joshtina.info (http://joshtina.info/) Situation (More Detail)

• There's a separate "join the team" section on joshtina.info (http://joshtina.info/)
• Trisha had NO idea it existed until now — "I've only heard about it, I've never even looked at it"
• They used it during the campaign announcement event to input supporter names
• Trisha doesn't know who monitors it or where data goes
• Frank Ariola is suspected (a coworker keeps talking about it)
• Trisha submitted a test with Dafne's info to see who responds
• Risk: People signing up on joshtina.info (http://joshtina.info/) think they're supporting the campaign, but that data may never reach the VO/data team
• Decision: Make joshtina.info (http://joshtina.info/) info-only, add link to Leon's system (joshtina.support)

8. Ryan — Previous Developer Context

• Ryan built the previous system
• "He had to buy the website, put it under his business" — similar to what Leon's doing now
• The hosting cost was absorbed by Ryan's business last time
• Trisha is aware this costs money and is willing to cover it

9. Precinct Details

• Barrigada = Precinct 15 (15A, 15B, 15C)
• They won't break into sub-precincts (A, B, C) until closer to election
• But the system should be ABLE to report at that granularity when needed
• 67 precincts originally, may have reduced to 62

10. Village Performance C
[3/15/26 7:33 PM] Jerry: ontext

• MTM (Mongmong-Toto-Maite) — doing well on quota. Linda + Lola running it.
• Agana Heights — doing well. "Went over by two." Credit to Sonia + the mayor helping.
• Barrigada — struggling. John Birch Jr. is chief. "Only 22 for Barrigada... come on."
[3/15/26 7:33 PM] Jerry: • Tamuning — Trisha's district. Phone banking struggling, people not answering.
• Agana — very few registered voters who actually live there. Hard to meet quota.
• Trisha's observation: some villages are meeting, taking pictures (looking busy), but not producing results. She needs visibility to know HOW to help.

11. People Saving Forms / Gaming Quotas

• Some village orgs are SAVING supporters for future quotas instead of submitting immediately
• They turn in zero one month, then dump everything the next to avoid showing zero twice
• Trisha is against this: "Just submit. If you're over quota, great. Don't save it."
• But the shortage stacks: miss a quota + next month = double the work

12. Data Team Workload Context

• When it was just Trisha and Ryan: "Every day after work until we were done"
• They gave themselves one week per quota to process, then one week for VO to review
• This time: new team, new system, can't expect the same pace
• Rose needs to adjust expectations

13. Rose's Management Style

• "Old school" — would prefer cutting paper forms manually if she could
• Needs to see the system work with her own eyes to trust it
• Trisha's plan: demo one village end-to-end for Rose, show her the reports she's used to seeing
• Trisha is managing Rose's transition carefully — "she's just gonna have to be okay"
• Rose doesn't want village orgs auto-importing into the verified list (confirmed multiple times)

14. Security Concerns

• Multiple references to opponents potentially hacking or sabotaging the system
• "I wouldn't put it past anybody"
• Comparison to their accounting office security: key to cabinet → key to door → safe with combo
• This is why the backup system and hidden staff portal are priorities
• "Daphne's part of the team was trying to hack it down" — people have tried before
• "People actually hack your emails... they use the same password"

15. Account Whitelisting Flow

• Leon is whitelisting specific emails
• Users get an email, click signup, create their account with that whitelisted email
• They're then assigned the appropriate role (data team, etc.)
• Trisha already had login credentials from before but never logged in

16. The "Kota" Board Presentation (Next Monday March 24)

• Trisha wants to show the quota board at the next meeting with prior month's data
• Purpose: give village orgs a preview of what's coming — "this is what we're working towards"
• Even if the full system isn't ready for VO self-service, showing the dashboard plants the seed
• "Going forward, we're doing it manually now, but the idea is moving toward this"

17. Data Verification Double-Check Workflow

• When village orgs eventually self-enter: data team still gets the physical forms
• They must verify that what was entered digitally matches the physical form
• "Even if you know that I'm a registered voter and supporter, if the form wasn't submitted, we don't confirm"
• Numbers must match exactly — if village says 100, data team can't show 102 even if they know 2 are legit

18. Phone Banking Challenges (More Detail)

• Primary splits voter lists between candidates (2 Republicans + 3 on their side)
• Supporters who were on previous lists may have switched
• People are getting competing cold texts/calls from other campaigns
• Small villages literally don't have enough people to meet quota
• Some registered voters don't live in the village anymore

19. Timeline Clarification

• "We're a year and a half behind" — Trisha feels they started too late
• Primary election is the TEST for the general
• Mock run needed before election day — possibly during poll watcher training
• They need someone tech-savvy + someone manual at each precinct on election day

───

Items to add to Plane / update in sprint doc:

• CT-XX: GEC disambiguation handling — flag records where same name + birth year appears, provide workflow to resolve via GEC online lookup
[3/15/26 7:33 PM] Jerry: • CT-XX: Sub-precinct reporting capability — support 15A/15B/15C level even if not used immediately
• Update CT-92 (entry order) to include: data team needs to verify digital entries match physical form submissions exactly — numbers must match

Want me to create those additional tickets and update the sprint doc? And then I'm ready for whatever you want to discuss about it.