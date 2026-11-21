# Switch puzzles

Doors that open when their switches are on. Most switches are **weight plates**, pressed by
anything resting on them: the player, an enemy, an NPC, or a **weight** (a box or a ball). Weights
are pushed by walking into them, and the player can carry, put down and throw them. A
**dispenser** keeps a puzzle supplied with weights. An **energy switch** is charged by the
player's shots: its door opens at once and slides shut as the energy drains. **Gravity zones**
flip enemies, NPCs and weights as well as the player, so plates on walls and ceilings work.

Like platforms, a door's switches can sit in other areas: they meet on a **channel** name, and all
state lives in `World`, so it survives scene changes and is ready to be saved.

Everything visible is a placeholder. See [Hooking up presentation](#hooking-up-presentation).

## The pieces

| File | What |
|------|------|
| `puzzle/weight_plate.gd` | `WeightPlate` (a `Zone`): hold or latch plate |
| `puzzle/energy_switch.gd` | `EnergySwitch`: charged by shots |
| `puzzle/door.gd` | `Door`: slides open while every switch on its channel is on |
| `puzzle/weight_body.gd`, `box.tscn`, `ball.tscn` | `WeightBody`: weights (a `RigidBody3D`) |
| `puzzle/dispenser.gd` | `Dispenser`: keeps weights in play |
| `puzzle/switch_registry.gd`, `world/switch_registry.tres` | every saved scene's switches, by channel (baked) |
| `world/world.gd` | `World.switches` (switch state), `World.bodies` (weight memory), the door maths |
| `demo/switches/` | demo areas (`switches_a`, `switches_b`) |
| `tests/switch_test.gd` | runtime suite |

`Door` and `EnergySwitch` reuse `MovingPlatform` as "a solid body shaped by `ShapeSet`": add
them with Add Node, give them a shape in the inspector's Shapes section (Shape Tools), and set the
`channel`. `WeightPlate` is a `Zone`: its shape is the detection slab over the plate's face.

## Building a puzzle

1. Add a `Door` and give it a shape (a 4 × 3 × 0.4 box is a doorway) and a `channel`, say `gate`.
   `open_offset` is how far it slides when open, in its own axes (default 3 m up); `open_time`
   how long opening takes.
2. Add one or more switches with the same `channel`: `WeightPlate`s (a thin box shape, 2 × 0.3 × 2,
   sitting on the floor) and/or `EnergySwitch`es (a small box shape on a wall).
3. If the puzzle needs weights, add a `Dispenser` where they should come out, with the puzzle's
   `channel` and `count`. Or place `box.tscn` / `ball.tscn` instances by hand.

The door is open while **every** switch on its channel is on.

- **Hold** plates (`mode = HOLD`) are on while something rests on them.
- **Latch** plates (`mode = LATCH`) spring back up until every switch on the channel is on at the
  same moment. Then every latch plate on the channel locks down for good, in loaded areas or not.
- **Energy switches** are on while they have energy. Each shot adds `time_to_close` seconds, up to
  `time_to_close × max_shots`. The door snaps open, then slides shut over the energy left (more
  shots, slower slide). Energy counts toward the all-on moment that locks latch plates.

A channel whose switches are all latch plates, all locked, is **solved**: its doors stay open and
its dispensers stop. A channel with any hold plate or energy switch is never solved, so its
dispensers keep replacing lost weights (the puzzle can't be left without them).

### What presses a plate

The player, an enemy, an NPC or a weight overlapping the plate's slab, whose gravity points into
the plate (within about 45°). One body is enough. A carried weight never counts (its collision is
off). A box shoved sideways against a wall plate doesn't count; a box whose gravity points at the
wall does. A plate's "up" is its basis Y, so a ceiling plate is a plate turned upside down.

### Channels and other areas

Channel names work as for platforms (`world/channels.gd`): a plain name belongs to the area, and
`area:name` reaches another area's channel. The inspector's `channel` field is the same picker as
on tracks and switches.

A door counts the switches of its channel in **every saved scene**, also in areas the player
hasn't visited yet (they count as off), through the switch registry. The Platform Tools plugin
re-bakes `world/switch_registry.tres` whenever a scene is saved or the filesystem changes; commit
it with the scenes. A switch inside an instanced sub-scene isn't found (a `ponytail:` in
`channel_registry.gd`). Scenes built in code count the switches that are loaded.

## Weights

`WeightBody` is a `RigidBody3D` with its own **sticky gravity** (`gravity_dir`, set by gravity
zones like the player's) and a `weight` (its mass):

- **Pushing**: anyone walking into a weight pushes it, at `speed × clamp(strength / weight, 0.05, 1)`.
  The player and NPCs push with `push_strength` (6), enemies with their own `weight`. The pusher
  is held to the weight's speed, so heavy boxes are slow to shove. Standing on a weight doesn't
  push it. Friction and damping rise with weight.
- **Carrying** (player only): R lifts the weight in front (within `carry_reach`, 60° of facing),
  R again puts it down in front (refused when it doesn't fit), T throws it
  (`throw_speed × clamp(10 / weight, 0.3, 1.5)`, forward and up). While carrying: walk speed
  `× 1 / (1 + weight × carry_slow)`, no running, dashing, grabbing, climbing, melee or shooting;
  stamina drains `carry_cost × weight / 10` per second and doesn't regenerate. The player drops
  the weight when hurt, dying, entering deep water, going through a `SceneDoor` (it stays in its
  area) or running out of stamina. A released weight takes the player's gravity.
- **Lost**: a `KillZone` or leaving the area's bounds (`GameArea.bounds_radius`) destroys it.

Enemies' probes see weights as open ground, so a chasing enemy walks into a weight and pushes it.

## Dispensers

A `Dispenser` keeps `count` weights of `weight_scene` in play. They come out at its position one
at a time, each when the spot is clear, named `Weight1`, `Weight2`... A lost one (destroyed, or
freed by any code) is replaced after `respawn_delay`. Once its `channel` is solved it stops for
good; the weights already out stay. An empty `channel` never stops.

## Memory and saving

- `World.switches`: plate `{on, locked}`, energy `{shot_at, end}` (world times), by `Channels.id`.
  A plate in an area that isn't loaded keeps the state it had when the player left, so a box left
  on a hold plate in one area holds a door open in another.
- `World.bodies`: each weight's position, pose and gravity (written by `GameArea` every physics
  frame), `{gone = true}` for a destroyed hand-placed one, `{alive = names}` per dispenser.
  Weights are back where they were left when an area reloads. Keys come from
  `Channels.placement_id`, which keys a scene instanced from code by its path under its parent's
  area.
- A loading plate waits `WeightPlate.WARMUP` physics frames (restored weights settle) before it
  reads what rests on it, and an area unloading never releases its plates.
- Enemies are not remembered: one standing on a hold plate is back home after a reload, and the
  plate reads released.

Saving the game means saving `switches` and `bodies` with the rest of `World`.

## Gravity zones

`GravityZone` sets the gravity of whatever enters, and it stays until another zone changes it: the
player, enemies (`Enemy.set_gravity_dir`), NPCs (`Npc.set_gravity_dir`, remembered with their
position) and weights. Enemies walk and chase on ceilings; climbing, swinging, flying and solved
jumps under flipped gravity are untested (a `ponytail:` in `enemy.gd`). An NPC's walk-timeout snap
only lands on marks of the floor its marks were cached on.

## Hooking up presentation

Every piece emits one-shot `cue(name)` signals for sound and VFX, and exposes state to poll:

| Node | State | Cues |
|------|-------|------|
| `WeightPlate` | `pressed`, `is_on()` | `press`, `release`, `lock` |
| `Door` | `amount` (0 shut .. 1 open), `locked()` | `open`, `close`, `locked` |
| `EnergySwitch` | `fraction()` (energy left) | `charge`, `empty` |
| `WeightBody` | `carrier`, `gravity_dir` | `land` (hard impact), `destroy` |
| `Dispenser` | `weights()` | `spawn` |
| `Player` | `held`; `anim` `carry_idle` / `carry_walk` | `lift`, `put_down`, `throw`, `blocked` |

## Demo

`demo/switches/switches_a.tscn` (bays: Hold, Latch trio, Weight, Energy, Gravity, Lure,
Cross-area) and `switches_b.tscn` (the far latch plate of the cross-area door), linked by
`SceneDoor`s. `[ ]` warps between bays, 7 forgets every switch and weight, 8 reloads the area to
show what it remembers.
