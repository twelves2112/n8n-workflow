# Smart Transaction System

## Overview
A personal finance system that ingests bank/fintech debit-and-credit alert emails, uses Claude to parse and categorize each transaction, flags likely impulse purchases (while excusing pre-declared or self-transfer transactions), logs everything to Airtable, and sends a weekly AI-coached spending review to Telegram. This product is made up of **three separate n8n workflows** that share one Airtable base (`TRANSACTION SYSTEM`, `appvLlyTF8IbOdC89`).

| File | Workflow | Role |
|---|---|---|
| `1-ingestion-and-impulse-detection.json` | Smart Transaction System | Core pipeline: parses incoming bank emails, detects impulse spending, logs to Airtable |
| `2-pre-declared-form.json` | Pre-declared form (STS) | A form for declaring a planned purchase in advance so it isn't flagged as impulsive |
| `3-weekly-summary.json` | STS summary | Weekly Claude-written spending coach report sent to Telegram |

---

## 1. Ingestion & Impulse Detection (`1-ingestion-and-impulse-detection.json`)

### Trigger
Gmail Trigger, polling every minute, filtered to a specific Gmail label (bank alert emails).

### Flow
1. **Gmail Trigger** — polls the labeled inbox for new bank/fintech alert emails.
2. **Message a model** (Claude Haiku) — parses the raw email body into structured JSON: `is_transaction`, `transaction_date`, `amount`, `currency`, `merchant`, `transaction_type` (debit/credit), `self_transfer`, `category`, `spend_type` (Need/Want/Saving/Investment). Self-transfers are detected by matching the counterparty name against the account holder's own name variants.
3. **Code** — strips markdown fencing from Claude's response, parses the JSON, and maps the sender's email address to a clean bank name (OPay, GTBank, Kuda, Sterling, UBA) via a hardcoded lookup.
4. **If** — only continues if `is_transaction` is true (security alerts, promos, login notices, etc. are dropped here).
5. **Lookup(Merchant Map)** (Airtable) — see ⚠️ known issue below; intended to check whether this merchant has a remembered category from a past transaction.
6. **Merchant lookup code** — if the Merchant Map lookup returned a `Category`, it overrides Claude's category guess ("memory table wins").
7. **Switch** — routes on `transaction_type`: debit vs. credit vs. fallback ("extra").
8. **Transaction Rows** (Airtable) — creates a row in the `Transactions` table. ⚠️ **only the debit branch is wired to this node** — see known issues.
9. **Count Today's Debits** (Airtable search) — counts today's debit rows, for impulse-frequency detection.
10. **Get Pre-declared** (Airtable search) — pulls active (`Pending`, not yet expired) pre-declared purchases.
11. **Impulse Check** (Code) — the core logic:
    - Skips impulse checks entirely for self-transfers.
    - Matches the transaction against pre-declared amounts (±₦2,000 tolerance); if matched, it's not flagged as impulse.
    - Flags as impulse if: amount ≥ ₦20,000, OR category is Shopping/Eating out, OR 5+ debits already logged today.
12. **Matched Id_ not empty** (If) — if a pre-declared purchase was matched, continues to:
13. **Mark Matched** (Airtable update) — marks that pre-declared entry's Status as `Matched`.
14. **If1** — checks `is_impulse`; if true, continues to:
15. **Send a message** (Telegram) — sends a "🚨 Spending alert" message asking if the purchase was planned.

### Requirements
- Credentials: Gmail OAuth2, Anthropic API (Claude Haiku), Airtable Personal Access Token, Telegram Bot API
- Gmail label filter must be pre-configured to capture bank alert emails
- Airtable base `TRANSACTION SYSTEM` with tables: `Transactions`, `Pre-declared`, `Merchant Map`
- Account-holder name variants are hardcoded in the Claude system prompt for self-transfer detection

---

## 2. Pre-declared Form (`2-pre-declared-form.json`)

### Trigger
n8n Form Trigger ("Declare a Purchase") — protected with HTTP Basic Auth.

### Flow
1. **On form submission** — collects Description, Amount, and Days (validity window).
2. **Code in JavaScript** — computes `declared_on` (today) and `valid_until` (today + Days, defaulting to 7 if not provided), sets `status: 'Pending'`.
3. **Create a record** (Airtable) — inserts into the `Pre-declared` table (with `Category` mapped to an empty expression — see known issues).

