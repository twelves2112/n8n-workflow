# Macro Intelligence Bot

An automated macroeconomic intelligence system that delivers pre-event scenario briefs for high-impact FX events straight to Telegram. It watches the economic calendar, filters to the events that move a defined set of pairs, reasons through each one with an LLM, and pushes a concise, scannable brief to a channel roughly two hours before the release.

Built with n8n (self-hosted), Supabase (Postgres), the Anthropic Claude API, and Telegram.

## What it does

For every upcoming High-impact USD / GBP / JPY event (Fed, BoE, BoJ and the core data releases), the bot produces a brief covering:

- **Context** — what's at stake and the relevant central bank's stance going in
- **Scenarios** — hotter / in-line / cooler outcomes, each with a directional read and a conviction band (High / Moderate / Low)
- **Watch** — the single nuance desks focus on beyond the headline number

It is a **pre-event** system: it reasons about expectations (forecast vs previous), not post-release actuals. Output is macro reasoning only — no trade signals, entries, or levels.

## Architecture

Two independent workflows sharing one Supabase database. They run on separate schedules so ingestion and briefing never block each other.

```
Forex Factory calendar
        │
   ┌────▼── FLOW 1: INGESTION (every 6h) ──────────────────┐
   │  fetch feed → filter High-impact USD/GBP/JPY →        │
   │  hash → upsert into events (ignore duplicates)        │
   └────────────────────────┬──────────────────────────────┘
                            ▼
              Supabase ▸ events table ◂  (shared store)
                            ▲
   ┌─────────────────────────┴── FLOW 2: BRIEFING (every 15m) ┐
   │  query events due in next 2h & not yet briefed →         │
   │  Claude writes brief → format → send to Telegram →       │
   │  stamp briefed_at (exactly-once guarantee)               │
   └──────────────────────────┬────────────────────────────────┘
                              ▼
                        Telegram channel
```

**Flow 1 — Ingestion** (`flow-1-ingestion.json`)
Schedule Trigger (6h) → HTTP Request (Forex Factory weekly JSON) → Code (filter to High-impact USD/GBP/JPY, rename fields, build a dedup hash) → HTTP Request (Supabase upsert with `on_conflict=event_hash` + `resolution=ignore-duplicates`, so re-runs never error or double-store).

**Flow 2 — Briefing** (`flow-2-briefing.json`)
Schedule Trigger (15m) → HTTP Request (query `events` for rows due in the next 2h where `briefed_at is null`) → Code (build the Claude request with the system prompt) → HTTP Request (Claude Messages API) → Code (format for Telegram) → Telegram (send) → HTTP Request (PATCH `briefed_at = now()`).

The `briefed_at` column is the dedup mechanism: once an event is briefed it is stamped, and the next query cycle filters it out — so each event is briefed exactly once regardless of how often the flow runs.

## Stack

- **n8n** (self-hosted) — orchestration
- **Supabase / Postgres** — event store + brief log
- **Anthropic Claude API** — analysis (Messages API, called via raw HTTP for full control)
- **Telegram Bot API** — delivery
- **Data source** — Forex Factory weekly calendar JSON (free)

## Setup

1. **Database** — run `schema.sql` in the Supabase SQL editor.
2. **Import workflows** — import both JSON files into n8n.
3. **Credentials** — create in n8n and map on import:
   - Supabase API credential (host + service_role key)
   - Telegram API credential (bot token)
   - Anthropic API key (set in the `x-api-key` header of the "Call Claude" node)
4. **Fill placeholders** — replace throughout both files:
   - `YOUR_PROJECT_REF` → your Supabase project ref
   - `YOUR_TELEGRAM_CHAT_ID` → your channel/chat ID
   - `YOUR_ANTHROPIC_API_KEY` → your Anthropic key
5. **Timezone** — brief headers format event times to `Africa/Lagos` (WAT). Change the `timeZone` string in the "Brain" node's Code to localize.
6. **Activate** both workflows.

## Notes & scope

- **Single-user** by design (one Telegram channel, one config). Not multi-tenant.
- **Pre-event only.** Post-event actual-vs-forecast analysis would require an actuals data source and is not implemented here.
- **Not financial advice.** The system produces educational macroeconomic analysis and explicitly avoids trade signals or price-action calls.
- Never commit real credentials. All identifiers in these files are placeholders; the Anthropic key belongs in an n8n credential or environment variable, never in a committed file.
