extends RefCounted
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const OrdinaryContracts=preload("res://src/content/ordinary_contracts_definitions.gd")
const Kappa=preload("res://src/content/kappa_population_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
## Actual lethal-hit history for the supported early Mido encounters. Death
## animation/accounting may restart; that does not repeat the lethal hit.
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const AmbientCombat=preload("res://src/content/ambient_combat_definitions.gd")
const Ambient=preload("res://src/content/ambient_population_definitions.gd")
const Lifecycle=preload("res://src/content/ambient_lifecycle_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
var error:=""
var _rules:={}
var _state:={}

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and Travel.parameters(bindings.mido_travel)

static func initial(bindings: RefCounted) -> Dictionary:
	if not available(bindings):return {}
	return {"axes":bindings.mido_travel.reputation.initial_axes.map(func(value):return int(value)),"override":int(bindings.mido_travel.reputation.override)}

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=2 or not data.get("override") is int or data.override!=-1:return false
	var axes: Variant=data.get("axes")
	return axes is Array and axes.size()==2 and axes.all(func(value):return value is int and value>=-100 and value<=100)

func configure(bindings: RefCounted, cursor: Variant, kinds: Variant, difficulty: Variant) -> bool:
	error="";_rules={};_state={}
	if not available(bindings) or not cursor is int or not kinds is Array or (not difficulty is int and not difficulty is float) or not is_finite(float(difficulty)) or float(difficulty)<0.0 or float(difficulty)>10.0:return reject("Reputation requires a verified early Mido encounter")
	var rules: Dictionary=bindings.mido_travel.reputation.duplicate(true)
	var expected: Variant=rules.actor_kinds_by_cursor.get(str(cursor))
	var contract: bool=load("res://src/content/convoy_transit_definitions.gd").supports(bindings.mido_travel,cursor) and ContractLife.available(bindings) and ContractLife.supported_kinds(kinds)
	var convoy: bool=cursor==14 and Convoy.available(bindings) and ContractLife.available(bindings) and kinds==[8,8,8,0,0,0,0]
	var alioth: bool=cursor==16 and Alioth.Life.available(bindings) and kinds==bindings.mido_travel.alioth_lifecycle.actor_kinds.map(func(kind):return int(kind))
	var kappa: bool=cursor==21 and Kappa.KappaLife.available(bindings) and kinds==[0,0,0,0]
	# The world validates the mission/population pair before supplying this
	# faction ledger. A selected courier supplies an empty list; delivery pirates
	# can extend the ordinary list beyond the no-job population bound.
	var free: bool=load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,cursor) and FreeLife.available(bindings) and (not kinds.is_empty() or OrdinaryContracts.available(bindings)) and kinds.size()<=FreeLife.Traffic.Population.maximum_actor_count(bindings,20,float(difficulty))+OrdinaryContracts.maximum_extra_count(bindings) and kinds.all(func(kind):return kind is int and kind in [0,1,2,8])
	if contract or convoy or alioth or free or kappa:
		if float(difficulty) not in [0.5,1.0]:return reject("Reputation requires the supported contract ship population")
		expected=kinds.duplicate()
		var contracts: Dictionary=bindings.early_contracts.ship_lifecycle.reputation
		rules.lethal_changes={};rules.faction_axes={}
		for index in contracts.factions.size():
			var kind:=str(int(contracts.factions[index]))
			rules.lethal_changes[kind]=int(contracts.lethal_changes[index]);rules.faction_axes[kind]=int(contracts.axes[index])
		if kappa:
			rules.system_id=int(bindings.mido_travel.kappa_lifecycle.system_id)
			rules.systems_reputation=bindings.mido_travel.kappa_lifecycle.systems.duplicate(true)
		if free:rules.system_id=int(bindings.mido_travel.free_lifecycle.system_id)
		if alioth:
			rules.system_id=int(bindings.mido_travel.alioth_lifecycle.system_id)
			rules.lethal_changes["9"]=int(bindings.mido_travel.alioth_lifecycle.void_reputation_change)
			rules.faction_axes["9"]=0
	elif cursor==10:
		if kinds.size() not in [0,1,4]:return reject("Reputation requires the generated Mido population")
		expected=[];expected.resize(kinds.size());expected.fill(3)
	elif not AmbientCombat.for_context(bindings,cursor).is_empty():
		if (kinds.is_empty() and bindings.mido_travel.get("continuation",{}).is_empty()) or kinds.size()>Ambient.maximum_actor_count(bindings.ambient_population,bindings.mido_travel.departure_traffic) or not bindings.ambient_population.supported_difficulties.any(func(value):return float(value)==float(difficulty)):return reject("Reputation requires the supported mixed Mido population")
		expected=[];expected.resize(kinds.size());expected.fill(int(bindings.ambient_combat.actor_kind))
	if not expected is Array or kinds.size()!=expected.size():return reject("Reputation has an unsupported encounter population")
	for id in kinds.size():
		if not kinds[id] is int or kinds[id]!=int(expected[id]):return reject("Reputation actor affiliation changed")
	_rules=rules.duplicate(true)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,
		"system_id":int(rules.system_id),"actor_kinds":kinds.duplicate(),"difficulty":Vitals.single(float(difficulty)),"events":[]}
	if kappa:
		_state.systems_hit_serials=[];_state.systems_hit_serials.resize(kinds.size());_state.systems_hit_serials.fill(0)
	if (free or (cursor in [11,12,13,14] and not contract and not convoy)) and Lifecycle.recycling_parameters(bindings.ambient_lifecycle):
		_state.spawn_generations=[];_state.spawn_generations.resize(kinds.size());_state.spawn_generations.fill(0)
	return true

