@tool
class_name Npc
extends CharacterBody3D
## A non-player character the player talks to. It holds an ordered list of NpcInteractions,
## started by the interact key in its Talk zone (KEY) or by the player coming close (NEAR).
## No state machine: it is either idle (the head follows the player when close) or running one
## interaction. Marks (Marker3D children of Marks) are floor points its steps walk to and look at
## (the head looks 1.5 m above a mark: someone standing there).
## Memory lives in World.npcs under this placement's Channels.id: plays per interaction, whether
## it left, and where it stands, so a moved NPC stays moved and a departed one stays gone.
## Presentation is polled like the player's and enemies': `anim`, `face`, `look_target`,
## `speaking`, plus the `cue(name)` signal (docs/npcs.md). Falls world-down only.

signal arrived ## a walk_to ended (reached, or snapped there after the timeout)
signal cue(name: StringName) ## one-shot presentation events: say, arrive, leave
signal finished ## an interaction ended
signal _advanced ## the interact key, during a locked interaction

const ARRIVE := 0.3 ## m from the walk target that counts as there
const FEET := 0.8 ## the NPC's origin above its feet; marks are floor points, so a snap lands this high
const HEAD_YAW := 75.0 ## degrees the head turns either way
const HEAD_PITCH := 35.0
const LEAVE_HOLD := 0.15 ## seconds a leave holds the screen black between its two fades

@export var interactions: Array[NpcInteraction] = []:
	set(v):
		interactions = v
		update_configuration_warnings()
## Story flags that must all be set for the NPC to be here (a character found elsewhere later).
@export var appears_if: PackedStringArray
@export var notice_distance := 6.0 ## the head follows the player within this distance (m)
@export var walk_speed := 2.5
@export var run_speed := 5.0
@export var accel := 20.0
@export var color := Color(0.3, 0.65, 0.45): ## tints the placeholder body
	set(v):
		color = v
		if is_node_ready():
			_mat.albedo_color = v

var anim: StringName = &"idle" ## what the body plays: idle, walk, run, talk, or a step's anim
var face: StringName = &"neutral" ## expression: neutral, happy, sad, angry, surprised, thinking
var look_target: Variant = null ## global point the head turns to, or null (straight ahead)
var speaking := false ## a line is showing (the mouth moves)
var facing := Vector3.FORWARD
var present := true ## false while absent (appears_if unmet, or it left)
var marks := {} ## mark name (StringName) -> global position, cached before the NPC ever moves
var playing: NpcInteraction ## the interaction running, or null
var line := "" ## the line showing in the bubble (without the key mark), or ""

var _run := 0 ## bumped when an interaction starts or is cut: a stale coroutine stops at its next step
var _locked := false ## the running interaction holds the player
var _started_frame := -1 ## physics frame the interaction started on (its key press doesn't advance it)
var _ended_frame := -1 ## physics frame the last one ended on (its closing press doesn't reopen one)
var _look_mode := -1 ## -1: default look; else the NpcStep.Look a step set
var _look_mark: StringName
var _last_line := {} ## NpcStep -> index of the version shown last
var _armed := {} ## NEAR NpcInteraction -> false once fired, until the player is beyond distance + 1 m
var _target: Variant = null ## walk target (global), or null
var _running := false
var _walk_left := 0.0 ## seconds before a walk gives up and snaps to its target
var _player: Player
var _blink := 0.0 ## seconds to the next blink (negative: blinking)

@onready var head: Node3D = $Visual/Head
@onready var talk_zone: NpcTalk = $Talk
@onready var bubble: Label3D = $Bubble
@onready var prompt: Label3D = $Prompt
@onready var voice: AudioStreamPlayer3D = $Voice
@onready var _visual: Node3D = $Visual
@onready var _visual_base := _visual.position
@onready var _mat: StandardMaterial3D = $Visual/Body.material_override
@onready var _eyes: Array[Node3D] = [$Visual/Head/EyeL, $Visual/Head/EyeR]
@onready var _mouth: Node3D = $Visual/Head/Mouth


