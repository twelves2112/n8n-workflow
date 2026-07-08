# Restaurant Order & Reservation Workflow (Vapi)

## Overview
Receives call data from a Vapi voice AI agent for "Mama Tee's Kitchen" (a restaurant), parses the call transcript with regex to classify and extract structured details, logs the result into the appropriate Airtable table, and posts a summary to Telegram for staff.

## Trigger
- Type: Webhook — `POST /mama-tee`
- Response mode: `lastNode` (waits for the workflow to finish and returns the last node's output — likely used as the response back to Vapi)

## Flow
1. **Webhook** (`mama-tee`) — receives the Vapi call payload (handles several possible Vapi payload shapes defensively).
2. **Code in JavaScript** — the core parsing engine:
   - Extracts the transcript from various possible payload locations.
   - Extracts customer phone from the structured `call.customer.number` field, falling back to regex over the transcript (`"phone number is..."`, `"call me on..."`, etc.) if missing.
   - Classifies the call into one of four types via keyword matching, first-match-wins: **Order** (food/menu keywords), **Reservation**, **Callback Request**, or **General Inquiry** (default).
   - Extracts customer name via regex patterns (`"my name is..."`, `"this is..."`, etc.).
   - For orders: extracts order details, delivery vs. pickup, and any special requests (extra pepper, no onion, allergy, etc.) via regex.
   - For reservations: extracts group size and reservation date/day via regex.
   - For callbacks: stores the first 300 characters of the transcript as the callback question.
   - Builds a one-line `summary` and returns a structured object with all extracted fields plus a timestamp.
3. **Switch** — routes on `callType` to one of four branches: Order, Reservation, Callback Request, General Inquiry.
4. **Orders Record / Reservation records / Callback Requests records / General inquiry records** (Airtable) — each branch creates a record in its corresponding Airtable table (`Orders`, `Reservations`, `Callback Requests`, and presumably a general-inquiries table) within the `Mama Tee's Kitchen` base.
5. **Send a text message** (Telegram) — all four branches converge here, sending a staff notification with call type, customer name/phone, summary, and timestamp.

## Requirements
- Credentials:
  - Airtable Personal Access Token (`...account 2`, shared across all four Airtable nodes)
  - Telegram Bot API (shared, hardcoded `chatId: 8394239499`)
- Airtable base: `Mama Tee's Kitchen` (`appqX2NyVCWNOTLN1`), with separate tables for Orders, Reservations, Callback Requests, and General Inquiries.
- External service: Vapi (voice AI) must be configured to POST call data to this webhook.

## Known issues / TODO
- **Order Type is hardcoded.** The `Orders Record` node writes `"Order Type": "=Delivery"` unconditionally, even though the Code node already detects `orderType` as `Delivery` or `Pickup` from the transcript. Pickup orders will be mislabeled as Delivery in Airtable. Fix: map `Order Type` to `={{ $json.orderType }}`.
- **Field-name mismatch in `Reservation records`.** It maps `"Phone Number": "={{ $json.phoneNumber }}"`, but the Code node's output field is `customerPhone`, not `phoneNumber`. This will always resolve to blank — reservations will save with no phone number. Fix: change to `={{ $json.customerPhone }}`.
- All extraction (name, phone, order details, dates, etc.) is regex-based against free-form transcript text — inherently fragile against phrasing the patterns don't anticipate. Worth monitoring Airtable records for a stretch to see how often fields land as blank/"unclear" and expanding patterns as needed.
- No dedup protection — if Vapi retries a webhook delivery, the same call could be logged twice.
- Same Telegram `chatId` and single Airtable credential pattern as other workflows in this set — consolidate/verify these are intentional if managing many workflows.

## Setup
1. Import `workflow.json` into n8n.
2. Reconnect Airtable and Telegram credentials.
3. Fix the two known field/mapping bugs above (`Order Type` and reservation `Phone Number`).
4. Confirm the `General inquiry records` Airtable table ID/name matches your base (not fully visible in this JSON excerpt — verify against your Airtable base directly).
5. Point your Vapi assistant's webhook/tool-call configuration at this workflow's webhook URL.
6. Activate.
