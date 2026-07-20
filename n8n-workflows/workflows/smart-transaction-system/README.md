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