func _ready() -> void:
	add_to_group(&"npc")
	_mat.albedo_color = color
	if Engine.is_editor_hint():
		return
	_cache_marks()
	var f := -global_basis.z.slide(up_direction)
	if f.length() > 0.01:
		facing = f.normalized()
	# deferred: an NPC added from code gets its owner (so its memory id) after add_child returns
	_start.call_deferred()


func _start() -> void:
	var mem := memory()
	if mem.has("pos"):
		global_position = mem.pos
		facing = mem.facing
		global_basis = Basis.looking_at(facing, up_direction)
		reset_physics_interpolation()
	World.flags_changed.connect(refresh_presence)
	refresh_presence()


## This placement's key in World.npcs: area and path (Channels.id).
func memory_id() -> String:
	return Channels.id(self)


func memory() -> Dictionary:
	return World.npc_memory(memory_id())


func player() -> Player:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Player
	return _player


# --- interactions -------------------------------------------------------------------------

## Memory key of `i`: its id, or its list position when the id is empty.
func key_of(i: NpcInteraction) -> String:
	return String(i.id) if i.id else "#%d" % interactions.find(i)


## The first interaction in list order with this trigger that can play now (null if none).
func choose(trigger: NpcInteraction.Trigger) -> NpcInteraction:
	var plays: Dictionary = memory().plays
	for i in interactions:
		if i and i.trigger == trigger and i.available(World.flags, plays.get(key_of(i), 0)):
			return i
	return null


## Whether the interact key would start something: present, not holding the player, not the
## frame a talk just ended on, and a key interaction is available. NpcTalk asks this.
func can_talk() -> bool:
	return present and not _locked and Engine.get_physics_frames() > _ended_frame \
		and choose(NpcInteraction.Trigger.KEY) != null


## The interact key in the Talk zone: cuts an unlocked interaction (a bark) and plays the first
## available key interaction.
func start_talk() -> void:
	if not can_talk():
		return
	var i := choose(NpcInteraction.Trigger.KEY)
	if playing:
		stop_walk()
	play(i)


## Runs `i` step by step (a coroutine). Steps run back to back until one waits. Starting another
## interaction cuts this one: it stops at its next step.
func play(i: NpcInteraction) -> void:
	_run += 1
	var run := _run
	_hush()
	playing = i
	_started_frame = Engine.get_physics_frames()
	var plays: Dictionary = memory().plays
	plays[key_of(i)] = plays.get(key_of(i), 0) + 1 # counted at the start: a cut `once` doesn't replay
	_locked = i.locks_player
	var p := player()
	if _locked and p:
		p.start_puppet()
		_face(p.global_position)
	for s in i.steps:
		if s == null:
			continue
		await _do(s, run)
		if run != _run:
			return
	_end()


func _do(s: NpcStep, run: int) -> void:
	match s.kind:
		NpcStep.Kind.SAY:
			if s.lines.is_empty():
				push_warning("%s: a say step has no lines" % name)
				return
			var at := s.pick_line(_last_line.get(s, -1))
			_last_line[s] = at
			line = s.lines[at]
			speaking = true
			bubble.text = line + (" ▸" if _locked else "")
			bubble.visible = true
			cue.emit(&"say")
			if _locked:
				await _advanced
			else:
				await _sleep(s.say_time(line))
			if run == _run:
				_hush()
		NpcStep.Kind.ANIM:
			anim = s.anim
			if s.time > 0.0:
				await _sleep(s.time)
		NpcStep.Kind.FACE:
			face = s.face
		NpcStep.Kind.LOOK:
			if s.look == NpcStep.Look.MARK and not marks.has(s.mark):
				push_warning("%s: no mark %s to look at" % [name, s.mark])
				return
			_look_mode = s.look
			_look_mark = s.mark
		NpcStep.Kind.MOVE:
			if not marks.has(s.mark):
				push_warning("%s: no mark %s to walk to" % [name, s.mark])
				return
			walk_to(marks[s.mark], s.run)
			if s.wait:
				await arrived
		NpcStep.Kind.SOUND:
			if s.sound == null:
				push_warning("%s: a sound step has no sound" % name)
				return
			voice.stream = s.sound
			voice.play()
			if s.sound_wait: # its end, or its length (a dummy audio driver may never finish)
				var left := s.sound.get_length()
				while left > 0.0 and voice.playing and run == _run:
					await get_tree().physics_frame
					left -= get_physics_process_delta_time()
		NpcStep.Kind.WAIT:
			if s.time > 0.0:
				await _sleep(s.time)
			elif _locked:
				await _advanced
			else:
				await _sleep(1.0)
		NpcStep.Kind.FLAG:
			if s.flag:
				World.set_flag(s.flag, s.value)
		NpcStep.Kind.LEAVE: # fade out, gone for good (memory), flag set, fade in; the interaction ends
			var p := player()
			if not _locked and p:
				_locked = true # a bark that leaves still holds the player through the fade
				p.start_puppet()
			await World.fade(1.0, s.fade)
			memory().gone = true
			if s.flag:
				World.set_flag(s.flag) # flags_changed: this NPC goes, copies waiting on the flag come
			refresh_presence()
			cue.emit(&"leave")
			await _sleep(LEAVE_HOLD) # rendered at full black: the swap never shows through
			await World.fade(0.0, s.fade)
			_end()
			_run += 1 # steps after a leave never run


