# Gym Membership

## Overview
Manages the full gym membership lifecycle: new member registration, daily expiry-reminder alerts, and renewal processing — with Airtable as the system of record and Gmail + Telegram for notifications. This workflow actually contains **three independent sub-flows** sharing one Airtable base.

## Trigger
- Sub-flow 1 (Registration): Webhook — `POST /gym-register`
- Sub-flow 2 (Expiry Reminder): Schedule Trigger — daily at 9:00 AM
- Sub-flow 3 (Renewal): Webhook — `POST /gym-renewal1`

## Flow

### 1. Registration (`Webhook` → ... → `Send a text message`)
1. **Webhook** (`gym-register`) — receives new member signup: `name`, `email`, `phone`, `plan`, `amount`.
2. **Code in JavaScript** — computes `startDate` (today) and `expiryDate` based on plan (Monthly = +1 month, Quarterly = +3 months, Annual = +1 year), sets `status: 'Active'`.
3. **Create a record** (Airtable) — inserts the new member into the `MEMBERS` table of the `Gym Management` base.
4. **Send a message** (Gmail) — sends a welcome email with plan, status, and dates.
5. **Send a text message** (Telegram) — notifies a fixed Telegram chat that a new member registered.

### 2. Expiry Reminder (`Schedule Trigger` → ... → `Send a text message1`)
1. **Schedule Trigger** — runs daily at 9:00 AM.
2. **Search records** (Airtable) — pulls all member records.
3. **If** — intended to filter for members expiring within 3 days.
4. **Edit Fields** — maps `recordId`, `memberName`, `memberEmail`, `expiryDate`, `plan` from the Airtable record into a flat object.
5. **Send a message1** (Gmail) — sends an "expiring soon" email with a renewal link placeholder.
6. **Send a text message1** (Telegram) — alerts staff via Telegram to follow up with the member.

### 3. Renewal (`Webhook1` → ... → `Send a text message2`)
1. **Webhook1** (`gym-renewal1`) — receives a renewal request: `email`, `plan`, `amount`.
2. **Search records1** (Airtable) — looks up the member by email (`filterByFormula`).
3. **Code in JavaScript1** — computes new `startDate`/`expiryDate` from today based on plan.
4. **Update record** (Airtable) — updates the matched record's Status, Start Date, Expiry Date, Amount Paid.
5. **Send a message2** (Gmail) — sends a renewal confirmation email.
6. **Send a text message2** (Telegram) — notifies staff of the renewal.

## Requirements
- Credentials:
  - Airtable Personal Access Token — **note:** Search records (sub-flow 2) uses a different Airtable credential (`Airtable Personal Access Token account`) than every other Airtable node in this workflow (`...account 2`). Confirm both point to the same base/permissions, or consolidate to one.
  - Gmail OAuth2 (shared across all three Send message nodes)
  - Telegram Bot API (shared across all three Send text nodes)
- Environment / hardcoded values:
  - Telegram `chatId: 8394239499` is hardcoded in all three Telegram nodes.
  - Airtable base (`Gym Management` / `appWeSlMFp3QkLHcX`) and table (`MEMBERS`) IDs are hardcoded.
  - The renewal email's "Renew Now" button link is a literal placeholder: `YOUR_RENEWAL_LINK`.

## Known issues / TODO
- **The expiry-reminder `If` node condition is broken.** It compares the literal string `"Condiion 1"` (note the typo) against a templated string like `"2026-08-01 is before 2026-07-06T..."` using the `equals` operator. This is comparing two strings for exact equality, not evaluating a date comparison — the condition will essentially never be true as written, so expiry reminders are not actually being filtered/sent correctly. This needs to be rebuilt as a proper date comparison (e.g. `dateTime` operator, "before" against `$now.plus({days:3})`).
- **Field name mismatch in `Edit Fields`.** It reads `$json["ExpiryDate"]` (no space), but the Airtable column is `Expiry Date` (with a space). This will always resolve to `undefined`, so the expiry-reminder email/Telegram alert will show a blank expiry date even once the `If` condition above is fixed.
- No dedup protection on the expiry reminder — since it runs daily against all members, anyone within the 3-day window (once the `If` is fixed) would get a new reminder every day until they renew, with no "already notified" tracking.
- Renewal email link is a hardcoded placeholder (`YOUR_RENEWAL_LINK`) rather than a real URL.

## Setup
1. Import `workflow.json` into n8n.
2. Reconnect Airtable, Gmail, and Telegram credentials across all nodes (note the two separate Airtable credential entries — decide if that's intentional).
3. Fix the `If` node in the expiry-reminder sub-flow to properly compare `Expiry Date` against `$now.plus({days: 3})`.
4. Fix the `Edit Fields` node's `expiryDate` assignment to read `$json["Expiry Date"]`.
5. Replace `YOUR_RENEWAL_LINK` with a real renewal URL.
6. Update the hardcoded Telegram `chatId` if staff notifications should go elsewhere.
7. Activate.