func register_relaunch(actor: Dictionary) -> bool:
	error=""
	if not _state.has("spawn_generations"):return reject("This reputation history does not support recycled traffic")
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if actor.get(key)!=_state[key]:return reject("Relaunched traffic belongs to another reputation history")
	var id: Variant=actor.get("actor_id")
	if not Numbers.integer(id,0,_state.actor_kinds.size()-1) or actor.get("actor_kind")!=_state.actor_kinds[id] or actor.get("subtype")!=0 or actor.get("population_group") not in ["patrol","travel"]:return reject("Unsupported recycled reputation actor")
	if actor.get("spawn_generation")!=_state.spawn_generations[id]+1 or actor.get("active")!=true or actor.get("actor_mode")!=1 or actor.get("vitals",{}).get("hull",0)<=0:return reject("Reputation requires the next restored traffic instance")
	_state.spawn_generations[id]+=1
	return true

func record_lethal(actor: Dictionary) -> bool:
	error=""
	if _state.is_empty():return reject("Configure reputation before recording a lethal hit")
	for key in ["base_content_id","binding_id"]:
		if actor.get(key)!=_state[key]:return reject("Reputation hit belongs to another content identity")
	if _rules.has("systems_reputation") and actor.get("campaign_cursor")!=_state.campaign_cursor:return reject("Kappa lethal hit belongs to another encounter")
	var id: Variant=actor.get("actor_id")
	if not Numbers.integer(id,0,_state.actor_kinds.size()-1) or actor.get("actor_kind")!=_state.actor_kinds[id] or actor.get("vitals",{}).get("hull")!=0 or not actor.get("nonplayer_kill") is bool:return reject("Reputation requires the actual exhausted actor and hit attribution")
	var generation:=0
	if _state.has("spawn_generations"):
		if actor.get("campaign_cursor")!=_state.campaign_cursor or actor.get("spawn_generation")!=_state.spawn_generations[id]:return reject("Lethal hit belongs to an earlier traffic instance")
		generation=_state.spawn_generations[id]
	return _append_event(id,actor.nonplayer_kill,generation)

func _append_event(id: int, nonplayer: bool, generation: int=0) -> bool:
	if _state.events.any(func(event):return event.get("event_kind","")!="systems_disabled" and event.actor_id==id and int(event.get("spawn_generation",0))>=generation):return reject("This traffic instance has already received its lethal hit")
	var change:=0 if nonplayer else int(_rules.lethal_changes[str(_state.actor_kinds[id])])
	if _state.difficulty==float(_rules.hardest_difficulty):change*=int(_rules.hardest_multiplier)
	var axis:=int(_rules.get("faction_axes",{}).get(str(_state.actor_kinds[id]),_rules.axis))
	_state.events.append({"actor_id":id,"actor_kind":_state.actor_kinds[id],"nonplayer_kill":nonplayer,"axis":axis,"change":change})
	if _state.has("spawn_generations"):_state.events[-1].spawn_generation=generation
	return true

