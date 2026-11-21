class_name Channels
extends RefCounted
## Scoped platform channel names. A plain name (`lift`) belongs to its area: the key World
## stores is `area:lift`, the area being the nearest ancestor with an `area_id` (GameArea; empty
## = its scene file's name), else the saved scene's root. A PlatformTrackGroup with
## `channel_scope` on adds its name (`area:bay3/lift`), so a set piece placed twice keeps two
## states. A name with a colon is already a key: `platforms_a:remote` reaches another area,
## `world:...` is for game-wide states. Keys still cross scenes: World holds them all.
## ponytail: a scene instanced from code at runtime counts as its own area (its root has no
## owner); add an area_id lookup by group if spawned set pieces need their parent's scope.


## The key World uses for channel `name` written on `node`.
static func key(node: Node, name: StringName) -> StringName:
	if name == &"" or String(name).contains(":"):
		return name
	return StringName(prefix(node) + name)


## What a plain name gets in front of it at `node`: "area:" plus the scoped groups.
static func prefix(node: Node) -> String:
	var area := area_of(node)
	var groups := ""
	var n := node
	while n and n != area:
		if n is PlatformTrackGroup and n.channel_scope:
			groups = String(n.name) + "/" + groups
		n = n.get_parent()
	return (area_name(area) + ":" if area else "") + groups


## How `node` stores channel `key`: the plain name when the key is in node's own scope.
static func relative(node: Node, key: StringName) -> StringName:
	var p := prefix(node)
	var rest := String(key).trim_prefix(p)
	return StringName(rest) if p != "" and String(key).begins_with(p) and not rest.contains("/") else key


## A key for World's own bookkeeping about `node` (area and path inside it).
static func id(node: Node) -> String:
	var area := area_of(node)
	return area_name(area) + ":" + String(area.get_path_to(node)) if area else String(node.get_path())


## The key for World's memory of a placed thing (an NPC, a weight): id(), except that a scene
## instanced from code has no owner, so area_of would take it for an area of its own (every such
## box would be "box:."): it is keyed by its path under its parent's area instead.
static func placement_id(node: Node) -> String:
	if node.owner != null or node.get_parent() == null:
		return id(node)
	var area := area_of(node.get_parent())
	return area_name(area) + ":" + String(area.get_path_to(node)) if area else String(node.get_path())


static func area_of(node: Node) -> Node:
	var n := node
	while n:
		if "area_id" in n or (n.owner == null and n.scene_file_path != ""):
			return n
		n = n.get_parent()
	return null


static func area_name(area: Node) -> String:
	if area == null:
		return ""
	var named: Variant = area.get("area_id")
	return String(named) if named else area.scene_file_path.get_file().get_basename()