## NEAR interactions: the first available one (list order) whose distance holds the player fires
## when it is armed and nothing plays. Firing disarms every NEAR interaction the player is within;
## each re-arms once the player is beyond its distance + 1 m, so standing still never loops a bark.
## Nothing fires while the player is held (talking to someone else).
func _check_near(p: Player) -> void:
	var d := p.global_position.distance_to(global_position)
	var fire: NpcInteraction = null
	for i in interactions:
		if i == null or i.trigger != NpcInteraction.Trigger.NEAR:
			continue
		if d > i.distance + 1.0:
			_armed[i] = true
		elif fire == null and d <= i.distance and _armed.get(i, true) \
				and i.available(World.flags, memory().plays.get(key_of(i), 0)):
			fire = i
	if fire == null or playing != null or p.state_name == &"puppet":
		return
	for i in interactions:
		if i and i.trigger == NpcInteraction.Trigger.NEAR and d <= i.distance:
			_armed[i] = false
	play(fire)


## Back to idle: neutral face, default look, no bubble, position saved, player released.
func _end() -> void:
	anim = &"idle"
	face = &"neutral"
	_look_mode = -1
	_hush()
	save_position()
	var was_locked := _locked
	_locked = false
	playing = null
	_ended_frame = Engine.get_physics_frames()
	if was_locked and is_instance_valid(player()):
		player().end_puppet()
	finished.emit()


func _hush() -> void:
	line = ""
	speaking = false
	bubble.visible = false


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, true).timeout


func _face(point: Vector3) -> void:
	var f := (point - global_position).slide(up_direction)
	if f.length() > 0.01:
		facing = f.normalized()


## Freed or unloaded mid-interaction: never leave the player held (or the screen black).
func _exit_tree() -> void:
	if Engine.is_editor_hint() or playing == null:
		return
	_run += 1
	if _locked and is_instance_valid(player()) and player().is_inside_tree():
		player().end_puppet()
	World.fade(0.0, 0.0)
	_locked = false
	playing = null


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var mark_names := get_node(^"Marks").get_children().map(func(m: Node) -> StringName: return StringName(m.name))
	var ids := {}
	for at in interactions.size():
		var i := interactions[at]
		if i == null:
			continue
		var label := "Interaction %d (%s)" % [at, i.id]
		if i.id == &"":
			out.append("Interaction %d has an empty id: give it one so the NPC remembers it apart." % at)
		elif ids.has(i.id):
			out.append("%s: duplicate id, the two share one memory." % label)
		ids[i.id] = true
		if i.steps.is_empty():
			out.append("%s has no steps." % label)
		var left := false
		for s in i.steps:
			if s == null:
				continue
			if left:
				out.append("%s: steps after leave never run." % label)
				break
			match s.kind:
				NpcStep.Kind.SAY:
					if s.lines.is_empty():
						out.append("%s: a say step has no lines." % label)
				NpcStep.Kind.MOVE, NpcStep.Kind.LOOK:
					if (s.kind == NpcStep.Kind.MOVE or s.look == NpcStep.Look.MARK) and s.mark not in mark_names:
						out.append("%s: mark \"%s\" isn't a child of Marks." % [label, s.mark])
				NpcStep.Kind.LEAVE:
					left = true
	return out


