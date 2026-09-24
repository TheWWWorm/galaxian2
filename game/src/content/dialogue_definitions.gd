extends RefCounted
## Source-bound timed radio declarations. Modal instructions have another owner.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Training = preload("res://src/content/combat_training_story_definitions.gd")
const Convoy = preload("res://src/content/convoy_capture_definitions.gd")
const Alioth = preload("res://src/content/alioth_attack_definitions.gd")
const Kappa = preload("res://src/content/kappa_rescue_definitions.gd")
const Sahi = preload("res://src/content/sahi_encounter_definitions.gd")
const Post = preload("res://src/content/post_sahi_definitions.gd")
const Thynome = preload("res://src/content/thynome_expedition_definitions.gd")
const VoidProbe = preload("res://src/content/void_probe_definitions.gd")
const Voice = preload("res://src/content/radio_audio_definitions.gd")
const Equal = preload("res://src/content/opening_escape_definitions.gd")

static func select(bindings: RefCounted, campaign_cursor: int = 0) -> Dictionary:
	match campaign_cursor:
		0: return bindings.opening_dialogue
		1: return bindings.arrival_dialogue
		7: return Training.radio(bindings)
		14: return Convoy.radio(bindings)
		16: return Alioth.radio(bindings)
		21: return Kappa.radio(bindings)
		25:
			if not Post.available(bindings):return {}
			return _timed_radio(bindings,25,_source_events(bindings.mido_travel.post_sahi["void"].radio))
		24:
			if not Sahi.coherent(bindings.mido_travel):return {}
			var data: Dictionary=bindings.mido_travel.sahi_encounter
			return _timed_radio(bindings,24,data.radio_events.duplicate(true))
		28:
			if not Thynome.coherent(bindings.mido_travel) or not Sahi.coherent(bindings.mido_travel):return {}
			return _timed_radio(bindings,28,_source_events(bindings.mido_travel.thynome_expedition.world28.radio_events))
		29:
			if not VoidProbe.parameters(bindings.mido_travel.get("void_probe",{})) or not Post.available(bindings) or not Sahi.coherent(bindings.mido_travel):return {}
			return _timed_radio(bindings,29,_source_events(bindings.mido_travel.void_probe.world29.radio_events))
	return {}

static func _timed_radio(bindings: RefCounted,cursor: int,events: Array) -> Dictionary:
	if not Voice.parameters(bindings.opening_dialogue.get("voice")):return {}
	var voice: Dictionary=bindings.opening_dialogue.voice.duplicate(true)
	voice.event_ids=events.map(func(row):return int(row.voice_event_id))
	voice.text_ids=events.map(func(row):return int(row.text_id))
	return {"campaign_cursor":cursor,"events":events,"timing":bindings.mido_travel.sahi_encounter.radio_timing.duplicate(true),"voice":voice}

static func _source_events(source: Array) -> Array:
	var events:=[]
	for row in source:
		events.append({"speaker_id":int(row.speaker_id),"text_id":int(row.text_id),"voice_event_id":int(row.voice_event_id),"condition":int(row.condition_kind),"values":[int(row.condition_value)]})
	return events

