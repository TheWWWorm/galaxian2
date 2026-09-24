extends RefCounted
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const OrdinaryContracts=preload("res://src/content/ordinary_contracts_definitions.gd")
const Kappa=preload("res://src/content/kappa_population_definitions.gd")
const NPCSystems=preload("res://src/content/npc_systems_definitions.gd")
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
const RecoveryRules=preload("res://src/content/tractor_recovery_definitions.gd")
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

func configure(bindings: RefCounted, cursor: Variant, kinds: Variant, difficulty: Variant, rescue_context:=false) -> bool:
	error="";_rules={};_state={}
	if not available(bindings) or not cursor is int or not kinds is Array or (not difficulty is int and not difficulty is float) or not is_finite(float(difficulty)) or float(difficulty)<0.0 or float(difficulty)>10.0:return reject("Reputation requires a verified early Mido encounter")
	var rules: Dictionary=bindings.mido_travel.reputation.duplicate(true)
	if RecoveryRules.available(bindings):
		rules.cargo_recovery=bindings.mido_travel.tractor_recovery.transfer.duplicate(true)
		rules.cargo_recovery.faction_kinds=rules.cargo_recovery.faction_kinds.map(func(kind):return int(kind))
	var expected: Variant=rules.actor_kinds_by_cursor.get(str(cursor))
	var contract: bool=load("res://src/content/convoy_transit_definitions.gd").supports(bindings.mido_travel,cursor) and ContractLife.available(bindings) and ContractLife.supported_kinds(kinds)
	var convoy: bool=cursor==14 and Convoy.available(bindings) and ContractLife.available(bindings) and kinds==[8,8,8,0,0,0,0]
	var alioth: bool=cursor==16 and Alioth.Life.available(bindings) and kinds==bindings.mido_travel.alioth_lifecycle.actor_kinds.map(func(kind):return int(kind))
	var kappa: bool=rescue_context and cursor==21 and Kappa.KappaLife.available(bindings) and kinds==[0,0,0,0]
	var story: bool=cursor==24 and load("res://src/content/sahi_encounter_definitions.gd").coherent(bindings.mido_travel) and kinds==bindings.mido_travel.sahi_encounter.population.actors.map(func(actor):return int(actor.actor_kind))
	if cursor in [25,26,29] and load("res://src/content/post_sahi_definitions.gd").portal_available(bindings.mido_travel,cursor):
		var count: int=bindings.mido_travel.post_sahi["void"].population.count if cursor in [25,29] else bindings.mido_travel.post_sahi.pursuers.count
		story=kinds.size()==count and kinds.all(func(kind):return kind is int and kind==9)
	if cursor==28 and load("res://src/content/thynome_expedition_definitions.gd").available(bindings):
		var authored:=[]
		for group in bindings.mido_travel.thynome_expedition.world28.cast.groups:
			for _index in int(group.count):authored.append(int(group.actor_kind))
		story=kinds==authored
	if rescue_context and not kappa:return reject("Rescue reputation requires its authored cast")
	# The world validates the mission/population pair before supplying this
	# faction ledger. A selected courier supplies an empty list; delivery pirates
	# can extend the ordinary list beyond the no-job population bound.
	var free: bool=not kappa and load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,cursor) and FreeLife.available(bindings) and (not kinds.is_empty() or OrdinaryContracts.available(bindings)) and kinds.size()<=FreeLife.Traffic.Population.maximum_actor_count(bindings,20,float(difficulty))+OrdinaryContracts.maximum_extra_count(bindings) and kinds.all(func(kind):return kind is int and kind in [0,1,2,8])
	if contract or convoy or alioth or free or kappa or story:
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
		if alioth or story:
			rules.system_id=18 if cursor in [28,29] else int(bindings.mido_travel.sahi_encounter.system_id if story else bindings.mido_travel.alioth_lifecycle.system_id)
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
	if NPCSystems.available(bindings) and (story or free or not AmbientCombat.for_context(bindings,cursor).is_empty()):
		rules.systems_changes={}
		for kind in kinds:rules.systems_changes[str(kind)]=NPCSystems.reputation(bindings,kind)
	_rules=rules.duplicate(true)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,
		"system_id":int(rules.system_id),"actor_kinds":kinds.duplicate(),"difficulty":Vitals.single(float(difficulty)),"events":[]}
	if kappa:
		_state.systems_hit_serials=[];_state.systems_hit_serials.resize(kinds.size());_state.systems_hit_serials.fill(0)
	if (free or (cursor in [11,12,13,14] and not contract and not convoy)) and Lifecycle.recycling_parameters(bindings.ambient_lifecycle):
		_state.spawn_generations=[];_state.spawn_generations.resize(kinds.size());_state.spawn_generations.fill(0)
	if kappa:_state.kappa_rescue=true
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
	if _state.events.any(func(event):return event.get("event_kind","") not in ["systems_disabled","cargo_recovered"] and event.actor_id==id and int(event.get("spawn_generation",0))>=generation):return reject("This traffic instance has already received its lethal hit")
	var change:=0 if nonplayer else int(_rules.lethal_changes[str(_state.actor_kinds[id])])
	if _state.difficulty==float(_rules.hardest_difficulty):change*=int(_rules.hardest_multiplier)
	var axis:=int(_rules.get("faction_axes",{}).get(str(_state.actor_kinds[id]),_rules.axis))
	_state.events.append({"actor_id":id,"actor_kind":_state.actor_kinds[id],"nonplayer_kill":nonplayer,"axis":axis,"change":change})
	if _state.has("spawn_generations"):_state.events[-1].spawn_generation=generation
	return true

