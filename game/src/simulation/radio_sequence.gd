extends RefCounted
## Independent single-speaker radio scheduler. Simulation time is supplied by the
## mission owner, which also owns pause policy, actor hulls and cinematic phase.
## Source-layout line counts must be supplied explicitly; desktop UI wrapping
## must not shorten or lengthen source timing. No mission/reward is completed here.
const Definitions = preload("res://src/content/dialogue_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
var error := ""
var _definition := {}
var _lines: Array = []
var _text: Array = []
var _started: Array = []
var _finished: Array = []
var _active := -1
var _visible := false
var _activated_at := 0
var _last_time := -1
var _identity := {}

func clear() -> void:
	error = ""
	_definition = {}
	_lines = []
	_text = []
	_started = []
	_finished = []
	_active = -1
	_visible = false
	_activated_at = 0
	_last_time = -1
	_identity = {}

func configure(bindings: RefCounted, library: RefCounted, source_line_counts: Array, campaign_cursor: int = 0) -> bool:
	clear()
	var content_id: String = library.manifest.get("content_id", "")
	if not Library.valid_hash(content_id) or content_id != bindings.base_content_id or not Library.valid_hash(bindings.binding_id): return fail("Radio belongs to another or unavailable content identity")
	var data: Dictionary = Definitions.select(bindings, campaign_cursor)
	if not Definitions.valid_parameters(data, campaign_cursor) or source_line_counts.size() != data.events.size(): return fail("Scene radio or source text layout is unavailable")
	if library.active_language.is_empty(): return fail("Select a verified content language before starting radio")
	for i in data.events.size():
		var text_id := int(data.events[i].text_id)
		if text_id >= library.strings.size() or not library.strings[text_id] is String: return fail("Radio text is outside the selected language")
		if not Numbers.integer(source_line_counts[i], 1, 65535): return fail("Missing verified source line count")
	_definition = data.duplicate(true)
	_lines = source_line_counts.duplicate()
	_text = library.strings.duplicate()
	_started.resize(data.events.size())
	_started.fill(false)
	_finished = _started.duplicate()
	_identity = {"base_content_id": content_id, "binding_id": bindings.binding_id, "language": library.active_language}
	if campaign_cursor != 0: _identity.campaign_cursor = campaign_cursor
	return true

func configure_from_layout(bindings: RefCounted, library: RefCounted, layout: RefCounted, campaign_cursor: int = 0) -> bool:
	clear()
	if layout.content_id != library.manifest.get("content_id", "") or layout.language != library.active_language or (not layout.binding_id.is_empty() and layout.binding_id != bindings.binding_id):
		return fail("Radio layout belongs to another content or language")
	var data: Dictionary = Definitions.select(bindings, campaign_cursor)
	if not Definitions.valid_parameters(data, campaign_cursor): return fail("Scene radio is unavailable")
	var counts := []
	for row in data.events:
		var text_id := int(row.text_id)
		if text_id >= library.strings.size() or not library.strings[text_id] is String: return fail("Radio text is outside the selected language")
		var lines: PackedStringArray = layout.wrap(library.strings[text_id])
		if not layout.error.is_empty(): return fail(layout.error)
		counts.append(lines.size())
	return configure(bindings, library, counts, campaign_cursor)

func step(elapsed_ms: int, actor_hulls: Dictionary, cinematic_phase: int) -> Array:
	if _identity.get("campaign_cursor")==7:
		fail("Training radio requires its typed actor activity context")
		return []
	return _step(elapsed_ms,actor_hulls,cinematic_phase,false)

func step_combat_training(elapsed_ms: int, combat: RefCounted) -> Array:
	error=""
	if _identity.get("campaign_cursor")!=7 or not combat is Combat:
		fail("Training radio requires its typed actor activity context")
		return []
	var state: Dictionary=combat.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if state.get(key)!=_identity[key]:
			fail("Training radio belongs to another encounter")
			return []
	if not state.get("actors") is Array or state.actors.size()!=4:
		fail("Training radio requires the complete source actor list")
		return []
	var hostile_active:=false
	for id in 4:
		var actor: Dictionary=state.actors[id]
		if actor.get("actor_id")!=id or not actor.get("active") is bool or not actor.get("friendly") is bool:
			fail("Training radio lacks source actor activity or allegiance")
			return []
		# Scenery is absent from this typed NPC group. Hull and explosion mode
		# do not participate in source radio condition16.
		hostile_active=hostile_active or (actor.active and not actor.friendly)
	return _step(elapsed_ms,{},0,hostile_active)

func _step(elapsed_ms: int, actor_hulls: Dictionary, cinematic_phase: int, hostile_active: bool) -> Array:
	error = ""
	if _identity.is_empty() or elapsed_ms < 0 or elapsed_ms < _last_time or elapsed_ms > 2147483647:
		fail("Invalid radio context or simulation time")
		return []
	_last_time = elapsed_ms
	var changes := []
	if _active < 0:
		for i in _started.size():
			if not _started[i] and eligible(_definition.events[i], elapsed_ms, actor_hulls, cinematic_phase,hostile_active):
				_active = i
				_started[i] = true
				_activated_at = elapsed_ms
				_visible = false
				changes.append({"kind": "started", "event": i})
				break
		return changes
	var timing: Dictionary = _definition.timing
	var visible_at := _activated_at + int(timing.display_delay_ms)
	if elapsed_ms <= visible_at: return changes
	if not _visible:
		_visible = true
		changes.append({"kind": "display", "event": _active, "text_id": int(_definition.events[_active].text_id)})
	var finish_at := visible_at + int(timing.base_duration_ms) + int(timing.per_line_ms) * int(_lines[_active])
	if elapsed_ms > finish_at:
		_finished[_active] = true
		changes.append({"kind": "finished", "event": _active})
		_active = -1
		_visible = false
	return changes

func eligible(row: Dictionary, elapsed_ms: int, hulls: Dictionary, phase: int, hostile_active:=false) -> bool:
	var value := int(row.values[0])
	match int(row.condition):
		5: return elapsed_ms >= value
		6: return _started[value]
		9:
			for actor in row.values:
				var hull: Variant = hulls.get(int(actor))
				if not Numbers.integer(hull, -2147483648, 2147483647) or hull > 0: return false
			return true
		27: return phase == value
		16: return hostile_active
	return false

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate(true)
	result.merge({"started": _started.duplicate(), "finished": _finished.duplicate(), "active_event": _active, "visible": _visible})
	if _active >= 0:
		var row: Dictionary = _definition.events[_active]
		result["text_id"] = int(row.text_id)
		result["speaker_id"] = int(row.speaker_id)
		result["text"] = _text[int(row.text_id)]
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._definition = _definition.duplicate(true)
	copy._lines = _lines.duplicate()
	copy._text = _text.duplicate()
	copy._started = _started.duplicate()
	copy._finished = _finished.duplicate()
	copy._active = _active
	copy._visible = _visible
	copy._activated_at = _activated_at
	copy._last_time = _last_time
	copy._identity = _identity.duplicate(true)
	return copy

func fail(message: String) -> bool:
	error = message
	return false
