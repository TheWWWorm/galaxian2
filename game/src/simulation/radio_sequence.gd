extends RefCounted
## Independent single-speaker radio scheduler. Simulation time is supplied by the
## mission owner, which also owns pause policy, actor hulls and cinematic phase.
## Source-layout line counts must be supplied explicitly; desktop UI wrapping
## must not shorten or lengthen source timing. No mission/reward is completed here.
const Definitions = preload("res://src/content/dialogue_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const Alioth=preload("res://src/content/alioth_attack_definitions.gd")
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
var _waypoint_indices := {}

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
	_waypoint_indices = {}

func configure(bindings: RefCounted, library: RefCounted, source_line_counts: Array, campaign_cursor: int = 0) -> bool:
	clear()
	var content_id: String = library.manifest.get("content_id", "")
	if not Library.valid_hash(content_id) or content_id != bindings.base_content_id or not Library.valid_hash(bindings.binding_id): return fail("Radio belongs to another or unavailable content identity")
	var data: Dictionary = Definitions.select(bindings, campaign_cursor)
	if not Definitions.valid_parameters(data, campaign_cursor) or source_line_counts.size() != data.events.size(): return fail("Scene radio or source text layout is unavailable")
	return _configure_records(bindings,library,data,source_line_counts,campaign_cursor)

func _configure_records(bindings: RefCounted, library: RefCounted, data: Dictionary, source_line_counts: Array, campaign_cursor: int) -> bool:
	var content_id: String=library.manifest.get("content_id", "")
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

func configure_local_message(bindings: RefCounted, library: RefCounted, layout: RefCounted, text_id: int, cursor: int=10) -> bool:
	clear()
	if bindings==null or library==null or layout==null or (Travel.journey(bindings.mido_travel,cursor).is_empty() and not ContractWorld.supports(bindings,cursor) and not (load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,cursor) and FreeFlight.available(bindings))) or not Definitions.valid_parameters(bindings.opening_dialogue,0):return fail("Local radio requires its verified dialogue and clock")
	if library.manifest.get("content_id")!=bindings.base_content_id or layout.content_id!=bindings.base_content_id or layout.binding_id!=bindings.binding_id or layout.language!=library.active_language:return fail("Local radio layout belongs to another content or language")
	var rule: Dictionary=bindings.mido_travel.traffic_combat.radio
	if not rule.warning_text_ids.any(func(value):return int(value)==text_id) and not rule.response_text_ids.any(func(value):return int(value)==text_id):return fail("Local radio text is outside the verified faction messages")
	if text_id>=library.strings.size() or not library.strings[text_id] is String:return fail("Local radio text is unavailable")
	var lines: PackedStringArray=layout.wrap(library.strings[text_id])
	if not layout.error.is_empty():return fail(layout.error)
	var row:={"speaker_id":int(rule.speaker_id),"text_id":text_id,"condition":int(rule.condition),"values":[int(rule.value)]}
	return _configure_records(bindings,library,{"events":[row],"timing":bindings.opening_dialogue.timing.duplicate(true)},[lines.size()],cursor)

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
	if _identity.get("campaign_cursor") in [7,14,16,21]:
		fail("Encounter radio requires its verified target context")
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

func step_convoy(elapsed_ms: int, targets: Dictionary) -> Array:
	error=""
	if _identity.get("campaign_cursor")!=14:
		fail("Convoy radio requires its original dialogue")
		return []
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if targets.get(key)!=_identity[key]:
			fail("Convoy target list belongs to another encounter")
			return []
	var rows: Variant=targets.get("player_targets")
	if not rows is Array or rows.size()>4096:
		fail("Convoy radio requires the player's current target list")
		return []
	var defeated:=0
	for row in rows:
		if not row is Dictionary or not row.get("scenery") is bool:
			fail("Convoy target has no scenery classification")
			return []
		# Source condition20 skips scenery before reading hull. Activity and
		# hostility do not participate, and this is not the lifetime kill count.
		if row.scenery:continue
		if not Numbers.integer(row.get("current_hull"),-2147483648,2147483647):
			fail("Convoy target has no current hull")
			return []
		if row.current_hull<=0:defeated+=1
	return _step(elapsed_ms,{},0,false,defeated)

