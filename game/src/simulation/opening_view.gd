extends RefCounted
## Native opening shot and view owner. The scene supplies current actor/player
## poses and radio flags; it still owns movement, pause, combat and progression.
## Supports the ordinary frame clock, not accelerated or alternate camera modes.
const Director = preload("res://src/simulation/opening_camera.gd")
const Rig = preload("res://src/simulation/camera_rig.gd")
var error := ""
var _director: RefCounted
var _rig: RefCounted

func clear() -> void:
	error = ""
	_director = null
	_rig = null

func configure(bindings: RefCounted) -> bool:
	clear()
	var director := Director.new()
	var rig := Rig.new()
	if not director.configure(bindings): return reject(director.error)
	if not rig.configure(bindings): return reject(rig.error)
	_director = director
	_rig = rig
	return true

func update(delta_ms: Variant, radio: Dictionary, scene: Dictionary) -> bool:
	error = ""
	if _director == null: return reject("Configure opening view before updating")
	var next: RefCounted = _director.fork_for_frame()
	if not next.advance(delta_ms, radio): return reject(next.error)
	# Mission camera changes precede the ordinary view update. A pan can refresh
	# fixed-eye history before the same update changes the target to the player.
	if not _rig.update(delta_ms, next.snapshot(), scene, next.fixed_refresh(), next.view_translation()): return reject(_rig.error)
	_director = next
	return true

func snapshot() -> Dictionary:
	if _director == null: return {}
	return {"shot": _director.snapshot(), "view": _rig.snapshot()}

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	if _director != null:
		copy._director = _director.fork_for_frame()
		copy._rig = _rig.fork_for_frame()
	return copy

func reject(message: String) -> bool:
	error = message
	return false