### Requirements
- Credentials: HTTP Basic Auth (for the form itself), Airtable Personal Access Token
- Same Airtable base as workflow 1 (`Pre-declared` table)

---

## 3. Weekly Summary (`3-weekly-summary.json`)

### Trigger
Schedule Trigger — every Friday at 7:00 PM (`Africa/Lagos`).

### Flow
1. **Recommendations (4 weeks)** (Airtable search) — pulls the last 29 days of past AI-generated advice from the `Recommendations` table (used to give Claude memory of prior coaching).
2. **Aggregate week's transactions** (Code) — pulls the same period's rows from `Transactions`, excludes self-transfers, and computes: total spent, total received, net, transaction count, spend-by-category, spend-by-need/want, biggest single purchase, and impulse-flag count. Builds a plain-text `dataSummary` plus a `pastAdvice` block from step 1.
3. **Claude Coach** (Claude Sonnet) — a finance-coach persona (grounded in *The Psychology of Money* and *The Intelligent Investor* principles) writes a short, warm, Telegram-friendly weekly review under ~200 words, referencing the actual figures and gently following up on past advice.
4. **Send a text message** (Telegram) — delivers Claude's review.
5. **Create a record** (Airtable) — logs Claude's advice back into the `Recommendations` table (Trigger: "Weekly summary"), so the next week's run has memory of it.

### Requirements
- Credentials: Airtable Personal Access Token, Anthropic API (Claude Sonnet), Telegram Bot API
- Same Airtable base, tables: `Transactions`, `Recommendations`

---

## Known issues / TODO

- **🐞 Credit transactions are never logged (workflow 1).** The `Switch` node's connections only wire its first output (`debit`) to `Transaction Rows` — the `credit` output and the fallback `extra` output have no downstream connection at all. This means every incoming credit (money received) is silently dropped after classification and never reaches Airtable. This also means the weekly summary's "Total received" figure will always show ₦0, since it reads directly from the `Transactions` table. **Fix:** wire the Switch node's second output (credit) to `Transaction Rows` as well (and decide what, if anything, should happen on the fallback/`extra` output).
- **🐞 "Lookup(Merchant Map)" node performs a `create`, not a `search` (workflow 1).** Despite its name, this Airtable node's operation is `create` and only writes the `Merchant` field — it doesn't query for an existing category mapping. As a result, `Merchant lookup code`'s logic (`if (known.length > 0 && known[0].Category) { tx.category = known[0].Category }`) never actually finds a remembered category, since the node just created a fresh, mostly-empty row rather than searching for a prior one. Practically: (a) the "merchant memory" feature doesn't work as intended, and (b) every transaction creates a new duplicate row in `Merchant Map` rather than checking against existing ones. **Fix:** split this into two nodes — a `search` on `Merchant Map` filtered by `{Merchant} = tx.merchant` (feeding `Merchant lookup code`), and a separate `create`-or-`upsert` step later in the flow for genuinely new merchants only.
- **Pre-declared form's `Category` field maps to a literal empty expression** (`"Category": "="`) — every pre-declared entry will have a blank category in Airtable. Minor, but worth either removing the field mapping entirely or wiring it to a form input if categorization at declaration time is desired.
- **Impulse Check's node-name dependencies are fragile.** The Code node explicitly references nodes by name (`$('Code')`, `$('Get Pre-declared')`, `$('Count Today\'s Debits')`) with inline comments noting "name must match your renamed node exactly" — renaming any of those three nodes in the n8n editor will silently break this logic without an error until you inspect output.
- No dedup protection on ingestion — if Gmail redelivers a message, or the trigger double-polls, the same transaction could be logged twice (compounding the credit/debit logging gap above).
- Same shared Airtable credential (`Airtable Personal Access Token account 2`) and Telegram bot/channel across all three workflows and other products in this set — fine if intentional, but worth confirming isolation if this expands to multiple users/accounts later.

## Setup
1. Import all three JSON files into n8n as separate workflows.
2. Reconnect credentials on each: Gmail OAuth2, Anthropic API, Airtable Personal Access Token, Telegram Bot API, and HTTP Basic Auth (form workflow only).
3. Confirm the Airtable base ID and table IDs match your own `TRANSACTION SYSTEM` base, or update them if rebuilding from scratch.
4. **Fix the two bugs above before relying on this for real tracking** — particularly the missing credit-branch connection, since it silently breaks "money received" tracking.
5. Set the Gmail label filter on workflow 1 to match wherever your bank alert emails land.
6. Activate all three.
