# D-PIA Tasks Reminder

## Overview
Automated task-reminder system that reads per-employee task tabs from a Google Sheet, checks for due/overdue tasks, and emails employees and their boss on a fixed weekly schedule. Built for non-technical handoff.

## Trigger
- Type: Schedule (n8n Schedule Trigger)
- Frequency:
  - Monday 9:00 AM — boss overdue alert run
  - Thursday 9:00 AM — boss overdue alert run
  - Thursday 10:00 AM — employee reminder run
  - Friday 5:00 PM — employee reminder run
- Timezone: `Africa/Lagos`

## Flow
1. **TaskTrigger** — fires on the schedule above.
2. **Get row(s) in sheet** — reads the "Team" tab of the "Team Tasks - per Employee" Google Sheet, which lists each employee (Name, Email, Sheet).
3. **Loop Over Items** — iterates over each employee row.
4. **Get row(s) in sheet1** — reads that employee's individual tab (`{{ Loop Over Items.item.json.Sheet }}`) for their tasks. `alwaysOutputData` is enabled so empty tabs don't stall the loop.
5. **Code in JavaScript** — core logic:
   - Filters out tasks marked "Done".
   - Parses due dates (handles ISO, several common formats, and Google Sheets serial dates).
   - Splits tasks into due and overdue.
   - On employee runs (Thu 10am / Fri 5pm): builds an email to the employee listing all due/overdue tasks.
   - On boss runs (Mon/Thu 9am): builds an email to the boss listing only overdue tasks, per employee.
   - If nothing to report, emits `{ skip: true }` to keep the loop moving.
6. **If** — checks `to` is not empty (i.e. there's actually an email to send).
   - True → **Send a message** (Gmail), then loops back to **Loop Over Items**.
   - False → loops back to **Loop Over Items** directly (no dead-end branch).

## Requirements
- Credentials:
  - Google Sheets OAuth2 (read access to the tracking sheet)
  - Gmail OAuth2 (send access)
- Environment / hardcoded values:
  - `BOSS_EMAIL` is hardcoded in the Code node (`prudentdan@gmail.com`) — update this if the boss changes.
- External services: Google Sheets, Gmail
- Sheet structure expected:
  - "Team" tab: `Name`, `Email`, `Sheet` (tab name) columns
  - Per-employee tabs: `Task`, `Due Date`, `Status`, `Priority` columns

## Known issues / TODO
- Boss email is hardcoded in code rather than pulled from a config/sheet — fine for single-boss use, but not easily reusable for other teams without editing code.
- No dedup/rate-limit protection — if the workflow is manually re-run on the same day, duplicate reminder emails will be sent.
- Both the Gmail node output and the **If** node's false branch wire back into **Loop Over Items** — this is required for the loop to continue; don't leave either branch dead-ended if you modify this workflow.

## Setup
1. Import `workflow.json` into n8n.
2. Reconnect Google Sheets OAuth2 and Gmail OAuth2 credentials (credential IDs won't carry over).
3. Update `BOSS_EMAIL` in the **Code in JavaScript** node if needed.
4. Confirm the Google Sheet ID/tabs match your own tracking sheet, or update `documentId`/`sheetName` in the two Google Sheets nodes.
5. Activate.
