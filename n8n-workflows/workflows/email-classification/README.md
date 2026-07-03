# Email Classification

## Overview
Watches a Gmail inbox for new unread mail, classifies each email into a department using keyword-based rules, and forwards a formatted HTML notification to the routed destination based on the classification.

## Trigger
- Type: Gmail Trigger (polling)
- Frequency: every minute
- Filter: unread messages only

## Flow
1. **Gmail Trigger** — polls for new unread emails every minute.
2. **Code in JavaScript** — rule-based classifier:
   - Pulls subject, snippet, and sender from the email.
   - Checks the combined subject + snippet text against five keyword lists (Sales, Customer Service, Human Resources, Finance, Operations), in that priority order — first match wins.
   - Defaults to `Other` if nothing matches.
   - Outputs `{ department, confidence: 'Rule-Based', subject, from, snippet, emailId }`.
3. **Switch** — routes on `department` to one of six branches (Sales, Customer Service, Human Resources, Finance, Operations, Other). `fallbackOutput` is set to `none`, so an unmatched value is dropped rather than erroring.
4. **Send a message / Send a message1–5** (Gmail) — one node per branch, each sends a styled HTML summary email (department, from, subject, preview, classification) to a fixed recipient.

## Requirements
- Credentials: Gmail OAuth2 (used by both the trigger and all six send nodes — same account)
- Environment / hardcoded values:
  - All six branches currently send to the same hardcoded address: `marvellousadebayo76@gmail.com`. Update per-branch if different departments should route to different inboxes.

## Known issues / TODO
- **Classification is single-match, priority-ordered keyword matching, not true NLP** — an email mentioning both "invoice" (Finance) and "refund" (Customer Service) will only ever hit whichever keyword list is checked first (Sales → Customer Service → HR → Finance → Operations). This can misclassify emails that span departments.
- **All routes notify the same inbox** — the department-based routing currently has no effect on *where* the email goes, only on the subject-line emoji/tag and body content. If the intent is to route to different team inboxes, each Send node's `sendTo` needs to be updated individually.
- One send node ("Send a message" — the `Other` branch) references `{{ $json.other }}` in its subject line, which doesn't exist in the Code node's output (the field is `department`, not `other`). This will render blank — likely a leftover from an earlier version and worth fixing.
- No dedup or already-processed tracking — if the workflow is restarted or reruns against the same unread emails, duplicate classification emails can be sent.
- Switch node's `fallbackOutput: none` means any future department not explicitly listed silently drops the email with no notification — worth having a true catch-all if new departments get added later.

## Setup
1. Import `workflow.json` into n8n.
2. Reconnect Gmail OAuth2 credentials (both trigger and the six send nodes).
3. Decide whether all branches should keep sending to one inbox or be split per department, and update `sendTo` on each Send node accordingly.
4. Review/expand the keyword lists in the Code node for your actual email patterns.
5. Activate.
