# NPC walk "needs room" check — design (short)

**Status:** approved 2026-11-21. Builds on `2026-11-21-npc-avoidance-routine-design.md`.

## Why

The Doorman stands in a 2 m gap in a wall; his talk walks him out to the `Aside` mark. When the
player starts the talk standing in front of him, a little right of centre, he wedges against the
wall end (walls aren't avoided), stops for ~3 s, then the walk timeout snaps him onto the mark past
the player (reproduced headless: player at (69.6, 4.2) and (70.2, 4.0) wedge him at (69.6, 3.4/3.1);
at (69, 4.3) and (69, 4.8) he gets out). The user's ask: for certain interactions the player must
leave the NPC room to act; if not, the NPC complains in dialog and stays put. A missing or wrong
check is acceptable (today's behavior); the system must stay simple.

## Approaches

1. **Opt-in fields on the `MOVE` step (picked).** The check lives on the walk it guards; no lines =
   no check.
2. A new `CHECK` step kind before the walk. More general than needed (YAGNI).
3. Automatic on every walk of a locked talk. Contradicts "for certain interactions".

## Design

- `NpcStep` `MOVE` shows two more fields: `lines` (the complaint versions, the same field `SAY`
  uses, same never-repeat pick) and `room` (metres, default 1.0). Empty `lines`: no check, the walk
  behaves exactly as today.
- When a `MOVE` with lines starts, the NPC checks whether the player stands ahead of it and within
  `room` (planar) of the straight line from the NPC to the mark (the segment, so standing on the
  mark counts; behind or level with the NPC doesn't — final review fix).
  - **In the way:** it says one of the lines like a `SAY` (locked talks wait for interact, `▸`;
    unlocked ones show it for its time), then the interaction ends right there (later steps
    skipped) and the NPC stays put. The run is not counted (its play is taken back, floor 0), so a
    `once` talk plays again from the top next time. Steps before the walk stay done (a `FLAG` step
    stays set).
  - **Clear:** it walks as today; the check isn't repeated mid-walk.
- The same on any trigger; a routine whose walk complains starts its loop over.
- Misconfigured (no lines, room too small): today's behavior (sidestep or wait, timeout snap).
- Summary row: `move → Aside (room 1.2 m)` when the step has lines.

## Demo, tests, docs

- The Doorman's `move → Aside` gets lines "You're in my way. Step back a bit." and room 1.2 (the
  regenerated demo scene; the help text says so).
- Tests (`npc_test.gd`, new section `room`): complaint instead of the walk (player on the line, and
  on the mark), the NPC stays put, the player is released, the `once` talk plays again and walks
  once the player stands clear; no lines = no check; the inspector shows `lines`/`room` for
  `MOVE`; demo: the two wedging spots complain and the Doorman stays, a clear spot (69, 4.8)
  steps him aside.
- One line each in `docs/npcs.md` (step table + walking paragraph) and CLAUDE.md.

## Non-goals

Wall/corridor awareness; re-checking during the walk; waiting at the complaint until the player
moves (the talk ends instead).
