# NPCs

Non-player characters the player talks to. An NPC holds an ordered list of **interactions**; the
player triggers one by pressing interact in the NPC's talk zone (**key**) or by walking close
(**near**). An interaction is a straight sequence of **steps**: a line in a billboard bubble, an
animation, a facial expression, a walk to a mark, a look, a sound, a wait, a story flag, leaving.
Pressing interact moves a talk to its next beat.

NPCs remember: a `once` interaction never plays again, a moved NPC stays where its talk left it,
and an NPC that left stays gone, also after the area reloads. What an NPC says changes with the
player's progress through **story flags**.

Everything visible is a placeholder made of prototype shapes. The NPC exposes the values a real
rig reads (body animation, face, head target, talking), so a skeleton plugs in without touching
the gameplay code. See [Hooking up presentation](#hooking-up-presentation).

## The pieces

| File | What |
|------|------|
| `npc/npc.gd`, `npc/npc.tscn` | `Npc`: the body, the interaction runner, triggers, placeholder visuals |
| `npc/npc_interaction.gd` | `NpcInteraction`: one interaction (trigger, needs, once, steps) |
| `npc/npc_step.gd` | `NpcStep`: one step; `kind` picks what it does |
| `npc/npc_talk.gd` | `NpcTalk`: the talk zone (an `Interactable`) |
| `world/world.gd` | `World.flags` (story flags), `World.npcs` (NPC memory), `World.fade()` |
| `addons/npc_tools/` | NPC Tools editor plugin |
| `demo/npcs/` | demo area |
| `tests/npc_test.gd`, `tests/npc_tools_test.*` | runtime and editor suites |

`npc.tscn`:

```
Npc (CharacterBody3D, npc.gd)
  Collision   capsule, radius 0.35, height 1.6
  Visual      feet at y -0.8: Body capsule, Head (turns) with Skull, EyeL, EyeR, Mouth
  Talk        NpcTalk zone, a 2 m sphere (edit it like any zone, Shape Tools)
  Bubble      Label3D: billboard, drawn over walls, word wrap
  Prompt      Label3D "E"
  Voice       AudioStreamPlayer3D
  <marks>     Marker3D children you add: floor points the NPC walks to and looks at
```

## Making NPCs

**NPC Tools** (the person icon in the 3D toolbar):

- **New NPC** puts `npc.tscn`, or a type, on the surface below the view centre and selects it.
  Dragging an NPC scene from the FileSystem dock into the viewport works too.
- **New NPC Type...** writes `npc/<name>/<name>.tscn`, a scene inherited from `npc.tscn`, and
  opens it. A type sets a look and defaults (colour, speeds, talk zone size). Interactions belong
  to each placed NPC, not to the type.
- **NPCs (N)** lists the scene's NPCs to select or remove.

With an NPC selected, a second icon menu appears:

- **Add Interaction**: **Talk once** (key, once), **Talk** (key, a line with three versions),
  **Bark** (near, doesn't hold the player), **Leave** (key, once, says goodbye and leaves). Each
  gets a unique id and placeholder lines to edit.
- **Add Mark**: click in the viewport to drop a `Marker3D` child on the surface there (`Mark`,
  `Mark2`...; rename them). Esc cancels. You can also add `Marker3D` children by hand.

The inspector does the rest. Each interaction and step row shows a one-line summary
(`talk · key · once · needs chapter2 · 5 steps`, `say "Hello, stranger." (+2)`), a step shows
only the fields of its kind, and the NPC's configuration warnings flag empty or duplicate ids,
missing marks, steps after a leave, lines without text and interactions without steps.

Every tool change is undoable.

## Interactions

| Field | Meaning |
|-------|---------|
| `id` | memory key (how many times it played); unique per NPC |
| `trigger` | `KEY`: interact in the talk zone. `NEAR`: the player comes within `distance` |
| `distance` | near only, metres (default 4) |
| `needs` | story flags that must all be set |
| `once` | plays a single time, ever |
| `locks_player` | the player stands still and interact advances the lines (key talks). Off: lines advance on timers and the player keeps moving (barks) |
| `steps` | the sequence |

**List order is priority.** When a trigger fires, the NPC plays the first interaction in its list
with that trigger that can play now. Put later-game interactions above earlier ones: before
`chapter2` is set the chapter-2 talk is skipped, after it the chapter-2 talk is found first and the
old line below it stops showing up. A typical NPC:

```
1. ch2_intro   key · once · needs chapter2
2. ch2         key · needs chapter2          (repeats, with versions)
3. intro       key · once
4. chat        key                            (repeats, with versions)
5. bark        near 6 m · free
```

A play is counted when it starts, so a `once` bark the player cuts short doesn't come back.

**Near** interactions fire when the player comes within `distance`, and fire again only after the
player has been farther than `distance + 1 m`: standing still never loops a bark. They don't fire
while the player is held by another NPC's talk. Pressing interact in the talk zone during a bark
cuts it and starts the NPC's key talk.

## Steps and beats

Steps run back to back until one waits. A **beat** is everything up to the next wait, so
`anim wave`, `face happy`, `sound`, `say "Hello!"` all start together, and one press of interact
moves on to the next beat.

| Kind | Fields | Does | Waits for |
|------|--------|------|-----------|
| `SAY` | `lines`, `time` | shows one line in the bubble: a random version, never the one shown last time | interact (locked talks, `▸` shows); else `time` (0: 1 s + 0.04 s per character) |
| `ANIM` | `anim`, `time` | sets `anim` until another step changes it | `time` (0: nothing) |
| `FACE` | `face` | sets `face` until changed | nothing |
| `LOOK` | `look` (player, mark, ahead), `mark` | what the head follows for the rest of the interaction | nothing |
| `MOVE` | `mark`, `run`, `wait` | walks to the mark | arrival when `wait`; else nothing, so the next line plays while walking |
| `SOUND` | `sound`, `sound_wait` | plays on `Voice` | its end (or its length) when `sound_wait` |
| `WAIT` | `time` | nothing | `time`; 0: interact (locked) or 1 s (unlocked) |
| `FLAG` | `flag`, `value` | sets a story flag (0 clears) | nothing |
| `LEAVE` | `flag`, `fade` | see Leaving | the fade; ends the interaction |

Only interact advances lines and key waits; walks, timed waits and sounds finish on their own. A
walk that hasn't arrived after `distance / speed * 2 + 1` seconds snaps the NPC to its mark, so a
blocked walk never strands the player. A step that can't run (a missing mark, no sound, no lines)
warns and is skipped.

At the end of every interaction the NPC goes back to `idle`, `neutral`, its default look, hides the
bubble, saves where it stands (if it walked) and releases the player.

**Marks** are floor points. The head looks 1.5 m above a mark (at someone standing there), and a
snapped walk lands the NPC standing on it. They are cached when the NPC loads, before it ever
moves, so walking doesn't drag them along. Moving an NPC in the editor moves its marks with it.

## Leaving and copies

A `LEAVE` step holds the player (also during a bark), fades the screen to black, marks the NPC
gone in its memory, sets the step's `flag`, holds black for 0.15 s, and fades back. The NPC is
absent from then on: hidden, no collision, no talk zone. Steps after a leave never run.

"She'll be at the dock" is a second NPC placed at the dock with `appears_if = [mara_at_dock]` and
its own interactions. NPCs re-check `appears_if` whenever a flag changes, so a copy in the same
area appears behind the fade, and one in another area is there when that area loads. Each
placement has its own memory.

## Flags, memory and saving

- **Story flags** (`World.flags`): game-wide plain names (`chapter2`, `bell_rang`), set by `FLAG`
  and `LEAVE` steps or from code with `World.set_flag(name, value)`; `World.flag(name)` reads one
  (0 when unset). Unlike platform channels they are not scoped to an area. Setting one emits
  `World.flags_changed`.
- **NPC memory** (`World.npcs`): one entry per placed NPC, keyed by `Channels.id` (area and node
  path): `plays` per interaction key, `gone`, and `pos` / `facing` once it has moved. An NPC
  writes its position on every arrival and at the end of an interaction that walked it, and goes
  back there when its area loads. One that never walked keeps its editor placement.
- **Saving** the game means saving `World.time`, `channels`, `signals`, `flags` and `npcs`:
  plain data. `World.reset_story()` forgets flags and memory (the demo's key 7).
- **Renaming or moving an NPC node** changes its memory key: what it remembered is lost. Give
  interactions ids before shipping a save format; an empty id falls back to the interaction's
  position in the list (`#2`), which changes when the list is reordered.

## The player side

The player keeps every `Interactable` zone it stands in and answers the nearest one whose
`can_interact()` is true. An NPC's talk zone says yes only while the NPC is present, has a key
interaction available and isn't holding the player, and only that zone shows the **E** prompt.
NPCs standing close together don't fight over the press.

A locked talk puts the player in its `puppet` state: no input, no damage. If the NPC is freed or
unloaded mid-talk, it releases the player and clears the fade.

## Hooking up presentation

Gameplay never waits on presentation. Presentation only reads:

- **`anim: StringName`**: what the body plays. `idle`, `walk`, `run` (walking overrides a step's
  anim and ends back on `idle`), plus whatever `ANIM` steps name. The placeholder knows `talk`,
  `wave`, `nod`, `shake`, `bow`, `jump`, `point`, `shrug`.
- **`face: StringName`**: `neutral`, `happy`, `sad`, `angry`, `surprised`, `thinking`.
- **`look_target: Variant`**: the global point the head turns to, or `null` for straight ahead.
- **`speaking: bool`**: a line is showing.
- **`cue(name)`**: one-shot events: `say` (a line appears), `arrive` (a walk ended), `leave`.
- **`finished`**: an interaction ended.

### Body animation

Replace the placeholder `_animate()` with an `AnimationTree`, as in the enemy guide: clips named
after the `anim` values, a state machine with callback mode **Physics**, a presenter that travels
when `anim` changes. To silence the placeholder, give the NPC type a script that `extends Npc`
and overrides `_animate()` with an empty function (keep `_look()` running if you keep the
placeholder head). Model forward is −Z, feet at `Visual`'s origin (y −0.8), scaled to the
capsule.

### Head look

Godot's `LookAtModifier3D` (4.4+) turns a bone toward a target on top of whatever the skeleton
plays: the mix the placeholder head imitates.

1. Add a `LookAtModifier3D` as a child of the `Skeleton3D`, `bone_name` the head (or neck) bone,
   `forward_axis` the bone's forward, angle limits about 75° sideways and 35° up and down.
2. Give the NPC a plain `Node3D` "LookTarget"; each physics frame the presenter moves it to
   `look_target`, and points the modifier's `target_node` at it.
3. When `look_target` is `null`, ease the modifier's `influence` to 0 (straight ahead); ease it
   back to 1 when there's a target. Its `duration` smooths target switches.

The skeleton has no fingers, so hands are rigid in the clips; attach props (a bell, a sign) with
a `BoneAttachment3D` on the hand bone.

### Face

Keep the premade face animations in a second `AnimationPlayer` (or blend shapes on the head mesh)
named after the `face` values, so the face plays on top of any body clip. The presenter plays
`face` when it changes, blinks on a timer (2-5 s), and flaps the mouth while `speaking`
(a looping mouth clip, or a blend shape driven from the voice's volume).

### Sound and VFX

A presenter child listens and never changes gameplay state:

```gdscript
# npc/npc_presenter.gd: a child of an NPC type scene
extends Node

@export var anim_tree: AnimationTree
@export var face_player: AnimationPlayer
@export var voice_blips: Array[AudioStream] = [] ## one plays on every line

@onready var npc: Npc = get_parent()
var _anim: StringName
var _face: StringName


func _ready() -> void:
	npc.cue.connect(_on_cue)


func _physics_process(_delta: float) -> void:
	if anim_tree and npc.anim != _anim:
		_anim = npc.anim
		(anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback).travel(_anim)
	if face_player and npc.face != _face:
		_face = npc.face
		face_player.play(_face)


func _on_cue(cue_name: StringName) -> void:
	if cue_name == &"say" and voice_blips and not npc.voice.playing:
		npc.voice.stream = voice_blips.pick_random()
		npc.voice.play()
```

Footsteps belong on the walk clip's audio track. `SOUND` steps play through `Voice`, so a voice
line and a blip never overlap on the same NPC.

## Demo

`demo/npcs/npcs.tscn`, five bays (`[` `]` to warp):

1. **Greeter**: a bark when you come close, a once intro (wave, happy), then a repeat line with
   versions. The head follows you within 6 m.
2. **Progression**: Smith waits for the bell; the Ringer rings it (`flag bell_rang`), and Smith's
   higher-listed lines take over.
3. **Performer**: one long talk walking between marks, talking while walking, pointing and
   looking at a mark, faces, sounds; he stays where he ends. **Doorman**: a once talk walks him out
   of a gap in a wall, for good.
4. **Leaver**: Mara says goodbye and leaves behind a fade.
5. **Dock**: Mara's copy, there once she has left.

Key 7 forgets every flag and all NPC memory; key 8 reloads the scene to show what NPCs remember.

## Shortcuts

Known ceilings (marked `ponytail:` in the code where they live):

- `_animate()` is a procedural stand-in for an `AnimationTree` plus face animations.
- No branching dialog, choices or player lines: a later `actor` field on `SAY` could give lines
  to someone else.
- NPCs fall world-down only and don't react to enemies or combat.
- Memory is keyed by node path: renaming an NPC forgets it (see Flags, memory and saving).
