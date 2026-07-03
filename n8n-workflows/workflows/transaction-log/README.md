# Transaction Log

## Overview
Watches Gmail for bank/wallet debit-alert emails (OPay, GTBank, Kuda, Sterling Bank), parses the transaction details out of each email via bank-specific regex, auto-categorizes the spend, and logs it as a row in a Notion database.

## Trigger
- Type: Gmail Trigger (polling)
- Frequency: every minute
- Filter: none set at the trigger level — filtering happens downstream in the **If** node

## Flow
1. **Gmail Trigger** — polls the inbox every minute for new mail (no built-in filter, so it fires on everything and relies on the next node to discard irrelevant mail).
2. **If** — passes the email through only if the `From` address contains one of: `opay-nigeria.com`, `gtbank.com`, `kuda.com`, `sterling.ng` (case-insensitive, OR combinator). Anything else is silently dropped (false branch has no connection).
3. **Code in JavaScript** — bank-specific parser, branching on sender domain:
   - **OPay**: extracts amount (`₦...`), recipient name (`Name: ... Bank:`), recipient bank.
   - **GTBank**: extracts amount (`NGN ...`), description/recipient from the `Description:` field, remarks.
   - **Sterling Bank**: extracts amount (`NGN...`), recipient from `Description ... to <name>`.
   - **Kuda**: extracts amount, recipient, and narration from `"You just sent ₦X to Y - narration"`.
   - Outputs a normalized `{ description, amount, date, recipientBank, bank, emailBody }` object. (Note: an older single-bank OPay-only version of this logic is left commented out at the top of the code, marked "to be used when I allow multiple banks" — now superseded by the active multi-bank version below it.)
4. **Code in JavaScript1** — categorization:
   - Keyword matching across ~9 category keyword lists (Food & Dining, Transportation, Airtime & Data, Entertainment, Education, Shopping, Bills & Utilities, Gift, Debt Repayment) checked against the email body, description, and narration.
   - Defaults to `Transfer` if nothing matches.
5. **Create a database page** (Notion) — writes Description, Amount, Date (Africa/Lagos timezone), Category, Bank, and the raw Email Body into the `Transaction Log` Notion database.

## Requirements
- Credentials:
  - Gmail OAuth2
  - Notion API (`Notion account 2`)
- Notion database: `Transaction Log`, with properties `Description` (title), `Amount` (number), `Date` (date), `Category` (select), `Bank` (rich text), `Email Body` (rich text).

## Known issues / TODO
- The hardcoded per-recipient name lookup (previously used to categorize known contacts, e.g. "this person = Food & Dining") has been removed for privacy — this version relies entirely on keyword matching. As a result, transfers to known people that don't match any keyword will now fall through to the `Transfer` default instead of their previously assigned category. If you want per-contact categorization back, reintroduce it via an environment variable or an Airtable/Notion lookup table (not hardcoded in the workflow file) so personal names don't live in source control.
- Parsing is entirely regex-based per bank and will break silently if any bank changes its email template — worth periodically spot-checking Notion entries for blank/incorrect `description` or `amount` values.
- No dedup protection — if Gmail re-delivers or the trigger re-polls the same message, it could be logged twice.
- The **If** node's false branch is intentionally left unconnected (not a bug — unlike the loop-based workflows in this set, there's no loop here to stall; non-matching emails are just dropped).
- Commented-out legacy OPay-only code sits at the top of the first Code node — harmless, but candidate for cleanup for readability.

## Setup
1. Import `workflow.json` into n8n.
2. Reconnect Gmail OAuth2 and Notion credentials.
3. Confirm your Notion `Transaction Log` database ID and property names match those referenced in the Notion node.
4. Add/adjust bank-specific parsing blocks in the first Code node if you add more banks.
5. (Optional) If you want per-contact categorization, add it back via an environment variable or Airtable/Notion lookup table rather than hardcoding names in the Code node.
6. Activate.