func record_cargo_recovery(actor: Dictionary) -> bool:
	error=""
	for key in ["base_content_id","binding_id"]:
		if actor.get(key)!=_state.get(key):return reject("Cargo recovery belongs to another faction history")
	var id: Variant=actor.get("actor_id")
	if not Numbers.integer(id,0,_state.get("actor_kinds",[]).size()-1) or actor.get("actor_kind")!=_state.actor_kinds[id] or actor.get("actor_mode") not in [3,4] or actor.get("vitals",{}).get("hull")!=0:return reject("Cargo reputation requires the actual exhausted actor")
	var generation:=0
	if _state.has("spawn_generations"):
		if actor.get("spawn_generation")!=_state.spawn_generations[id]:return reject("Cargo belongs to an earlier traffic instance")
		generation=_state.spawn_generations[id]
	return _append_cargo_event(id,generation)

func _append_cargo_event(id: int,generation: int) -> bool:
	var kind: int=_state.actor_kinds[id]
	if not _rules.has("cargo_recovery") or kind not in _rules.cargo_recovery.faction_kinds:return reject("Unsupported recovered-cargo affiliation")
	if _state.events.any(func(event):return event.get("event_kind")=="cargo_recovered" and event.actor_id==id and int(event.get("spawn_generation",0))>=generation):return reject("This traffic instance has already recorded cargo recovery")
	var change:=int(_rules.cargo_recovery.faction_base_magnitude)*(1 if kind%2 else -1)
	if _state.difficulty==float(_rules.hardest_difficulty):change*=int(_rules.hardest_multiplier)
	_state.events.append({"actor_id":id,"actor_kind":kind,"event_kind":"cargo_recovered","axis":kind/2,"change":change})
	if _state.has("spawn_generations"):_state.events[-1].spawn_generation=generation
	return true

func record_systems_depletion(actor: Dictionary,hit: Dictionary) -> bool:
	error=""
	if not _rules.has("systems_reputation") and not _rules.has("systems_changes"):return reject("This reputation history has no systems damage support")
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if actor.get(key)!=_state[key]:return reject("Systems damage belongs to another reputation history")
	var id: Variant=actor.get("actor_id")
	if not Numbers.integer(id,0,_state.actor_kinds.size()-1) or actor.get("actor_kind")!=_state.actor_kinds[id] or actor.get("vitals",{}).get("hull",0)<=0:return reject("Systems reputation requires the actual living fighter")
	var after: Variant=actor.get("systems")
	if not after is Dictionary or not after.get("disabled",false) or after.get("integrity")!=0 or not hit.get("accepted",false) or hit.get("after")!=after or hit.get("before",{}).get("integrity",0)<=0:return reject("Systems reputation requires an accepted depletion transaction")
	var generation:=0
	if _state.has("spawn_generations"):
		if actor.get("spawn_generation")!=_state.spawn_generations[id]:return reject("Systems depletion belongs to an earlier traffic instance")
		generation=_state.spawn_generations[id]
	return _append_systems_event(id,actor.get("systems_hit_serial"),generation)

