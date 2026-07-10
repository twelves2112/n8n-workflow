# n8n Workflows

A collection of n8n automation workflows. Each folder under `workflows/` contains the exported workflow JSON plus a README documenting what it does, its requirements, and known issues.

## Workflows

| Workflow | Description |
|---|---|
| [D-PIA Tasks Reminder](workflows/d-pia-tasks-reminder/README.md) | Weekly employee/boss task reminder emails, sourced from a Google Sheet. |
| [Email Classification](workflows/email-classification/README.md) | Classifies incoming Gmail messages by department via keyword rules and forwards a notification. |
| [Gym Membership](workflows/gym-membership/README.md) | Registration, expiry reminders, and renewal handling for gym members via Airtable. |
| [Order and Reservation](workflows/mama-tee/README.md) | Parses Vapi voice-call transcripts for a restaurant into orders/reservations/callbacks logged to Airtable. |
| [Transaction Log](workflows/transaction-log/README.md) | Parses bank debit-alert emails (OPay, GTBank, Kuda, Sterling) and logs categorized transactions to Notion. |
| [Smart Trasnsaction System](workflows/smart-transaction-system/README.md) | Parses bank debit and credit alert emails categorize each transaction, flags likely impulse purchases (while excusing pre-declared or self-transfer transactions), logs everything to Airtable. |
| [Macro Intelligence Bot](workflows/macro-intelligence-bot/README.md) | Delivers pre-event scenario briefs for high-impact FX events straight to Telegram. |

## Usage

Each workflow folder is self-contained:
1. Open the workflow's README for an overview, required credentials, and setup steps.
2. Import `workflow.json` into your n8n instance (**Workflows → Import from File**).
3. Reconnect credentials — these are never exported with the workflow JSON, so you'll need to select/create them after import.
4. Review the "Known issues / TODO" section of each README before activating.

## Notes

- All workflows assume `Africa/Lagos` timezone unless noted otherwise.
- Node credential *references* (IDs/names) are visible in the JSON, but no actual secrets, tokens, or API keys are included in these exports — n8n never exports credential values.