# --- presence ---------------------------------------------------------------------------

## Present when every `appears_if` flag is set and the NPC hasn't left. Absent: hidden, no
## collision, no talk zone, not processing. Runs whenever World's flags change.
func refresh_presence() -> void:
	var on: bool = not memory().gone
	for f: String in appears_if:
		on = on and World.flag(f) > 0
	present = on
	visible = on
	prompt.visible = prompt.visible and on
	$Collision.set_deferred(&"disabled", not on)
	talk_zone.set_deferred(&"monitoring", on)
	if not on:
		stop_walk()
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


# --- walking ------------------------------------------------------------------------------

func _cache_marks() -> void:
	for m in $Marks.get_children():
		if m is Node3D:
			marks[StringName(m.name)] = m.global_position


## Walks (or runs) to `point`. Emits `arrived` within ARRIVE m, or after distance / speed * 2 + 1
## seconds by snapping there, so a blocked walk never strands an interaction.
func walk_to(point: Vector3, running := false) -> void:
	_target = point
	_running = running
	var d := (point - global_position).slide(up_direction).length()
	_walk_left = d / (run_speed if running else walk_speed) * 2.0 + 1.0


func stop_walk() -> void:
	_target = null


func walking() -> bool:
	return _target != null


## Writes where the NPC stands into its memory (restored when the area loads again).
func save_position() -> void:
	var m := memory()
	m.pos = global_position
	m.facing = facing


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _locked and Input.is_action_just_pressed(&"interact") and Engine.get_physics_frames() > _started_frame:
		_advanced.emit()
	var p := player()
	prompt.visible = present and p != null and p.interactable == talk_zone and not _locked
	if p:
		_check_near(p)
	_move(delta)
	_look(delta)
	_orient(delta)
	_animate(delta)


func _move(delta: float) -> void:
	var dir := Vector3.ZERO
	var snap := false
	if _target != null:
		var to: Vector3 = (_target - global_position).slide(up_direction)
		_walk_left -= delta
		if _walk_left <= 0.0:
			snap = true
		elif to.length() > 0.01:
			dir = to.normalized()
			facing = dir
	var speed := run_speed if _running else walk_speed
	var vert := velocity.project(up_direction)
	if not is_on_floor():
		vert += get_gravity() * delta
	velocity = velocity.slide(up_direction).move_toward(dir * speed, accel * delta) + vert
	move_and_slide()
	if snap:
		global_position = (_target as Vector3) + up_direction * FEET
		reset_physics_interpolation()
	if _target != null and (snap or (_target - global_position).slide(up_direction).length() < ARRIVE):
		_target = null
		velocity = velocity.project(up_direction)
		save_position()
		cue.emit(&"arrive")
		arrived.emit()
	if _target != null: # walking overrides a step's anim; it ends back on idle
		anim = &"run" if _running else &"walk"
	elif anim in [&"walk", &"run"]:
		anim = &"idle"


func _orient(delta: float) -> void:
	var f := facing.slide(up_direction)
	if f.length() < 0.01:
		return
	facing = f.normalized()
	global_basis = global_basis.slerp(Basis.looking_at(facing, up_direction), 1.0 - exp(-10.0 * delta)).orthonormalized()


# --- head look and placeholder animation --------------------------------------------------

## What the head follows: a look step's choice during an interaction, else the player's head
## within notice_distance, else straight ahead.
func _look_point() -> Variant:
	var p := player()
	match _look_mode:
		NpcStep.Look.PLAYER:
			return p.global_position + p.up_direction * Player.HEAD if p else null
		NpcStep.Look.MARK:
			return marks[_look_mark] + up_direction * 1.5
		NpcStep.Look.AHEAD:
			return null
	if p and p.global_position.distance_to(global_position) <= notice_distance:
		return p.global_position + p.up_direction * Player.HEAD
	return null


