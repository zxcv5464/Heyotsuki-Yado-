# AGENTS.md — Heyotsuki-Yado

## Project role

This repository is the existing official website and administration system.

It currently contains:
- public website pages
- staff management
- reservation and ordering systems
- Supabase schema and migrations
- admin pages under `admin/`

The new card game must remain a separate deployable website. Only shared database migrations and game-card administration UI belong in this repository.

## Safety rules

- Inspect the existing project before editing.
- Preserve all existing reservation, order, report, Discord notification, and staff management behavior.
- Do not rename or repurpose existing columns without an explicit migration plan.
- Do not expose Supabase `service_role`, database passwords, or private secrets in frontend files.
- Do not replace existing RLS policies blindly. Add narrowly scoped policies and document them.
- Do not use the local `STAFF_DATA` fallback for the production game card pool.
- Do not delete hidden or former staff card settings. Visibility must control eligibility.
- Make migrations idempotent where practical.
- Add rollback notes for every schema change.

## Existing staff source of truth

`public.staff_members` remains the source of truth for:
- staff ID
- staff name
- normal staff photo
- website visibility
- sort order

Verify exact column names and types against the current SQL files before writing migrations.

## Game-card administration

Create a separate one-to-one table rather than adding game-only fields to `staff_members`.

Preferred table name:

```text
public.game_staff_card_settings
```

Expected responsibilities:
- staff reference
- month number
- mark
- optional card title
- optional game-specific image
- game enabled flag
- timestamps

Season must be derived from month in one shared mapping, not independently editable.

The admin UI should provide:
- quick game-card status in existing staff management
- a dedicated game-card management page
- filters for unset, disabled, and hidden staff
- month and mark distribution counts
- optional automatic assignment for unset staff
- card preview using the same data as the game

## Eligibility rule

A staff member is eligible for newly created game decks only when:

```text
staff_members.is_visible = true
AND a usable image exists
AND game_staff_card_settings.is_game_enabled = true
AND required game-card settings exist
```

Already-started games keep their opening deck snapshot.

## Quality checks

Before finishing a task:
- run or document relevant smoke tests
- verify existing staff CRUD still works
- verify hiding a staff member removes them from new card-pool results
- verify hidden staff cannot be fetched through public policies or RPC
- verify no production secrets were committed
- summarize changed files and manual deployment steps