func record_systems_depletion(actor: Dictionary,hit: Dictionary) -> bool:
	error=""
	if not _rules.has("systems_reputation"):return reject("This reputation history has no systems damage support")
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if actor.get(key)!=_state[key]:return reject("Systems damage belongs to another reputation history")
	var id: Variant=actor.get("actor_id")
	if not Numbers.integer(id,0,_state.actor_kinds.size()-1) or actor.get("actor_kind")!=_state.actor_kinds[id] or actor.get("vitals",{}).get("hull",0)<=0:return reject("Systems reputation requires the actual living fighter")
	var after: Variant=actor.get("systems")
	if not after is Dictionary or not after.get("disabled",false) or after.get("integrity")!=0 or not hit.get("accepted",false) or hit.get("after")!=after or hit.get("before",{}).get("integrity",0)<=0:return reject("Systems reputation requires an accepted depletion transaction")
	return _append_systems_event(id,actor.get("systems_hit_serial"))

func _append_systems_event(id: int,serial: Variant) -> bool:
	if not _rules.has("systems_reputation") or not Numbers.integer(serial,1,2147483647) or serial<=_state.systems_hit_serials[id]:return reject("Systems depletion has already been recorded or lacks its hit serial")
	if _state.events.any(func(event):return event.actor_id==id and event.get("event_kind","")!="systems_disabled"):return reject("Systems depletion cannot follow this fighter's lethal hit")
	var change:=int(_rules.systems_reputation.reputation_change)
	if _state.difficulty==float(_rules.hardest_difficulty):change*=int(_rules.hardest_multiplier)
	_state.events.append({"actor_id":id,"actor_kind":_state.actor_kinds[id],"event_kind":"systems_disabled","hit_serial":serial,
		"axis":int(_rules.systems_reputation.reputation_axis),"change":change})
	_state.systems_hit_serials[id]=serial
	return true

func restore(bindings: RefCounted, data: Variant) -> bool:
	error=""
	if not data is Dictionary or not data.get("events") is Array:return reject("Retained reputation hit history is unavailable")
	var next: RefCounted=get_script().new()
	if not next.configure(bindings,data.get("campaign_cursor"),data.get("actor_kinds"),data.get("difficulty")):return reject(next.error)
	if next._state.has("spawn_generations"):
		var generations: Variant=data.get("spawn_generations")
		if not generations is Array or generations.size()!=next._state.actor_kinds.size() or not generations.all(func(value):return Numbers.integer(value,0,2147483647)):return reject("Invalid retained traffic generations")
		next._state.spawn_generations=generations.duplicate()
	for event in data.events:
		if event is Dictionary and event.get("event_kind")=="systems_disabled":
			if not Numbers.integer(event.get("actor_id"),0,next._state.actor_kinds.size()-1) or not next._append_systems_event(event.actor_id,event.get("hit_serial")):return reject("Invalid retained systems depletion")
			continue
		if not event is Dictionary or not Numbers.integer(event.get("actor_id"),0,next._state.actor_kinds.size()-1) or not event.get("nonplayer_kill") is bool:return reject("Invalid retained reputation hit")
		var generation:=0
		if next._state.has("spawn_generations"):
			if not Numbers.integer(event.get("spawn_generation"),0,next._state.spawn_generations[event.actor_id]):return reject("Retained lethal hit has an unregistered traffic generation")
			generation=event.spawn_generation
		if not next._append_event(event.actor_id,event.nonplayer_kill,generation):return reject(next.error)
	if data!=next.snapshot():return reject("Retained reputation history disagrees with its source encounter")
	_rules=next._rules;_state=next._state
	return true

func apply_to(prior: Dictionary,first_event: int=0) -> Dictionary:
	error=""
	if _state.is_empty() or not valid_state(prior):reject("Reputation requires its actual retained career state");return {}
	if first_event<0 or first_event>_state.events.size():reject("Reputation checkpoint is outside the retained history");return {}
	var result:=prior.duplicate(true)
	for event in _state.events.slice(first_event):
		result.axes[event.axis]=clampi(result.axes[event.axis]+event.change,int(_rules.minimum),int(_rules.maximum))
	return result

func snapshot() -> Dictionary:return _state.duplicate(true)
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new();copy._rules=_rules;copy._state=_state.duplicate(true);return copy
func reject(message: String) -> bool:error=message;return false