## Turns the head toward look_target in the body's frame, clamped, on top of the body's
## animation (Head sits under Visual): the mix a skeleton gets from LookAtModifier3D.
func _look(delta: float) -> void:
	look_target = _look_point()
	var want := Vector2.ZERO # pitch, yaw
	if look_target != null:
		var local: Vector3 = _visual.global_transform.affine_inverse() * (look_target as Vector3) - head.position
		want = Vector2(atan2(local.y, Vector2(local.x, local.z).length()), atan2(-local.x, -local.z))
		want = Vector2(clampf(want.x, -deg_to_rad(HEAD_PITCH), deg_to_rad(HEAD_PITCH)), clampf(want.y, -deg_to_rad(HEAD_YAW), deg_to_rad(HEAD_YAW)))
	var t := Time.get_ticks_msec() * 0.001
	match anim: # head gestures add to the look
		&"nod": want.x += sin(t * 7.0) * 0.3
		&"shake": want.y += sin(t * 9.0) * 0.4
	var k := 1.0 - exp(-8.0 * delta)
	head.rotation.x = lerp_angle(head.rotation.x, want.x, k)
	head.rotation.y = lerp_angle(head.rotation.y, want.y, k)


## Placeholder "animation" on prototype shapes, in the physics tick (interpolation smooths it).
## ponytail: procedural stand-in for an AnimationTree keyed on `anim` plus face animations keyed
## on `face` (docs/npcs.md); the values are what a real rig reads.
func _animate(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var sc := Vector3.ONE
	var off := 0.0
	var tilt := 0.0
	var roll := 0.0
	match anim:
		&"walk": off = absf(sin(t * 9.0)) * 0.05
		&"run": off = absf(sin(t * 13.0)) * 0.08; tilt = -0.2
		&"talk": off = sin(t * 6.0) * 0.015
		&"wave": roll = sin(t * 8.0) * 0.12
		&"bow": tilt = -0.6
		&"jump": off = absf(sin(t * 6.0)) * 0.35; sc = Vector3(0.9, 1.1, 0.9)
		&"point": tilt = -0.15; sc = Vector3(1.05, 1.0, 1.05)
		&"shrug": sc = Vector3(1.12, 0.92, 1.12)
		_: off = sin(t * 2.0) * 0.01 # idle breathing; nod and shake move the head (_look)
	var k := 1.0 - exp(-15.0 * delta)
	_visual.position = _visual_base + Vector3.UP * off
	_visual.scale = _visual.scale.lerp(sc, k)
	_visual.rotation.x = lerpf(_visual.rotation.x, tilt, k)
	_visual.rotation.z = lerpf(_visual.rotation.z, roll, k)

	var eye := Vector3.ONE
	var brow := 0.0
	var mouth := Vector3.ONE
	match face:
		&"happy": eye = Vector3(1.0, 0.5, 1.0); mouth = Vector3(1.4, 0.7, 1.0)
		&"sad": eye = Vector3(1.0, 0.7, 1.0); brow = 0.35; mouth = Vector3(0.8, 0.6, 1.0)
		&"angry": eye = Vector3(1.1, 0.6, 1.0); brow = -0.45; mouth = Vector3(1.0, 0.5, 1.0)
		&"surprised": eye = Vector3(1.3, 1.4, 1.0); mouth = Vector3(0.6, 2.0, 1.0)
		&"thinking": eye = Vector3(1.0, 0.8, 1.0); mouth = Vector3(0.6, 0.6, 1.0)
	_blink -= delta
	if _blink < -0.12:
		_blink = randf_range(2.0, 5.0)
	if _blink < 0.0:
		eye.y *= 0.1
	if speaking:
		mouth.y *= 1.0 + absf(sin(t * 18.0)) * 1.5
	for i in 2:
		_eyes[i].scale = _eyes[i].scale.lerp(eye, k)
		_eyes[i].rotation.z = lerpf(_eyes[i].rotation.z, brow * (1.0 if i == 0 else -1.0), k)
	_mouth.scale = _mouth.scale.lerp(mouth, k)