func step_alioth_attack(elapsed_ms: int, combat: Dictionary) -> Array:
	error=""
	if _identity.get("campaign_cursor")!=16:
		fail("Alioth radio requires its original encounter")
		return []
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if combat.get(key)!=_identity[key]:
			fail("Alioth actors belong to another encounter")
			return []
	var actors: Variant=combat.get("actors")
	var expected: Array=Alioth.VALUES.population.actors
	if not actors is Array or actors.size()!=expected.size():
		fail("Alioth radio requires its complete authored population")
		return []
	var hulls:={}
	for id in actors.size():
		var row: Variant=actors[id]
		if not row is Dictionary:
			fail("Alioth radio lost an authored actor")
			return []
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:
			if row.get(key)!=int(expected[id][key]):
				fail("Alioth radio changed its authored actor membership")
				return []
		if not Numbers.integer(row.get("current_hull"),-2147483648,2147483647):
			fail("Alioth radio requires current actor hulls")
			return []
		hulls[id]=int(row.current_hull)
	# Condition9 observes the three freighter hulls. Visibility, activity,
	# retirement and the player's lifetime kill count are unrelated.
	return _step(elapsed_ms,hulls,0,false)

func step_kappa_rescue(elapsed_ms: int, targets: Dictionary) -> Array:
	error=""
	if _identity.get("campaign_cursor")!=21:
		fail("Kappa radio requires its original rescue declarations")
		return []
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if targets.get(key)!=_identity[key]:
			fail("Kappa targets belong to another encounter")
			return []
	var rows: Variant=targets.get("player_targets")
	var route_index: Variant=targets.get("route_index")
	if not rows is Array or rows.is_empty() or rows.size()>4096 or not Numbers.integer(route_index,-1,2):
		fail("Kappa radio requires the player's current targets and two-waypoint route")
		return []
	var hostile_active:=false
	var survivors:=0
	for row in rows:
		if not row is Dictionary:
			fail("Invalid Kappa radio target")
			return []
		for key in ["scenery","active","friendly","systems_disabled"]:
			if not row.get(key) is bool:
				fail("Kappa radio target lacks its current activity, allegiance or systems state")
				return []
		if not Numbers.integer(row.get("current_hull"),-2147483648,2147483647):
			fail("Kappa radio target lacks its current hull")
			return []
		if row.scenery:continue
		hostile_active=hostile_active or (row.active and not row.friendly)
		if row.current_hull>0:survivors+=1
	# The flight supplies the actual target order and projected NPC stun flag.
	# These predicates do not use lifetime kills or scanner selection.
	return _step(elapsed_ms,{},0,hostile_active,0,{"targets":rows,"route_index":int(route_index),"survivors":survivors})

func _step(elapsed_ms: int, actor_hulls: Dictionary, cinematic_phase: int, hostile_active: bool, defeated_targets:=0, observations: Dictionary={}) -> Array:
	error = ""
	if _identity.is_empty() or elapsed_ms < 0 or elapsed_ms < _last_time or elapsed_ms > 2147483647:
		fail("Invalid radio context or simulation time")
		return []
	_last_time = elapsed_ms
	var changes := []
	if _active < 0:
		for i in _started.size():
			if not _started[i] and eligible(_definition.events[i], elapsed_ms, actor_hulls, cinematic_phase,hostile_active,defeated_targets,observations,i):
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

func eligible(row: Dictionary, elapsed_ms: int, hulls: Dictionary, phase: int, hostile_active:=false, defeated_targets:=0, observations: Dictionary={}, event_index: int=-1) -> bool:
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
		20: return defeated_targets>=value
		8:
			var targets: Array=observations.get("targets",[])
			return value<targets.size() and not targets[value].scenery and targets[value].active
		21:
			var targets: Array=observations.get("targets",[])
			return value<targets.size() and targets[value].systems_disabled
		25:
			var current:=int(observations.get("route_index",-1))
			if current<0 or event_index<0:return false
			var previous:=int(_waypoint_indices.get(event_index,0))
			# An active or earlier eligible event defers this route observation.
			_waypoint_indices[event_index]=current
			return current>previous and previous==0 and int(observations.get("survivors",0))>=value
	return false

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate(true)
	result.merge({"started": _started.duplicate(), "finished": _finished.duplicate(), "active_event": _active, "visible": _visible})
	if _identity.get("campaign_cursor")==21:result.waypoint_observations=_waypoint_indices.duplicate()
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
	copy._waypoint_indices = _waypoint_indices.duplicate()
	return copy

func fail(message: String) -> bool:
	error = message
	return false
