# NPC interaction system design

Date: 2026-11-20. Status: draft for approval.

## Intent

AHRA needs people to talk to. This work builds the **backbone** for in-game NPC interactions:
an NPC holds a list of interactions, the player triggers them by walking close or by pressing
interact, and each one is a straight sequence of steps (a line in a billboard bubble, an
animation, a facial expression, a walk across the space, a sound). Pressing interact moves the
interaction to its next beat.

NPCs remember what they said: some lines play only once, after which the NPC repeats the same
thing, or versions of it, over and over. What an NPC has to say changes with the player's
progress through the game. After some talks an NPC leaves (the dialog implies they went
somewhere else): the screen fades to black briefly and the NPC is gone, possibly to be found at
that other place.

The point of the backbone: the data and the runner stay fixed when real characters arrive. A
future skeleton (no fingers) plugs into the same hooks: body animation keyed on `anim`, a set of
premade face animations keyed on `face`, and the head turning toward the player on top of
whatever the body is playing. Today all of that is drawn with prototype shapes.

## Goals

- **Interactions** on an NPC, in list order, each one either **near** (fires when the player comes
  within its `distance`) or **key** (fires when the player presses interact in the NPC's talk zone).
- **Steps**: say (with versions), animation, face, look, move to a mark, sound, wait, set flag, leave.
- **Beats**: steps run back to back until one waits; a line waits for the interact key. One press
  advances dialog, animation, movement and sound together.
- **Memory**: an interaction marked `once` never plays again. A line with versions picks one at
  random, never the same twice in a row.
- **Position memory**: an NPC stays where a talk walked it, and is still there after the area
  reloads ("he stepped aside from the door" sticks).
- **Progression**: an interaction can need story flags; it is skipped until they are all set.
- **Leaving**: a `leave` step fades to black, removes the NPC for good, sets a flag and fades back.
  An NPC can be placed to appear only once flags are set: the same character "found elsewhere".
- **Billboard dialog**: a bubble over the NPC's head, facing the camera.
- **Head look**: the head turns toward the player (or a mark) on top of the body's animation.
- **Face**: a set of named expressions plus blinking and a talking mouth, on prototype shapes.
- **NPC Tools** editor plugin: create NPC types, add NPCs to a scene, configure their interactions
  and marks.
- **Demo** scene built from prototype shapes, and a guide for hooking up a skeleton, face
  animations and sound later.

## Non-goals

- Branching dialog, player choices, player replies or a player speech bubble. The user picked
  straight sequences. A later `actor` field on `say` could give lines to someone else.
- A save system. `World.flags` is plain data meant to be saved next to `time` and `channels`.
- Camera moves during talks, typewriter text, localization, portraits.
- NPC routines (wandering, schedules), NPCs reacting to enemies or combat, NPCs under changed
  gravity (they fall world-down, like enemies).
- Real meshes, skeletons, animations or audio. Placeholders only; the guide explains the hookup.
- The general **placement palette** (click to place prefabs from a palette onto surfaces). It is
  the next project. Until then "add an NPC" means the tool's New NPC or dragging an NPC scene from
  the FileSystem dock into the viewport, which Godot already drops onto the surface under the
  mouse.

## Anti-goals (failure even if it "works")

- **The player stuck** in a locked talk: a walk that never arrives, a missing mark, an error in a
  step. Every wait has a way out, and a broken step is skipped with a warning.
- **Forgetting**: a `once` line replaying, a departed NPC back, or a moved NPC back at its placed
  spot, after reloading the area.
- **Bark loops**: a near interaction firing again and again while the player stands still.
- **Lost first line**: the interact press that starts a talk also skipping its first line.
- **Popping**: an NPC vanishing without the fade.
- Interact meaning two things at once (barking NPC and talk zone both reacting to one press).

## Constraints

- Godot 4.7.2, GDScript, static typing, `##` docs, committed `.uid` sidecars (see CLAUDE.md).
- Physics interpolation is on: NPC motion and placeholder animation run in the physics tick.
- `@tool` scripts guard runtime logic with `Engine.is_editor_hint()` and create child nodes in
  `_ready`, never as member defaults.
- NPC scripts reference the `World` autoload, so `-s` tests must not static-type them (CLAUDE.md
  gotcha); fetch World via `root.get_node("World")`. `Enemy` must not reference NPC code.
- Don't touch the user's own scenes (`demo/builder/`) or the editor layout.
- Fit the project's patterns: data as Resources edited in the inspector (like `PlatformSequence`),
  presentation polled from `anim` plus a `cue` signal (like `Enemy`), triggers as `Zone`s, the
  player locked through its existing `puppet` state, editor work undoable through
  `EditorUndoRedoManager` (like Platform Tools).

## Approaches considered

1. **Inspector resources (picked).** An NPC holds `Array[NpcInteraction]`; each holds
   `Array[NpcStep]`. Same pattern as tracks and their `PlatformSequence`s; the NPC tool is a
   better inspector plus commands. Cost: typing lots of dialog into inspector fields is slower
   than a text file.
2. **A text file per NPC** with a small format (`## greet once key`, `say: Hi. | Hello.`). Fastest
   for lots of dialog, diffable, easy to translate. Costs a parser, and typos in mark or animation
   names only show up as load warnings.
3. **AnimationPlayer timelines**: an interaction is an animation that pauses at markers for the
   key, with method tracks for lines and audio tracks for sound. Best for tightly timed scenes, but
   dialog text hides in track keys and keyframed walking ignores collision.

Dropped: the Dialogue Manager addon (solves text and conditions, but is built around branching and
2D balloons: a dependency for what option 1 does in a few hundred lines).

The user picked 1, for the editor tool they want to configure NPCs with.

## Design

### Files

| Path | What |
|------|------|
| `npc/npc.gd`, `npc/npc.tscn` | `Npc` body, runner, triggers, placeholder visuals |
| `npc/npc_interaction.gd` | `NpcInteraction` resource |
| `npc/npc_step.gd` | `NpcStep` resource (one class, a `kind` enum) |
| `npc/npc_talk.gd` | `NpcTalk`, the key-trigger zone (extends `Interactable`) |
| `world/world.gd` | + `flags`, `flags_changed`, `flag()`, `set_flag()`, `npcs`, `fade()` |
| `world/interactable.gd` | + `can_interact()` (default true); enter/exit add to and remove from the player's list |
| `player/player.gd` | `interactables` list; `interactable` = the nearest usable one, picked each physics frame |
| `addons/npc_tools/` | the NPC Tools editor plugin (enabled in `project.godot`) |
| `demo/npcs/npcs.tscn`, `npcs.gd` | demo area (extends `GameArea`) |
| `tests/npc_test.gd` | runtime suite (`-s`) |
| `tests/npc_tools_test.tscn` (+ `.gd`) | editor suite on `tests/editor_test.gd` |
| `docs/npcs.md` | authoring and presentation guide |
| `CLAUDE.md` | NPC section, the two new suites |

### World: flags and fade

```gdscript
signal flags_changed
## Story flags: name -> int. Saved with time, channels and signals.
var flags := {}
## NPC memory per placement: Channels.id(npc) -> {plays = {interaction id: count}, gone = bool,
## pos = Vector3, facing = Vector3}. Saved with the rest.
var npcs := {}
func flag(name: StringName) -> int          # 0 when unset
func set_flag(name: StringName, value := 1) # emits flags_changed
func fade(to_alpha: float, time := 0.4)     # awaitable; tweens a black full-screen ColorRect
```

- **Story flags** are game-wide plain names (`chapter2`, `mara_at_dock`), set by `flag` and
  `leave` steps or by any code (`World.set_flag`). Unlike channels they are not area-scoped:
  progress belongs to the game.
- **NPC memory** is keyed per placement with `Channels.id(npc)` (area and path): how many times
  each interaction played, whether the NPC left, and where it stands (see Position memory). A copy
  of a character placed elsewhere is another placement with its own memory. Positions are
  `Vector3`s, like the `Vector3` rates `channels` already holds.
- **Fade**: World creates a `CanvasLayer` (high layer) with a black `ColorRect` in `_ready`. It
  lives in the autoload so it survives scene changes (a `SceneDoor` can use it later; not in this
  work).
- `debug_text()` gains a `flags:` line. The demo area adds debug keys to clear `flags` and `npcs`
  and to reload the scene (to show memory surviving a reload).

### The NPC body (`Npc`, `npc/npc.gd`, `@tool`)

A `CharacterBody3D`, built like `Enemy` but much smaller: no state machine. It is either idle
(looking at the player when close) or running one interaction.

```
Npc (CharacterBody3D, npc.gd)
  Collision      CollisionShape3D, capsule
  Visual         Node3D at the feet (y = -0.8): body capsule, Head (turns) with eyes and mouth
  Talk           NpcTalk zone, sphere: where interact starts a key interaction
  Bubble         Label3D: billboard, no depth test, word wrap, outline
  Prompt         Label3D "E": shown while the player is in Talk and a key interaction is available
  Voice          AudioStreamPlayer3D
  Marks          Node3D holding Marker3D children (move and look targets)
```

Exports: `interactions: Array[NpcInteraction]`, `appears_if: PackedStringArray`,
`notice_distance := 6.0` (idle head look), `walk_speed`, `run_speed`, `color`.

Presentation state, polled like `Enemy.anim`:

- `anim: StringName`: `idle`, `walk`, `run`, `talk`, plus whatever `anim` steps name (the
  placeholder knows a handful: `wave`, `nod`, `shake`, `bow`, `jump`, `point`, `shrug`).
- `face: StringName`: `neutral`, `happy`, `sad`, `angry`, `surprised`, `thinking`.
- `look_target: Variant`: a global `Vector3`, or `null` for straight ahead.
- `speaking: bool`: a line is showing (drives the mouth).
- `cue(name)` signal: one-shot events (`say`, `arrive`, `leave`) for sound and VFX.

**Marks** are `Marker3D` children of `Marks`, so they move with the NPC while editing. `_ready`
caches their global positions by name **first**, before the NPC moves (walking or restoring its
saved spot), so marks always stay where they were placed.

**Movement**: `walk_to(point, run)` accelerates planar velocity toward the point with world-down
gravity and `move_and_slide`, turns the body toward its motion, and emits `arrived` within 0.3 m.
A walk that hasn't arrived after `distance / speed * 2 + 1` seconds snaps the NPC to the mark
and arrives anyway (anti-goal: stuck player).

**Position memory** (the user's choice: a moved NPC stays moved): the NPC writes its global
position and facing into its `World.npcs` entry on every `arrived` and at the end of every
interaction (a bark cut mid-walk stops where it is and is saved when the next talk ends). In
`_ready` at runtime, after caching marks, an NPC with a saved position teleports there, takes the
saved facing and resets physics interpolation. An NPC that never moved has no saved position and
starts at its placed spot, so moving it in the editor still works. Only walks move NPCs (the
player can't push a `CharacterBody3D`), so nothing else needs saving.

**Present / absent**: present when every `appears_if` flag is set and its memory doesn't say it
left.
Re-evaluated on `World.flags_changed`. Absent means hidden, collision off, Talk not monitoring,
no processing. In the editor NPCs always show.

**Config warnings** (editor): empty or duplicate interaction ids, steps after a `leave`, `move` or
`look` naming a mark that doesn't exist, `say` without lines, an interaction without steps.

### Interactions (`NpcInteraction`, `@tool` Resource)

| Field | Meaning |
|-------|---------|
| `id: StringName` | memory key; the tool fills unique ids (`talk`, `talk2`, `bark`) |
| `trigger: Trigger` | `KEY` or `NEAR` |
| `distance := 4.0` | NEAR only: fires when the player comes this close |
| `needs: PackedStringArray` | story flags that must all be set |
| `once := false` | plays a single time, ever |
| `locks_player := true` | key talks lock the player; the Bark template turns it off |
| `steps: Array[NpcStep]` | the sequence |

**Choosing**: when a trigger fires, the NPC plays the **first** interaction in list order with
that trigger that is available (needs met, and not a `once` already played). List order is
priority, so later-game interactions go above earlier ones: when `chapter2` is set, the chapter-2
talk is found first and the chapter-1 repeat line below it stops showing up. No `until` field.

A play is counted when it starts (so an interrupted `once` bark doesn't replay).

The setters keep `resource_name` as a one-line summary (`talk · key · once · needs chapter2 · 5
steps`), which the inspector shows on each array row instead of "NpcInteraction".

### Steps (`NpcStep`, `@tool` Resource)

One class with a `kind` enum. `_validate_property` shows only the fields of the chosen kind, and
`resource_name` keeps a summary (`say "Hello, stranger." (+2)`, `move → Well (run)`).

| Kind | Fields | Does | Waits for |
|------|--------|------|-----------|
| `SAY` | `lines: PackedStringArray`, `time` | shows one line (random version, not the last one shown), `cue(&"say")` | the key when locked; else `time` (0: 1 s + 0.04 s per character) |
| `ANIM` | `anim`, `time` | sets `anim` until changed | `time` (0: nothing) |
| `FACE` | `face` | sets `face` until changed | nothing |
| `LOOK` | `look` (`PLAYER`, `MARK`, `AHEAD`), `mark` | sets what the head follows | nothing |
| `MOVE` | `mark`, `run`, `wait := true` | walks to the mark | arrival when `wait` (with the snap timeout); else nothing, so the next line plays while walking |
| `SOUND` | `sound: AudioStream`, `wait` | plays on `Voice` | the sound's end when `wait` |
| `WAIT` | `time` | nothing | `time`; 0 means the key (locked) or 1 s (unlocked) |
| `FLAG` | `flag`, `value := 1` | `World.set_flag` | nothing |
| `LEAVE` | `flag` (optional), `fade := 0.4` | see Leaving | the fade; ends the interaction |

Steps that wait for nothing run in the same frame as the next step, so a beat is "everything up to
the next wait": `anim wave`, `face happy`, `sound hi`, `say "Hello!"` all start together and the
key moves on to the next beat. Only key waits listen to the key; walks, timed waits and sounds
finish on their own. A step that can't run (missing mark, no sound) warns and is skipped.

At the end of every interaction the NPC returns to `idle`, `neutral`, its default look, hides the
bubble, and releases the player.

### Triggers and the player

**Key**: `Talk` is an `NpcTalk` (an `Interactable` zone, shape edited with Shape Tools as for any
zone). `Interactable` gains `can_interact() -> bool` (true by default).

**Overlapping zones** (NPCs standing in groups): today the player keeps one `interactable`, the
zone entered last, and leaving any zone clears it. Instead, zones add themselves to
`Player.interactables` on enter and remove themselves on exit, and each physics frame the player
sets `interactable` to the **nearest zone in the list whose `can_interact()` is true** (null if
none). `ground_step` and the `interact` state keep using `interactable` unchanged, so a lone
switch behaves exactly as before. `NpcTalk.can_interact()` is true while the NPC is present, not
running a locked interaction, and has an available key interaction. `Prompt` shows only on the
zone that is the player's current `interactable`: the one a press would reach.
`NpcTalk.interact(p)` starts the talk **deferred** (so the player's `interact` state finishes
entering; that state already turns the player toward the zone) and returns `0.0`.

A locked interaction calls `p.start_puppet()` (no target): the player stands still, ignores input
and can't be damaged, all existing behaviour. The NPC turns to face the player. `p.end_puppet()`
at the end.

**The key inside a talk** is `interact`, read by the NPC in `_physics_process`, ignoring the
physics frame the talk started on (anti-goal: lost first line).

**Near**: the NPC checks the player's distance (player found through the `player` group) each
physics frame while idle. A near interaction fires when the player comes within its `distance`
and re-arms once the player is beyond `distance + 1 m` (anti-goal: bark loops). Near interactions
default to not locking: lines advance on their timers. Pressing interact in `Talk` during a bark
cuts the bark and starts the key talk (one meaning per press).

### Bubble

`Bubble` is a `Label3D` above the head: billboard, `no_depth_test` so walls don't hide it, word
wrap at a fixed width, an outline for contrast, sized for the iso camera. A `▸` at the end of the
line while it waits for the key. Hidden when nothing is said. No background panel (a billboard
quad behind the text is an easy later polish).

### Head look and face (placeholders)

**Head look**: each physics frame the target is, in order: the interaction's `look` override; the
player when within `notice_distance`; else straight ahead. The `Head` node rotates toward it in
the body's frame, yaw clamped to ±75° and pitch to ±35°, eased. Because `Head` sits under `Visual`,
the body's squash and tilt from `anim` carry it, and the turn is applied on top: the mix the real
skeleton will get from `LookAtModifier3D` (see the guide).

**Face**: two box eyes and a box mouth on the head sphere. Each `face` sets their scale and tilt;
eyes blink every 2-5 s on their own; the mouth flaps while `speaking`.

**Body** (`_animate`, physics tick): squash, bob and tilt per `anim`, like the player and enemy
placeholders. `ponytail:` comment marking it as the stand-in for an `AnimationTree`.

### Leaving and appearing

A `leave` step: lock the player if the interaction didn't, `await World.fade(1.0)`, mark the NPC
gone in its memory and set the step's `flag`, the NPC turns absent, `await World.fade(0.0)`, release the
player, end the interaction. Steps after it never run (warned in the editor).

"She'll be at the dock" is a second NPC placed at the dock with `appears_if = [mara_at_dock]` and
its own interactions. It appears the moment the flag is set (behind the fade, if it's in the same
area) or when its area loads later. A departed NPC stays gone across reloads, because its memory is
in World.

### NPC Tools plugin (`addons/npc_tools`)

Follows Platform Tools: an icon menu in the 3D toolbar, a second one while an NPC is selected,
every change undoable through `EditorUndoRedoManager`.

**Create**: *New NPC Type…* asks for a name and writes `npc/<name>/<name>.tscn`, a scene
inherited from `npc/npc.tscn` (instantiate with `GEN_EDIT_STATE_MAIN_INHERITED`, pack, save),
then opens it. Types change the look and defaults; interactions belong to placements.

**Add**: *New NPC* (submenu of `npc.tscn` and every type found under `npc/`) instances it into the
edited scene at the surface below the view centre, selected. *NPCs (N)* lists the scene's NPCs to
select or remove (like *Tracks (N)*). Dragging an NPC scene from the FileSystem dock also works;
the palette project will replace both with one placement tool.

**Configure** (NPC selected):
- *Add Interaction* ▸ **Talk once** (key, once: say, say), **Talk** (key: say with three
  versions), **Bark** (near, unlocked: say), **Leave** (key, once: say, leave). Unique ids, appended
  to the list.
- *Add Mark*: the next viewport click places a `Marker3D` under `Marks` on the surface hit (editor
  physics raycast; a horizontal plane through the NPC's feet when nothing is hit). Esc cancels.
- The inspector does the rest: array rows read as summaries, step fields follow the step kind,
  config warnings flag broken references.

### Demo (`demo/npcs/npcs.tscn`)

A `GameArea` with `Bays`, all prototype shapes:

1. **Greeter**: barks "Hey, over here!" when you approach (near, unlocked); a once intro talk
   (wave, happy, three lines); afterwards a repeat line with versions. Shows the idle head look.
2. **Progression**: Smith says "Come back when the bell has rung" until `bell_rang` is set; the
   Ringer next to him sets it in his talk (`flag` step); Smith's chapter talk is listed above and
   takes over.
3. **Performer**: a long locked talk that walks between marks (one walk while talking), points and
   looks at a mark, changes faces and animations, and plays sounds. A **Doorman** blocks a gap
   until a once talk walks him aside; after a reload he is still aside.
4. **Leaver**: Mara says she'll wait at the dock, leaves (fade), and her copy appears at the dock
   (bay 5, across the room) with new lines.

The project has no audio files: the demo's sound is a short generated tone saved as an
`AudioStreamWAV` resource. Debug keys clear `World.flags` and `World.npcs` to replay everything,
and reload the scene to show what is remembered; the HUD shows the flags.

### Verification

`tests/npc_test.gd` (`-s`, sections filterable after `--` like the enemy suite), each section on a
small course built in code with a player and NPCs created from scripts, not static types:

- key: interact in `Talk` starts the first available key interaction, the player is puppeted, each
  press advances exactly one line, the starting press doesn't skip line 1, the player is released.
- overlap: with two talk zones overlapping, the nearer usable NPC answers and alone shows the
  prompt; an NPC with nothing to say is passed over; leaving one zone keeps the other working.
- memory: `once` doesn't replay (also after freeing and re-instancing the NPC); the repeat takes
  over; 20 plays of a three-version line never repeat back to back.
- progression: an interaction needing a flag is skipped, then chosen first once the flag is set.
- near: fires on approach without locking, doesn't refire while the player stays, refires after
  leaving and coming back; interact during a bark starts the key talk.
- moves and beats: `move` arrives at the cached mark position, a blocked walk snaps after the
  timeout, `wait = false` overlaps the next line; anim, face and look are set by steps and reset
  at the end.
- leave: the fade reaches black and clears, the NPC is absent (hidden, no collision), the flag is
  set, an `appears_if` copy turns present, a re-instanced original stays gone.
- position: after a talk walks an NPC to a mark, a freed and re-instanced NPC stands at the end
  spot with the same facing, its marks are still at their placed positions (a second talk can walk
  it back to its start mark), and an NPC that never moved starts at its placed spot.
- head: the head yaw turns toward the player within the clamp.
- the demo scene loads and runs without errors.

`tests/npc_tools_test.tscn` on `tests/editor_test.gd`: New NPC Type writes an inherited scene, New
NPC instances and undo removes it, each Add Interaction template appends and undoes, Add Mark
places a marker.

Also run `smoke_test` (player `ground_step` change), `puzzle_test` (`PlatformSwitch` is an
`Interactable`) and both existing editor suites. Game feel is untested and the report says so.

### Docs

`docs/npcs.md`: authoring (list order is priority, `once`, versions, `needs`, leaving and copies,
marks, moved NPCs staying moved, the tool), flags, NPC memory and saving, and the presentation
hookup:

- **Body**: an `AnimationTree` state machine keyed on `anim`, callback mode Physics, replacing
  `_animate` (as in the enemy guide).
- **Head**: a `LookAtModifier3D` on the head bone (built into Godot 4.4+) whose target is a node
  the NPC moves to `look_target` each frame, influence eased to 0 when it is `null`. It blends over
  whatever the body plays: the mix the placeholder imitates.
- **Face**: premade face animations in a second `AnimationPlayer` (or blend shapes) named after
  the `face` values, with blink and mouth-flap on top from `speaking`.
- **Sound**: a presenter child listening to `cue` (voice blips on `say`, footsteps on `walk`).

CLAUDE.md gets an NPC section and the two suites in its test list.

## Left to the builder

- The placeholder look: head and face proportions, the exact set of `anim` and `face` values,
  their squash and tilt numbers, blink timing.
- Bubble styling: font size, pixel size, width, outline, the `▸` mark.
- Default timings (`distance`, line time per character, fade time, walk timeout factor).
- Whether `NpcStep` hides fields with `_validate_property` or splits into subclasses, as long as
  the inspector shows only the fields of the chosen kind.
- Summary text formats for `resource_name`.
- How the plugin raycasts in the editor for New NPC and Add Mark.
- Demo layout, texts, colours and the generated tone.

## Next project

The **placement palette**: a general editor tool to pick prefab scenes (scenes that hold other
scenes and effects) from a palette and place them by clicking surfaces under the cursor. NPC
types become entries in it. Brainstormed separately after this ships.
