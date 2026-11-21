# NPC avoidance and routines: short design

Date: 2026-11-21. Status: approved in conversation. Builds on
`2026-11-20-npc-interaction-design.md`.

## Intent

1. **Bug**: an NPC walking during an interaction (the Performer) pushes straight into the player
   when the player is in its way, then snaps to its mark after the walk timeout, possibly onto
   the player. During a locked talk the player can't step aside, so the NPC looks stuck.
2. **Feature**: NPCs that are already busy when you arrive: a routine they loop (walk, pause,
   mutter), avoiding the player on the way and waiting when the player stands where they are
   going.

## Goals

- While walking, an NPC steers around the player and other present NPCs.
- If the player stands on the walk's destination, the NPC walks up close and waits (facing the
  player, `anim = &"wait"`, `cue(&"blocked")` once), the walk timeout paused, until it is free.
- Exception: when the NPC's own locked interaction holds the player (the player can't move),
  the NPC stops beside the mark and counts as arrived, so the talk goes on.
- A walk-timeout snap never lands on the player.
- **Routine**: `NpcInteraction.Trigger.ROUTINE`, made of the usual steps. It plays whenever the
  NPC is present and nothing else runs, and loops. A key talk or a near bark cuts it; afterwards
  it resumes at the step it was cut on. `needs` works as for other triggers (first available
  routine in list order). Never locks the player.
- Demo: a sixth bay, **Routine**, with a sweeper looping four corner marks.

## Non-goals / anti-goals

- No navmesh or route planning: walls are still handled by the timeout snap.
- NPCs don't wait for other NPCs standing on their destination (only the player): two NPCs
  waiting for each other's spot would deadlock.
- Anti-goals: the player stuck in a locked talk; a routine that never waits freezing the game
  (looping in one frame); an NPC snapping into the player.

## Approaches

1. **Reactive steering (picked)**: each physics frame of a walk, obstacles are circles (player
   radius 0.4, NPC 0.35). The nearest one ahead within 2 m whose centre is closer than the
   clearance (1.0 m) to the walk line gives a detour point beside it, on the side away from it
   (a consistent side when dead ahead); the NPC heads there instead of the mark until it has
   passed. Small, fits the reactive enemy chase, needs no scene setup.
2. **NavigationAgent3D with avoidance**: needs a baked navmesh per scene; the project uses none
   (the enemy design rejected navmesh too).
3. **Wait-only**: stop whenever the player is ahead. Fails the locked-talk case.

Routine as a third trigger (picked) reuses steps, `needs`, memory and the inspector, versus a
separate patrol `Path3D` (new authoring, no lines or animations).

## Design notes

- Clearance 1.0 m (0.35 + 0.4 + 0.25 margin); look-ahead 2.0 m. The destination counts as taken
  when the player is within the clearance of it; the NPC stops when within clearance + 0.3 m.
- While waiting: `walking()` stays true, the timeout doesn't run, the head looks at the player,
  the body faces the mark. The wait ends the frame the destination is free.
- Snap after the timeout: skipped (timeout re-armed) if the player is within the clearance of the
  snap point.
- Routine: `play(i, from_step)`; the runner tracks the current step. A routine cut by `start_talk`
  or a near bark remembers its step; any interaction's end resumes the routine one physics frame
  later (so a routine of instant steps can't loop within a frame). Present again after being
  absent, or on load: the routine starts. Inspector hides `distance` and `locks_player` for
  routines; `once` keeps its meaning. Config warning when a routine has no step that takes time.
- Steering also applies to walks in barks and routines.

## Verification

`tests/npc_test.gd` new section: walking around a standing player (arrives well before the
snap time, never overlaps the player); waiting at a taken mark past the timeout, then arriving
once the player leaves; a locked talk with the held player on the mark arrives beside it; the
Performer case (held player between NPC and mark) arrives without a snap; routine loops its
marks, is cut by a talk and resumes at its step, a near bark fires during it, `needs` picks the
routine, an instant-step routine doesn't freeze (and warns). Demo test: the sweeper is moving.
Full suites after.

## Left to the builder

The `wait` placeholder animation, the sweeper's lines and layout, steering numbers within the
spirit above.
