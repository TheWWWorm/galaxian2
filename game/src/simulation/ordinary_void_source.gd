extends RefCounted
## Detached ordinary Void warning source. Career navigation owns selection and
## commits the returned source and random state together with its location.
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Navigation=preload("res://src/simulation/contract_navigation.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const VoidAccess=preload("res://src/content/void_access_definitions.gd")
const Library=preload("res://src/content/library.gd")
var error:=""
var _identity:={}
var _source:={}
var _systems:=[]
var _station_count:=0
var _availability:=[]
var _rules:={}

## A newly activated native source has observed no eligible selections. The
## original constructor does not establish a counter value; zero is our explicit
## native initialization, not an imported original-memory value or save fallback.
func configure_fresh(bindings: RefCounted,cat: RefCounted,availability: Variant) -> bool:
	if bindings==null or not VoidAccess.parameters(bindings.mido_travel.get("void_access")):
		return reject("Void source declarations are unavailable")
	var rules: Dictionary=bindings.mido_travel.void_access.source
	return configure(bindings,cat,availability,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"source_system_id":int(rules.initial_system_id),"source_station_id":int(rules.initial_station_id),"eligible_selection_count":0})

## Loaded state always supplies its explicit retained counter.
func configure(bindings: RefCounted,cat: RefCounted,availability: Variant,retained: Variant) -> bool:
	error=""
	if not bindings is Bindings or not cat is Catalogues or not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or cat.content_id!=bindings.base_content_id:
		return reject("Void source requires matching imported content and bindings")
	if not bindings.mido_travel is Dictionary or not VoidAccess.parameters(bindings.mido_travel.get("void_access")):
		return reject("Void source declarations are unavailable")
	if not bindings.early_contracts is Dictionary or not bindings.early_contracts.has("base_navigation") or not Navigation.valid_availability(bindings.early_contracts.base_navigation,availability):
		return reject("Void source requires retained system access")
	var rules: Dictionary=bindings.mido_travel.void_access.source
	var bound: int=int(rules.reroll.system_draw_exclusive_bound)
	var systems: Variant=cat.tables.get("systems")
	var stations: Variant=cat.tables.get("stations")
	if not systems is Array or systems.size()!=int(bindings.early_contracts.base_navigation.system_count) or not stations is Array or stations.size()!=int(bindings.early_contracts.base_navigation.global_station_bound) or bound<1 or bound>systems.size():
		return reject("Void source requires complete station and system catalogues")
	var lists:=[]
	for system_id in systems.size():
		var row: Variant=systems[system_id]
		if not row is Dictionary or row.get("id")!=system_id or (not row.get("station_ids") is Array and not row.get("station_ids") is PackedInt32Array):return reject("Invalid source system membership")
		var members: Array=Array(row.station_ids)
		for station_id in members:
			if not station_id is int or station_id<0 or station_id>=stations.size() or not stations[station_id] is Dictionary or stations[station_id].get("system_id")!=system_id:return reject("Invalid source station membership")
		lists.append(members.duplicate())
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	if not _valid_retained(retained,identity,lists,rules):return reject("Invalid retained Void source or content identity")
	_identity=identity
	_source=retained.duplicate(true)
	_systems=lists
	_station_count=stations.size()
	_availability=availability.duplicate()
	_rules=rules.duplicate(true)
	return true

## Validate a loaded or previously proposed state before replacing the owner copy.
func restore(retained: Variant) -> bool:
	error=""
	if _identity.is_empty() or not _valid_retained(retained,_identity,_systems,_rules):return reject("Invalid retained Void source or content identity")
	_source=retained.duplicate(true)
	return true