func _append_systems_event(id: int,serial: Variant,generation: int=0) -> bool:
	if (not _rules.has("systems_reputation") and not _rules.has("systems_changes")) or not Numbers.integer(serial,1,2147483647):return reject("Systems depletion lacks its supported hit serial")
	var previous: int=_state.systems_hit_serials[id] if _state.has("systems_hit_serials") else 0
	for event in _state.events:
		if event.actor_id!=id:continue
		if event.get("event_kind","")=="systems_disabled":previous=maxi(previous,event.hit_serial)
		elif int(event.get("spawn_generation",0))>=generation:return reject("Systems depletion cannot follow this instance's lethal hit")
	if serial<=previous:return reject("Systems depletion has already been recorded")
	var rule: Dictionary=_rules.systems_changes[str(_state.actor_kinds[id])] if _rules.has("systems_changes") else {"axis":int(_rules.systems_reputation.reputation_axis),"change":int(_rules.systems_reputation.reputation_change)}
	var change:=int(rule.change)
	if _state.difficulty==float(_rules.hardest_difficulty):change*=int(_rules.hardest_multiplier)
	_state.events.append({"actor_id":id,"actor_kind":_state.actor_kinds[id],"event_kind":"systems_disabled","hit_serial":serial,
		"axis":int(rule.axis),"change":change})
	if _state.has("spawn_generations"):_state.events[-1].spawn_generation=generation
	if _state.has("systems_hit_serials"):_state.systems_hit_serials[id]=serial
	return true

func restore(bindings: RefCounted, data: Variant) -> bool:
	error=""
	if not data is Dictionary or not data.get("events") is Array:return reject("Retained reputation hit history is unavailable")
	var next: RefCounted=get_script().new()
	if not next.configure(bindings,data.get("campaign_cursor"),data.get("actor_kinds"),data.get("difficulty"),data.get("kappa_rescue",false)):return reject(next.error)
	if next._state.has("spawn_generations"):
		var generations: Variant=data.get("spawn_generations")
		if not generations is Array or generations.size()!=next._state.actor_kinds.size() or not generations.all(func(value):return Numbers.integer(value,0,2147483647)):return reject("Invalid retained traffic generations")
		next._state.spawn_generations=generations.duplicate()
	for event in data.events:
		if event is Dictionary and event.get("event_kind")=="cargo_recovered":
			if not Numbers.integer(event.get("actor_id"),0,next._state.actor_kinds.size()-1):return reject("Invalid retained cargo-recovery actor")
			var generation:=0
			if next._state.has("spawn_generations"):
				if not Numbers.integer(event.get("spawn_generation"),0,next._state.spawn_generations[event.actor_id]):return reject("Retained cargo has an unregistered traffic generation")
				generation=event.spawn_generation
			if not next._append_cargo_event(event.actor_id,generation):return reject(next.error)
			continue
		if event is Dictionary and event.get("event_kind")=="systems_disabled":
			if not Numbers.integer(event.get("actor_id"),0,next._state.actor_kinds.size()-1):return reject("Invalid retained systems depletion actor")
			var generation:=0
			if next._state.has("spawn_generations"):
				if not Numbers.integer(event.get("spawn_generation"),0,next._state.spawn_generations[event.actor_id]):return reject("Retained systems depletion has an unregistered traffic generation")
				generation=event.spawn_generation
			if not next._append_systems_event(event.actor_id,event.get("hit_serial"),generation):return reject("Invalid retained systems depletion")
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