static func valid_parameters(data: Dictionary, campaign_cursor: int = 0) -> bool:
	if campaign_cursor==25:
		return Numbers.integer(data.get("campaign_cursor"),25,25) and Equal.equal_value(data.get("events"),_source_events(Post.VALUES["void"].radio)) and Equal.equal_value(data.get("timing"),Sahi.VALUES.radio_timing)
	if campaign_cursor==24:
		return Numbers.integer(data.get("campaign_cursor"),24,24) and (Equal.equal_value(data.get("events"),Sahi.VALUES.radio_events) or Equal.equal_value(data.get("events"),Sahi.MAC_VALUES.radio_events)) and Equal.equal_value(data.get("timing"),Sahi.VALUES.radio_timing)
	if campaign_cursor==28:
		return Numbers.integer(data.get("campaign_cursor"),28,28) and (Equal.equal_value(data.get("events"),_source_events(Thynome.VALUES.world28.radio_events)) or Equal.equal_value(data.get("events"),_source_events(Thynome.MAC_VALUES.world28.radio_events))) and Equal.equal_value(data.get("timing"),Sahi.VALUES.radio_timing)
	if campaign_cursor==29:
		return Numbers.integer(data.get("campaign_cursor"),29,29) and (Equal.equal_value(data.get("events"),_source_events(VoidProbe.VALUES.world29.radio_events)) or Equal.equal_value(data.get("events"),_source_events(VoidProbe.MAC_VALUES.world29.radio_events))) and Equal.equal_value(data.get("timing"),Sahi.VALUES.radio_timing)
	if campaign_cursor==21:
		return Numbers.integer(data.get("campaign_cursor"),21,21) and (Equal.equal_value(data.get("events"),Kappa.VALUES.radio_events) or Equal.equal_value(data.get("events"),Kappa.MAC_VALUES.radio_events)) and Equal.equal_value(data.get("timing"),Kappa.VALUES.radio_timing)
	if campaign_cursor==16:
		return Numbers.integer(data.get("campaign_cursor"),16,16) and (Equal.equal_value(data.get("events"),Alioth.VALUES.radio_events) or Equal.equal_value(data.get("events"),Alioth.MAC_VALUES.radio_events)) and Equal.equal_value(data.get("timing"),Alioth.VALUES.radio_timing)
	if campaign_cursor==14:
		return Numbers.integer(data.get("campaign_cursor"),14,14) and (Equal.equal_value(data.get("events"),Convoy.VALUES.radio_events) or Equal.equal_value(data.get("events"),Convoy.MAC_VALUES.radio_events)) and Equal.equal_value(data.get("timing"),Convoy.VALUES.radio_timing)
	if campaign_cursor==7:
		var events: Variant=data.get("events")
		return Numbers.integer(data.get("campaign_cursor"),7,7) and (Equal.equal_value(events,Training.VALUES.radio_events) or Equal.equal_value(events,Training.MAC_VALUES.radio_events)) and Equal.equal_value(data.get("timing"),Training.VALUES.radio_timing)
	if campaign_cursor not in [0, 1] or not Numbers.integer(data.get("campaign_cursor"), campaign_cursor, campaign_cursor): return false
	var rows: Variant = data.get("events")
	var timing: Variant = data.get("timing")
	if not rows is Array or rows.size() != (23 if campaign_cursor == 0 else 3) or not timing is Dictionary: return false
	if timing.get("display_delay_ms") != 2000 or timing.get("base_duration_ms") != 1500 or timing.get("per_line_ms") != 2000: return false
	for i in rows.size():
		var row: Variant = rows[i]
		if not row is Dictionary or not Numbers.integer(row.get("text_id"), 0, 65535) or not Numbers.integer(row.get("speaker_id"), 0, 65535): return false
		if not Numbers.integer(row.get("condition"), 0, 31) or int(row.condition) not in [5, 6, 9, 27] or not row.get("values") is Array: return false
		if row.values.is_empty() or row.values.size() > 256 or (row.condition != 9 and row.values.size() != 1): return false
		for value in row.values:
			if not Numbers.integer(value, 0, 2147483647): return false
			if row.condition == 6 and (value >= rows.size() or value == i): return false
		if campaign_cursor == 1 and (row.condition != (5 if i == 0 else 6) or (i > 0 and int(row.values[0]) != i - 1)): return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String, campaign_cursor: int = 0, opening: Dictionary = {}) -> String:
	if not data is Dictionary: return "Missing opening radio declarations"
	if data.is_empty(): return ""
	if not valid_parameters(data, campaign_cursor): return "Unsupported scene radio declarations"
	var sizes := {}
	if architecture == "x86_64":
		sizes = {"single_constructor": 91, "range_wrapper": 10, "range_constructor": 143, "dispatch": 44, "dispatch_table": 648, "duration": 32, "display_delay": 26}
	elif architecture == "armv7":
		sizes = {"single_constructor": 50, "range_wrapper": 30, "range_constructor": 104, "dispatch": 10, "dispatch_table": 324, "duration": 32, "display_delay": 44}
	if campaign_cursor == 1:
		sizes.erase("range_wrapper"); sizes.erase("range_constructor")
		if architecture == "armv7": sizes.shared_store = 14
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size() != sizes.size() + 1: return "Missing radio provenance"
	var declaration: Variant = provenance.get("declaration")
	if not declaration is Dictionary or not Numbers.integer(declaration.get("bytes"), 1000 if campaign_cursor == 0 else 150, 2048 if campaign_cursor == 0 else 384): return "Invalid radio declaration extent"
	sizes.declaration = int(declaration.bytes)
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not row is Dictionary or row.get("bytes") != sizes[key] or not Numbers.integer(row.get("offset"), 0, executable_bytes - sizes[key]): return "Invalid radio source extent"
	if campaign_cursor == 1:
		for key in ["dispatch", "dispatch_table", "single_constructor", "duration", "display_delay"]:
			if provenance[key] != opening.get("provenance", {}).get(key): return "Rescue radio belongs to another declaration owner"
		if architecture == "armv7":
			var shared: Dictionary = provenance.shared_store
			if shared.offset < declaration.offset + declaration.bytes and declaration.offset < shared.offset + shared.bytes: return "Overlapping rescue radio declarations"
	return ""