## A career location-selection call. The result is prospective: neither this
## component nor the caller's RNG changes. The navigation owner commits both.
## Story selection is admitted only when its target is the chosen station; the
## source's retry on a selected story targeting the old source cannot arise here.
func select(cursor: Variant,chosen_station_id: Variant,story_target_station_id: Variant,selected_story: Variant,random: RefCounted) -> Dictionary:
	error=""
	if _source.is_empty():return fail("Configure the retained Void source first")
	if not cursor is int or cursor<0 or cursor>2147483647 or not chosen_station_id is int or chosen_station_id<0 or chosen_station_id>=_station_count:return fail("Invalid career location selection")
	if not story_target_station_id is int or story_target_station_id < -1 or story_target_station_id>=_station_count or not selected_story is bool:return fail("Invalid selected story context")
	if selected_story and (story_target_station_id<0 or chosen_station_id!=story_target_station_id):return fail("Unsupported selected story and source context")
	if cursor==32 and (story_target_station_id!=10 or selected_story!=(chosen_station_id==10)) or cursor==33 and (story_target_station_id!=10 or selected_story):return fail("Unsupported cursor32/33 story selection")
	if not random is Random or random.snapshot().is_empty():return fail("Void source requires a seeded caller random stream")
	var next_source: Dictionary=_source.duplicate(true)
	var next_random: Dictionary=random.snapshot()
	var event:="unchanged"
	if cursor>=int(_rules.selection_at_or_after_cursor_disables_source):
		next_source.source_system_id=int(_rules.disabled_system_id)
		next_source.source_station_id=int(_rules.disabled_station_id)
		event="disabled"
	elif cursor>=int(_rules.reroll.first_cursor):
		if next_source.source_system_id<0:return fail("The Void source is already disabled")
		if chosen_station_id==story_target_station_id or chosen_station_id==next_source.source_station_id:
			event="skipped"
		else:
			next_source.eligible_selection_count+=1
			event="counted"
			if next_source.eligible_selection_count>=int(_rules.reroll.threshold):
				if not _has_reroll_candidate():return fail("No accessible Void source system")
				var stream: RefCounted=random.fork()
				var system_id: int=-1
				while system_id<0:
					var drawn: int=stream.next_int(int(_rules.reroll.system_draw_exclusive_bound))
					if _candidate(drawn):system_id=drawn
				var members: Array=_systems[system_id]
				var station_index: int=stream.next_int(members.size())
				next_source.source_system_id=system_id
				next_source.source_station_id=members[station_index]
				next_source.eligible_selection_count=int(_rules.reroll.counter_after_reroll)
				next_random=stream.snapshot()
				event="rerolled"
	return {"source":next_source,"random_state":next_random,"event":event}

func _candidate(system_id: int) -> bool:
	return system_id>=0 and system_id<_systems.size() and _availability[system_id] and not _rules.reroll.excluded_system_ids.any(func(id):return int(id)==system_id) and not _systems[system_id].is_empty()

func _has_reroll_candidate() -> bool:
	for system_id in int(_rules.reroll.system_draw_exclusive_bound):
		if _candidate(system_id):return true
	return false

func _valid_retained(value: Variant,identity: Dictionary,systems: Array,rules: Dictionary) -> bool:
	if not value is Dictionary or value.size()!=5 or value.get("base_content_id")!=identity.base_content_id or value.get("binding_id")!=identity.binding_id:return false
	var system: Variant=value.get("source_system_id")
	var station: Variant=value.get("source_station_id")
	var counter: Variant=value.get("eligible_selection_count")
	if not counter is int or counter<0 or counter>=int(rules.reroll.threshold) or not system is int or not station is int:return false
	if system==int(rules.disabled_system_id) and station==int(rules.disabled_station_id):return true
	return system>=0 and system<int(rules.reroll.system_draw_exclusive_bound) and systems[system].has(station)

func snapshot() -> Dictionary:
	return _source.duplicate(true)

func fork() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate()
	copy._source=_source.duplicate(true)
	copy._systems=_systems
	copy._station_count=_station_count
	copy._availability=_availability
	copy._rules=_rules
	return copy

func fail(message: String) -> Dictionary:
	reject(message)
	return {}

func reject(message: String) -> bool:
	error=message
	return false
