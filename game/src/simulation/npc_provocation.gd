extends RefCounted
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const Kappa=preload("res://src/content/kappa_population_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
## Requested player damage and faction reactions in verified ordinary Mido
## populations. Hull pools, career reputation and radio presentation have owners.
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const AmbientCombat=preload("res://src/content/ambient_combat_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var error:=""
var _rules:={}
var _state:={}

func configure(bindings: RefCounted, catalogues: RefCounted, world: Dictionary, rank: Variant, difficulty: Variant, equipment: RefCounted, reputation: Dictionary) -> bool:
	error="";_rules={};_state={}
	var data:=Travel.population(bindings,world,rank,difficulty)
	return _configure_population(bindings,catalogues,data,equipment,reputation)

func configure_ambient(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,rank: Variant,difficulty: Variant,equipment: RefCounted,reputation: Dictionary) -> bool:
	error="";_rules={};_state={}
	if not construction is Construction:return reject("Ambient reactions require their generated population")
	var packet: Dictionary=construction.snapshot()
	var data:=FreeLife.population(bindings,packet) if packet.has("free_context") else AmbientCombat.population(bindings,packet,rank,difficulty)
	if not _configure_population(bindings,catalogues,data,equipment,reputation):return false
	if data.has("free_lifecycle"):_set_factions(data,int(data.mission_kind))
	return true

func configure_contract(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted) -> bool:
	error="";_rules={};_state={}
	if not construction is Construction:return reject("Contract reactions require their generated accepted population")
	var data:=ContractLife.population(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported contract reaction population")
	if not _configure_population(bindings,catalogues,data,equipment,data.reputation_state):return false
	_set_factions(data,int(data.mission.kind))
	return true

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted,reputation: Dictionary) -> bool:
	error="";_rules={};_state={}
	if not construction is Construction:return reject("Convoy reactions require the generated encounter")
	var data:=Convoy.lifecycle(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported convoy reaction population")
	if not _configure_population(bindings,catalogues,data,equipment,reputation):return false
	_set_factions(data,int(construction.snapshot().convoy_context.mission_kind))
	return true

func configure_alioth_attack(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted,reputation: Dictionary) -> bool:
	error="";_rules={};_state={}
	if not construction is Construction:return reject("Alioth reactions require their generated encounter")
	var data:=Alioth.lifecycle(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported Alioth reaction population")
	if not _configure_population(bindings,catalogues,data,equipment,reputation):return false
	_set_factions(data,int(data.mission_kind))
	return true

func configure_kappa_rescue(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,reputation: Dictionary) -> bool:
	error="";_rules={};_state={}
	if not construction is Construction or catalogues==null or catalogues.content_id!=bindings.base_content_id or not Reputation.valid_state(reputation):return reject("Kappa reactions require their generated population and current standing")
	var packet: Dictionary=construction.snapshot()
	var data:=Kappa.lifecycle(bindings,packet)
	if data.is_empty() or not packet.get("kappa_loadout") is Dictionary:return reject("Kappa reactions require the retained construction loadout")
	var source: Dictionary=data.kappa_lifecycle
	if catalogues.tables.systems[int(data.system_id)].fields[int(source.system_faction_field)]!=int(source.primary_faction):return reject("Kappa system faction disagrees with the original encounter")
	var rules: Dictionary=bindings.mido_travel.traffic_combat
	for id in packet.kappa_loadout.equipment_ids:
		if catalogues.tables.items[id].properties.get(2)==int(rules.credential_subtype):return reject("Faction credentials require an unsupported reaction path")
	if not _initialize_population(bindings,data,rules,reputation):return false
	_set_factions(data,int(data.mission_kind))
	_rules.kappa_lifecycle=source.duplicate(true)
	_state.permanent_hostile=packet.actors.map(func(actor):return actor.script_hostile)
	_state.forced_hostile=_state.permanent_hostile.duplicate()
	_state.systems_requested_damage=[];_state.systems_requested_damage.resize(data.actor_count)
	_state.systems_requested_damage.fill(int(source.systems.initial_requested_damage))
	return true

func apply_kappa_sequence(owner: RefCounted) -> bool:
	error=""
	if not _rules.has("kappa_lifecycle") or not is_instance_of(owner,load("res://src/simulation/kappa_rescue.gd")):return reject("Kappa reactions require their rescue sequence")
	var sequence: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if sequence.get(key)!=_state[key]:return reject("Kappa sequence belongs to another encounter")
	for id in sequence.force_hostile_actor_ids:
		_state.permanent_hostile[id]=true;_state.forced_hostile[id]=true
	return true

func _set_factions(data: Dictionary,mission_kind: int) -> void:
	_rules.contract=data.lifecycle.reactions.duplicate(true)
	_state.actor_kinds=data.actor_kinds.duplicate();_state.active_mission_kind=mission_kind

func _configure_population(bindings: RefCounted,catalogues: RefCounted,data: Dictionary,equipment: RefCounted,reputation: Dictionary) -> bool:
	if data.is_empty() or not equipment is Equipment or catalogues==null or catalogues.content_id!=bindings.base_content_id or not Reputation.valid_state(reputation):return reject("Local combat requires its generated traffic, equipment and retained reputation")
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false):return reject("Local combat precedes the station equipment exchange")
	for key in ["base_content_id","binding_id"]:
		if owned.get("loadout",{}).get(key)!=bindings.get(key):return reject("Local combat equipment belongs to another content identity")
	var rules: Dictionary=bindings.mido_travel.traffic_combat
	if owned.loadout.station_id!=int(data.station_id):return reject("Local combat belongs to another station")
	for id in owned.loadout.equipment_ids:
		if catalogues.tables.items[id].properties.get(2)==int(rules.credential_subtype):return reject("Faction credentials require an unsupported reaction path")
	return _initialize_population(bindings,data,rules,reputation)

func _initialize_population(bindings: RefCounted,data: Dictionary,rules: Dictionary,reputation: Dictionary) -> bool:
	var damage:=[];damage.resize(int(data.actor_count));damage.fill(int(rules.requested_damage_initial))
	var forced:=[];forced.resize(int(data.actor_count));forced.fill(bool(rules.forced_hostile_initial))
	_rules=rules.duplicate(true)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor),
		"station_id":int(data.station_id),"initial_reputation":reputation.duplicate(true),
		"requested_damage":damage,"forced_hostile":forced,"warning_issued":false,"response_issued":false,
		"station_response_flag":bool(rules.station_flag_initial),"radio_serial":0,"pending_radio":{}}
	return true

func evaluate(actor: Dictionary, amount: Variant, nonplayer: Variant, random_state: Dictionary, display_available: bool) -> Dictionary:
	error=""
	if not Vitals.integer(amount) or not nonplayer is bool or not _validate_actor(actor):return fail("Provocation requires a matching actor and valid damage attribution: "+error)
	var id: int=actor.actor_id;var expected_kind: int=actor.actor_kind
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	var next:=fork_for_frame();var events:=[]
	var faction_eligible: bool=not _rules.has("contract") or _rules.contract.eligible_factions.any(func(value):return int(value)==expected_kind)
	if _rules.has("kappa_lifecycle") and actor.script_hostile:faction_eligible=false
	if faction_eligible and actor.active and actor.damage_allowed and actor.vitals.hull>0 and not nonplayer and (not actor.hostile or actor.forced_hostile):
		# Accumulation counts requested damage, including absorbed shield/armor
		# damage. Match signed 32-bit storage before the binary32 comparisons.
		var total: int=(next._state.requested_damage[id]+amount)&0xffffffff
		if total>=0x80000000:total-=0x100000000
		next._state.requested_damage[id]=total
		if exceeds(total,actor.max_hull,float(_rules.warning_fraction)) and not next._state.warning_issued:
			next._state.warning_issued=true
			next._queue_radio("warning",random,display_available,events)
		if exceeds(total,actor.max_hull,float(_rules.retaliation_fraction)):
			next._state.forced_hostile[id]=true
		if exceeds(total,actor.max_hull,float(_rules.faction_fraction)):
			for other in next._state.forced_hostile.size():
				if not next._state.has("actor_kinds") or next._state.actor_kinds[other]==expected_kind:
					next._state.forced_hostile[other]=true
					if next._state.has("permanent_hostile"):next._state.permanent_hostile[other]=true
			if not next._state.response_issued:
				next._state.response_issued=true
				next._queue_radio("response",random,display_available,events)
				if not _rules.has("contract") or expected_kind==int(_rules.contract.primary_faction):next._state.station_response_flag=true
	return {"owner":next,"random_state":random.snapshot(),"events":events}

func _validate_actor(actor: Dictionary) -> bool:
	if _state.is_empty():return reject("Provocation requires configured traffic")
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if actor.get(key)!=_state[key]:return reject("Provocation belongs to another encounter")
	var id: Variant=actor.get("actor_id")
	if not id is int or id<0 or id>=_state.requested_damage.size():return reject("Provocation actor is outside this faction population")
	var expected_kind:=int(_state.actor_kinds[id]) if _state.has("actor_kinds") else int(_rules.actor_kind)
	if actor.get("actor_kind")!=expected_kind:return reject("Provocation actor affiliation changed")
	for key in ["active","damage_allowed","hostile","forced_hostile"]:
		if not actor.get(key) is bool:return reject("Provocation requires current actor permissions and hostility")
	if actor.forced_hostile!=_state.forced_hostile[id] or not Vitals.integer(actor.get("max_hull")) or not Vitals.integer(actor.get("vitals",{}).get("hull")):return reject("Provocation actor disagrees with its retained state")
	if _state.has("permanent_hostile") and actor.get("script_hostile")!=_state.permanent_hostile[id]:return reject("Persistent actor hostility disagrees with its reaction state")
	return true

func evaluate_systems(actor: Dictionary,amount: Variant,nonplayer: Variant,random_state: Dictionary,display_available: bool) -> Dictionary:
	error=""
	if not _rules.has("kappa_lifecycle") or not Vitals.integer(amount) or not nonplayer is bool or not _validate_actor(actor):return fail("Systems reactions require a matching Kappa actor and valid damage attribution: "+error)
	var pools: Variant=actor.get("systems")
	if not pools is Dictionary or not Vitals.integer(pools.get("integrity")) or not Vitals.integer(pools.get("capacity")) or pools.capacity<1 or not pools.get("disabled") is bool:return fail("Systems reactions require current systems pools")
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	var next:=fork_for_frame();var events:=[]
	var id: int=actor.actor_id;var kind: int=actor.actor_kind
	var accepted: bool=actor.active and actor.damage_allowed and actor.vitals.hull>0 and pools.integrity>0
	var depleted: bool=accepted and amount>=pools.integrity
	if accepted and not nonplayer and not actor.script_hostile and kind==int(_rules.kappa_lifecycle.primary_faction):
		# Systems and ordinary damage accumulate in different source counters.
		var total: int=(next._state.systems_requested_damage[id]+amount)&0xffffffff
		if total>=0x80000000:total-=0x100000000
		next._state.systems_requested_damage[id]=total
		@warning_ignore("integer_division")
		var threshold: int=int(pools.capacity)/int(_rules.kappa_lifecycle.systems.warning_divisor)
		if total>threshold:
			next._state.forced_hostile[id]=true
			if not next._state.warning_issued:
				next._state.warning_issued=true;next._queue_radio("warning",random,display_available,events)
		if depleted:
			# The EMP caller passes false to the faction response. Matching ships
			# become permanently hostile, without its radio/station-alert flag.
			for other in next._state.actor_kinds.size():
				if next._state.actor_kinds[other]==kind:
					next._state.forced_hostile[other]=true;next._state.permanent_hostile[other]=true
	return {"owner":next,"random_state":random.snapshot(),"events":events,
		"depleted_by_player":depleted and not nonplayer,"first_disable_by_player":depleted and not nonplayer and not pools.disabled}

static func exceeds(requested: int, max_hull: int, fraction: float) -> bool:
	return Vitals.single(float(requested))>Vitals.single(Vitals.single(float(max_hull))*Vitals.single(fraction))

func _queue_radio(kind: String, random: RefCounted, display_available: bool, events: Array) -> void:
	# The configured departure has an empty active mission (kind -1) and an
	# empty exclusion list. A missing display still consumes the world's once flag.
	if _rules.has("contract") and _state.active_mission_kind!=int(_rules.contract.empty_mission_kind):return
	if not display_available:return
	var radio: Dictionary=_rules.radio
	var index: int=random.next_int(int(radio.text_draw_bound))
	_state.radio_serial+=1
	var event:={"serial":_state.radio_serial,"kind":kind,"speaker_id":int(radio.speaker_id),
		"text_id":int(radio[kind+"_text_ids"][index]),"voice_event_id":int(radio[kind+"_voice_ids"][index])}
	_state.pending_radio=event.duplicate(true);events.append(event)

func snapshot() -> Dictionary:return _state.duplicate(true)

func retire_contract() -> bool:
	error=""
	if not _rules.has("contract") or _state.active_mission_kind==int(_rules.contract.empty_mission_kind):return reject("There is no active contract reaction context")
	_state.active_mission_kind=int(_rules.contract.empty_mission_kind)
	return true

func reset_actor_damage(actor_id: int) -> bool:
	error=""
	if _state.is_empty() or actor_id<0 or actor_id>=_state.requested_damage.size():return reject("Traffic reset requires its configured actor")
	# Statistics reinitialization clears requested damage. The separate actor
	# force flag and the world's once-only warnings remain retained.
	_state.requested_damage[actor_id]=0
	return true

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules.duplicate(true);copy._state=_state.duplicate(true)
	return copy

func reject(message: String) -> bool:
	error=message;return false

func fail(message: String) -> Dictionary:
	reject(message);return {}
