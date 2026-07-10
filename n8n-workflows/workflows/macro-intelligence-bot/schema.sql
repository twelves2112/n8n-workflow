-- Macro Intelligence Bot — Supabase (Postgres) schema
-- Run once in the Supabase SQL editor before importing the workflows.

-- events: every high-impact calendar event ingested by Flow 1
create table events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  currency text not null,            -- USD / GBP / JPY
  event_time timestamptz not null,
  impact text not null,              -- High / Medium / Low / Holiday
  forecast text,
  previous text,
  event_hash text unique not null,   -- dedup key: title|currency|event_time
  briefed_at timestamptz,            -- null = not yet briefed; timestamp = brief sent
  created_at timestamptz default now()
);

-- briefs: (optional log) generated analysis per event
create table briefs (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references events(id) on delete cascade,
  brief_type text not null default 'pre_event',  -- pre_event | post_event
  content text not null,
  model text,
  sent_to_telegram boolean default false,
  sent_at timestamptz,
  created_at timestamptz default now()
);

create index idx_events_time on events(event_time);
create index idx_briefs_unsent on briefs(sent_to_telegram) where sent_to_telegram = false;
