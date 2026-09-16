extends RefCounted
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
const Kappa=preload("res://src/content/kappa_population_definitions.gd")
## Ordinary NPC ownership; Opening alone uses the radio activation cue. AI and weapon
## target-list selection remain distinct from this canonical actor-ID inventory.
const EscapeCamera=preload("res://src/content/opening_escape_camera_definitions.gd")
const HitDefinitions = preload("res://src/content/ordinary_hit_definitions.gd")
const WeaponHit = preload("res://src/simulation/ordinary_weapon_hit.gd")
const Actor = preload("res://src/simulation/opening_combat_actor.gd")
const Activation = preload("res://src/content/npc_activation_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const TrainingWeapons = preload("res://src/content/combat_training_weapon_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const AmbientCombat=preload("res://src/content/ambient_combat_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const ContractResults=preload("res://src/content/contract_flight_result_definitions.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
const NPCConstruction=preload("res://src/simulation/opening_npc_construction.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Provocation=preload("res://src/simulation/npc_provocation.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var error := ""
var _actors := []
var _activation := {}
var _hit_policy := {}
var _training_weapons := {}
var _identity := {}
var _activated := false
var _phase := -1
var _event_count := 0
var _escape_enabled:=false
var _reputation: RefCounted
var _provocation: RefCounted
var _reputation_rules:={}
var _contact_random:={}
var _display_available:=false
var _contract_encounter:={}
var _contract_settlement:={}

func clear() -> void:
	error = ""
	_actors = []
	_activation = {}
	_hit_policy = {}
	_training_weapons = {}
	_identity = {}
	_activated = false
	_phase = -1
	_event_count = 0
	_escape_enabled=false
	_reputation=null
	_provocation=null;_reputation_rules={};_contact_random={};_display_available=false
	_contract_encounter={}
	_contract_settlement={}

func configure(bindings: RefCounted, catalogues: RefCounted, difficulty: Variant) -> bool:
	clear()
	if bindings == null or catalogues == null: return reject("Opening combat group requires source content")
	var initial: Variant = bindings.opening_actors.get("npc_initialization",{})
	if not initial is Dictionary: return reject("Invalid NPC initialization scope")
	var activation: Variant = initial.get("activation",{})
	if not activation is Dictionary or not Activation.parameters(activation): return reject("Source opening activation is unavailable")
	var rows: Variant = bindings.opening_actors.get("actors")
	if not rows is Array or rows.is_empty(): return reject("Source opening actor population is unavailable")
	var actors := []
	for id in rows.size():
		var actor := Actor.new()
		if not actor.configure(bindings,catalogues,id,difficulty): return reject(actor.error)
		actors.append(actor)
	for id in activation.actor_ids:
		if int(id)>=actors.size(): return reject("Activation names an absent opening actor")
	var events: Variant = bindings.opening_dialogue.get("events")
	if not events is Array or activation.after_event_finished>=events.size(): return reject("Activation event is outside the source radio sequence")
	if bindings.opening_camera.get("pan",{}).get("engagement_after_event_finished") != activation.after_event_finished:
		return reject("Actor activation and camera engagement gates disagree")
	var hit_policy: Variant = bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(hit_policy): return reject("Invalid NPC weapon hit policy")
	_hit_policy = hit_policy.duplicate(true)
	_actors = actors
	_activation = activation.duplicate(true)
	_activation.actor_ids = []
	for id in activation.actor_ids: _activation.actor_ids.append(int(id))
	_identity = {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_event_count = events.size()
	return _configure_reputation(bindings,0,difficulty)

func configure_full_hold(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted, difficulty: Variant) -> bool:
	clear()
	var actor:=Actor.new()
	if not actor.configure_full_hold(bindings,catalogues,construction,difficulty):return reject(actor.error)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Second pirate lacks the ordinary NPC weapon hit policy")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(bindings.full_hold_pirate.campaign_cursor)}
	_actors=[actor];_hit_policy=policy.duplicate(true)
	return _configure_reputation(bindings,4,difficulty)


func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant) -> bool:
	clear()
	var actors:=[]
	for id in 4:
		var actor:=Actor.new()
		if not actor.configure_combat_training(bindings,catalogues,world,id,rank,difficulty):return reject(actor.error)
		actors.append(actor)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Combat training lacks the ordinary NPC weapon hit policy")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":7}
	_actors=actors;_hit_policy=policy.duplicate(true)
	if TrainingWeapons.parameters(bindings.combat_training_weapons):_training_weapons=bindings.combat_training_weapons.duplicate(true)
	return _configure_reputation(bindings,7,difficulty)

func apply_combat_training_guidance(data: Dictionary, decision: Dictionary) -> bool:
	error=""
	var id: Variant=decision.get("actor_id")
	if _identity.get("campaign_cursor")!=7 or _actors.size()!=4 or not id is int or id<0 or id>=_actors.size():return reject("Combat-training activity names an unavailable actor")
	if not _actors[id].apply_combat_training_guidance(data,decision):return reject(_actors[id].error)
	_activated=_activated or bool(_actors[id].snapshot().active)
	return true

func configure_local_patrol(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant) -> bool:
	clear()
	if world==null:return reject("Local patrol requires its generated world")
	var data:=Travel.population(bindings,world.snapshot(),rank,difficulty)
	if data.is_empty():return reject("Local patrol requires its verified population")
	var actors:=[]
	for id in int(data.actor_count):
		var actor:=Actor.new()
		if not actor.configure_local_patrol(bindings,catalogues,world,id,rank,difficulty):return reject(actor.error)
		actors.append(actor)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor)}
	_actors=actors
	return _configure_reputation(bindings,int(data.campaign_cursor),difficulty)

func _configure_reputation(bindings: RefCounted, cursor: int, difficulty: Variant) -> bool:
	if not Reputation.available(bindings):return true
	var history:=Reputation.new()
	var kinds:=_actors.map(func(actor):return int(actor.snapshot().actor_kind))
	if not history.configure(bindings,cursor,kinds,difficulty):return reject(history.error)
	_reputation=history
	return true

func configure_local_traffic(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant, equipment: RefCounted, reputation: Dictionary) -> bool:
	if not configure_local_patrol(bindings,catalogues,world,rank,difficulty):return false
	var reaction:=Provocation.new()
	if not reaction.configure(bindings,catalogues,world.snapshot(),rank,difficulty,equipment,reputation):clear();return reject(reaction.error)
	var weapons:=Travel.weapons(bindings,world.snapshot(),rank,difficulty)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if weapons.is_empty() or not HitDefinitions.parameters(policy):clear();return reject("Local combat lacks verified weapons and normal-hit rules")
	for actor in _actors:
		if not actor.enable_local_combat():clear();return reject(actor.error)
	_provocation=reaction;_training_weapons=weapons;_hit_policy=policy.duplicate(true)
	_reputation_rules=bindings.mido_travel.reputation.duplicate(true)
	return true

func has_local_reactions() -> bool:return _provocation!=null

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted,reputation: Dictionary) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Convoy combat requires its generated encounter")
	var data:=Convoy.lifecycle(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported convoy combat lifecycle")
	var reaction:=Provocation.new()
	if not reaction.configure_convoy(bindings,catalogues,construction,equipment,reputation):return reject(reaction.error)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Convoy combat lacks the ordinary hit policy")
	var actors:=[]
	for id in int(data.actor_count):
		var actor:=Actor.new()
		if not actor.configure_convoy(bindings,catalogues,construction,id) or not actor.enable_convoy_combat():return reject(actor.error)
		actors.append(actor)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor)}
	_actors=actors;_hit_policy=policy.duplicate(true);_provocation=reaction;_training_weapons=data
	_reputation_rules=bindings.mido_travel.convoy_lifecycle.terran_hostility.duplicate(true)
	if not _configure_reputation(bindings,int(data.campaign_cursor),data.difficulty):
		var reason:=error;clear();return reject(reason)
	return true

func configure_alioth_attack(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted,reputation: Dictionary) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Alioth combat requires its generated encounter")
	var data:=Alioth.lifecycle(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported Alioth combat lifecycle")
	var reaction:=Provocation.new()
	if not reaction.configure_alioth_attack(bindings,catalogues,construction,equipment,reputation):return reject(reaction.error)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Alioth combat lacks the ordinary hit policy")
	var actors:=[]
	for id in int(data.actor_count):
		var actor:=Actor.new()
		if not actor.configure_alioth_attack(bindings,catalogues,construction,id) or not actor.enable_alioth_combat():return reject(actor.error)
		actors.append(actor)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor)}
	_actors=actors;_hit_policy=policy.duplicate(true);_provocation=reaction;_training_weapons=data
	if not _configure_reputation(bindings,int(data.campaign_cursor),data.difficulty):
		var reason:=error;clear();return reject(reason)
	return true

func apply_alioth_guidance(decision: Dictionary) -> bool:
	var id: Variant=decision.get("actor_id")
	if not _training_weapons.has("alioth_lifecycle") or not id is int or id<0 or id>=_actors.size():return reject("Alioth guidance names an unavailable actor")
	if not _actors[id].apply_alioth_guidance(decision):return reject(_actors[id].error)
	_activated=_activated or bool(_actors[id].snapshot().active)
	return true

func configure_kappa_rescue(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,reputation: Dictionary) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Kappa combat requires its generated encounter")
	var data:=Kappa.lifecycle(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported Kappa combat lifecycle")
	var reaction:=Provocation.new()
	if not reaction.configure_kappa_rescue(bindings,catalogues,construction,reputation):return reject(reaction.error)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Kappa combat lacks the ordinary hit policy")
	var actors:=[]
	for id in int(data.actor_count):
		var actor:=Actor.new()
		if not actor.configure_kappa_rescue(bindings,catalogues,construction,id) or not actor.enable_kappa_combat():return reject(actor.error)
		actors.append(actor)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor)}
	_actors=actors;_hit_policy=policy.duplicate(true);_provocation=reaction;_training_weapons=data
	_reputation_rules=data.kappa_lifecycle.terran_hostility.duplicate(true)
	if not _configure_reputation(bindings,int(data.campaign_cursor),data.difficulty):
		var reason:=error;clear();return reject(reason)
	return true

func apply_kappa_guidance(decision: Dictionary) -> bool:
	var id: Variant=decision.get("actor_id")
	if not _training_weapons.has("kappa_lifecycle") or not id is int or id<0 or id>=_actors.size():return reject("Kappa guidance names an unavailable actor")
	if not _actors[id].apply_kappa_guidance(decision):return reject(_actors[id].error)
	_activated=_activated or bool(_actors[id].snapshot().active)
	return true

func advance_systems(actor_id: int,delta_ms: Variant) -> bool:
	if not _training_weapons.has("kappa_lifecycle") or actor_id<0 or actor_id>=_actors.size():return reject("Systems update names an unavailable fighter")
	if not _actors[actor_id].advance_systems(delta_ms):return reject(_actors[actor_id].error)
	return true

func systems_for_frame(actor_id: int) -> RefCounted:
	if not _training_weapons.has("kappa_lifecycle") or actor_id<0 or actor_id>=_actors.size():reject("Systems update names an unavailable fighter");return null
	return _actors[actor_id].systems_for_frame()

func apply_kappa_sequence(owner: RefCounted) -> bool:
	if not _training_weapons.has("kappa_lifecycle"):return reject("This group has no Kappa sequence")
	var next: RefCounted=_provocation.fork_for_frame()
	if not next.apply_kappa_sequence(owner):return reject(next.error)
	var actors:=_reaction_actors(next,_actors)
	if actors.is_empty():return false
	_actors=actors;_provocation=next
	return true

func systems_hit(actor_id: Variant,amount: Variant,nonplayer_source: Variant=false) -> Dictionary:
	error=""
	if not _training_weapons.has("kappa_lifecycle") or not actor_id is int or actor_id<0 or actor_id>=_actors.size():reject("Systems hit names an unavailable fighter");return {}
	var actor: RefCounted=_actors[actor_id].fork_for_frame()
	var reaction: Dictionary=_provocation.evaluate_systems(actor.snapshot(),amount,nonplayer_source,_contact_random,_display_available)
	if reaction.is_empty():reject(_provocation.error);return {}
	var result: Dictionary=actor.systems_hit(amount)
	if result.is_empty():reject(actor.error);return {}
	var history: RefCounted=_reputation.fork_for_frame()
	if reaction.depleted_by_player and not history.record_systems_depletion(actor.snapshot(),result):reject(history.error);return {}
	var staged:=_actors.duplicate();staged[actor_id]=actor
	var actors:=_reaction_actors(reaction.owner,staged)
	if actors.is_empty():return {}
	_actors=actors;_provocation=reaction.owner;_reputation=history;_contact_random=reaction.random_state
	result.reactions=reaction.events.duplicate(true)
	result.first_disable_by_player=reaction.first_disable_by_player
	return result

func _reaction_actors(reaction: RefCounted,actors: Array) -> Array:
	var state: Dictionary=reaction.snapshot();var result:=[]
	for id in actors.size():
		var actor: RefCounted=actors[id].fork_for_frame()
		if _training_weapons.has("kappa_lifecycle"):
			if not actor.retain_kappa_force(state.forced_hostile[id],state.permanent_hostile[id]):reject(actor.error);return []
		else:
			if not actor.retain_local_force(state.forced_hostile[id]):reject(actor.error);return []
		result.append(actor)
	return result

func alioth_actor_context() -> Dictionary:
	if not _training_weapons.has("alioth_lifecycle"):return {}
	var result:=_identity.duplicate()
	result.actors=[]
	for owner in _actors:
		var actor: Dictionary=owner.snapshot()
		actor.current_hull=int(actor.vitals.hull)
		result.actors.append(actor)
	return result

func apply_alioth_sequence(owner: RefCounted) -> bool:
	error=""
	if not _training_weapons.has("alioth_lifecycle"):return reject("This group has no Alioth sequence")
	var actors:=[]
	for actor in _actors:
		var next: RefCounted=actor.fork_for_frame()
		if not next.apply_alioth_retirement(owner):return reject(next.error)
		actors.append(next)
	_actors=actors
	return true

func apply_convoy_guidance(decision: Dictionary) -> bool:
	var id: Variant=decision.get("actor_id")
	if not _training_weapons.has("capital_death") or not id is int or id<0 or id>=_actors.size():return reject("Convoy guidance names an unavailable actor")
	if not _actors[id].apply_convoy_guidance(decision):return reject(_actors[id].error)
	_activated=_activated or bool(_actors[id].snapshot().active)
	return true

func apply_convoy_capture(owner: RefCounted) -> bool:
	error=""
	if not _training_weapons.has("capital_death"):return reject("This group has no convoy capture owner")
	var actors:=[]
	for actor in _actors:
		var next: RefCounted=actor.fork_for_frame()
		if not next.apply_convoy_capture(owner):return reject(next.error)
		actors.append(next)
	_actors=actors
	return true

func configure_contract(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Contract combat requires its accepted generated population")
	var data:=ContractLife.population(bindings,construction.snapshot())
	if data.is_empty():data=Junk.population(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported contract combat lifecycle")
	var reaction: RefCounted
	var debris: bool=int(data.mission.kind)==7
	if debris:
		if equipment==null or equipment.snapshot().get("loadout",{}).get("station_id")!=int(data.station_id):return reject("Debris combat belongs to another equipped location")
	else:
		reaction=Provocation.new()
		if not reaction.configure_contract(bindings,catalogues,construction,equipment):return reject(reaction.error)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Contract combat lacks the ordinary hit policy")
	var actors:=[]
	for id in int(data.actor_count):
		var actor:=Actor.new()
		if not actor.configure_contract(bindings,catalogues,construction,id) or not actor.enable_contract_combat(bindings):return reject(actor.error)
		actors.append(actor)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor)}
	_actors=actors;_hit_policy=policy.duplicate(true);_provocation=reaction;_training_weapons=data
	_contract_encounter=construction.snapshot().contract_encounter.duplicate(true)
	if not debris and not _configure_reputation(bindings,int(data.campaign_cursor),data.difficulty):
		var reason:=error;clear();return reject(reason)
	return true

func apply_contract_guidance(decision: Dictionary) -> bool:
	var id: Variant=decision.get("actor_id")
	if _contract_encounter.is_empty() or not id is int or id<0 or id>=_actors.size():return reject("Contract guidance names an unavailable actor")
	if not _actors[id].apply_contract_guidance(decision):return reject(_actors[id].error)
	_activated=_activated or bool(_actors[id].snapshot().active)
	return true

func relaunch_ambient(actor_id: int,bindings: RefCounted,death_owner: RefCounted=null) -> bool:
	error=""
	if _provocation==null or actor_id<0 or actor_id>=_actors.size():return reject("Traffic launch requires its configured combat group")
	var actor: RefCounted=_actors[actor_id].fork_for_frame()
	var reaction: RefCounted=_provocation.fork_for_frame()
	if not actor.relaunch_ambient(bindings,death_owner):return reject(actor.error)
	if not reaction.reset_actor_damage(actor_id):return reject(reaction.error)
	var history: RefCounted=_reputation.fork_for_frame()
	if actor.snapshot().has("spawn_generation") and not history.register_relaunch(actor.snapshot()):return reject(history.error)
	_actors[actor_id]=actor;_provocation=reaction
	_reputation=history
	return true

func apply_ambient_guidance(decision: Dictionary) -> bool:
	error=""
	var id: Variant=decision.get("actor_id")
	if not id is int or id<0 or id>=_actors.size():return reject("Ambient decision names an unavailable actor")
	if not _actors[id].apply_ambient_guidance(decision):return reject(_actors[id].error)
	return true

func apply_ambient_departure_pose(actor_id: int,root: Variant) -> bool:
	error=""
	if actor_id<0 or actor_id>=_actors.size():return reject("Departure names an unavailable actor")
	if not _actors[actor_id].apply_ambient_departure_pose(root):return reject(_actors[actor_id].error)
	return true

func configure_ambient(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,rank: Variant,difficulty: Variant,equipment: RefCounted,reputation: Dictionary) -> bool:
	clear()
	if not construction is NPCConstruction:return reject("Ambient combat requires its generated construction")
	var data:=AmbientCombat.population(bindings,construction.snapshot(),rank,difficulty)
	if data.is_empty() or not TrainingWeapons.parameters(bindings.combat_training_weapons):return reject("Ambient combat lacks supported population and primary-hit declarations")
	if data.has("free_traffic"):
		data=FreeLife.population(bindings,construction.snapshot())
		if data.is_empty():return reject("Ordinary free-flight combat requires its verified lifecycle")
	var reaction:=Provocation.new()
	if not reaction.configure_ambient(bindings,catalogues,construction,rank,difficulty,equipment,reputation):return reject(reaction.error)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Ambient combat lacks the ordinary hit policy")
	var actors:=[]
	for id in int(data.actor_count):
		var actor:=Actor.new()
		if not actor.configure_ambient(bindings,catalogues,construction,id,rank,difficulty) or not actor.enable_local_combat():return reject(actor.error)
		actors.append(actor)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor)}
	_actors=actors;_hit_policy=policy.duplicate(true);_provocation=reaction
	_training_weapons=data.duplicate(true) if data.has("free_lifecycle") else {"scope":"mido_ambient_ordinary_weapons","campaign_cursor":int(data.campaign_cursor)}
	_reputation_rules=data.free_lifecycle.standing.duplicate(true) if data.has("free_lifecycle") else bindings.mido_travel.reputation.duplicate(true)
	if not _configure_reputation(bindings,int(data.campaign_cursor),difficulty):
		var reason:=error;clear();return reject(reason)
	return true

func begin_contact_pass(random_state: Dictionary, display_available: bool) -> bool:
	error=""
	if _provocation==null and _contract_encounter.get("kind")!=7:return reject("This encounter does not use local provocation")
	var random:=Random.new()
	if not random.restore(random_state):return reject(random.error)
	_contact_random=random.snapshot();_display_available=display_available
	return true

func contact_random_state() -> Dictionary:return _contact_random.duplicate(true)

func current_reputation() -> Dictionary:
	if _contract_encounter.get("kind")==7:
		return _contract_settlement.reputation.duplicate(true) if not _contract_settlement.is_empty() else _contract_encounter.context.reputation.duplicate(true)
	if _provocation==null:return {}
	if not _contract_settlement.is_empty():return _reputation.apply_to(_contract_settlement.reputation,int(_contract_settlement.event_count))
	return reputation_after(_provocation.snapshot().initial_reputation)

func open_contract_result(bindings: RefCounted,mode: int) -> bool:
	error=""
	if _contract_encounter.is_empty() or not _contract_settlement.is_empty() or not ContractResults.available(bindings):return reject("This combat group has no unsettled contract result")
	if bindings.base_content_id!=_identity.base_content_id or bindings.binding_id!=_identity.binding_id:return reject("Contract result belongs to another content identity")
	var rules: Dictionary=bindings.early_contracts.flight_results
	if mode not in [int(rules.success_result_mode),int(rules.failure_result_mode)]:return reject("Unsupported contract result mode")
	var context: Dictionary=_contract_encounter.context
	var standing:=current_reputation()
	if mode==int(rules.success_result_mode):
		standing=ContractResults.standing_after(bindings.early_contracts,standing,int(context.mission.kind),int(context.client_faction),float(context.difficulty))
	if standing.is_empty():return reject("The contract lost its faction standing")
	# Retain lethal history, but apply future hits after the result bonus. This
	# matters at the reputation caps: replaying the old hits would change it twice.
	_contract_settlement={"mode":mode,"retired":false,"reputation":standing,"event_count":0 if _reputation==null else _reputation.snapshot().events.size()}
	return true

func retire_contract_result() -> bool:
	error=""
	if _contract_settlement.is_empty() or _contract_settlement.retired:return reject("No contract result awaits retirement")
	if _provocation!=null and not _provocation.retire_contract():return reject(_provocation.error)
	_contract_settlement.retired=true
	return true

func reputation_after(prior: Dictionary) -> Dictionary:
	error=""
	if _reputation==null:reject("This encounter has no retained reputation hit history");return {}
	var result: Dictionary=_reputation.apply_to(prior)
	if result.is_empty():reject(_reputation.error)
	return result

func apply_local_patrol_guidance(decision: Dictionary) -> bool:
	error=""
	var id: Variant=decision.get("actor_id")
	if _identity.get("campaign_cursor")!=10 or not id is int or id<0 or id>=_actors.size():return reject("Local patrol activity names an unavailable actor")
	if not _actors[id].apply_local_patrol_guidance(decision):return reject(_actors[id].error)
	_activated=_activated or bool(_actors[id].snapshot().active)
	return true

func apply_full_hold_guidance(data: Dictionary, decision: Dictionary) -> bool:
	error=""
	if _identity.get("campaign_cursor")!=4 or _actors.size()!=1:return reject("This group has no second-trip activity context")
	if not _actors[0].apply_full_hold_guidance(data,decision):return reject(_actors[0].error)
	_activated=_activated or bool(_actors[0].snapshot().active)
	return true

func apply_full_hold_appearance(data: Dictionary, root: Variant, statistics: Variant) -> bool:
	error=""
	if _identity.get("campaign_cursor")!=4 or _actors.size()!=1:return reject("This group has no second-trip appearance context")
	if not _actors[0].apply_full_hold_appearance(data,root,statistics):return reject(_actors[0].error)
	_activated=true
	return true

func configure_escape(bindings: RefCounted) -> bool:
	error=""
	if _activation.is_empty() or _escape_enabled or _phase>0 or bindings==null or bindings.binding_id!=_identity.get("binding_id") or not EscapeCamera.parameters(bindings.opening_staging.get("escape_camera",{})):
		return reject("Escape actor lifecycle requires matching fresh declarations")
	_escape_enabled=true
	return true

func update(scene: Variant, phase: Variant, preceding_radio: Variant) -> bool:
	error = ""
	if _actors.is_empty() or _activation.is_empty(): return reject("This combat group has no Opening radio activation owner")
	if not Numbers.integer(phase,0,16 if _escape_enabled else 4) or phase<_phase: return reject("Opening combat phase is invalid or regressed")
	if not preceding_radio is Dictionary: return reject("Opening activation requires preceding radio state")
	for key in _identity:
		if preceding_radio.get(key)!=_identity[key]: return reject("Activation radio belongs to another content identity")
	var finished: Variant = preceding_radio.get("finished")
	if not finished is Array or finished.size()!=_event_count: return reject("Activation radio completion flags are unavailable")
	for done in finished:
		if not done is bool: return reject("Invalid activation radio completion flag")
	if phase>4:
		if not _activated or not finished[10]:return reject("Escape precedes its earned encounter radio")
		for actor in _actors:
			if actor.snapshot().vitals.hull>0:return reject("Escape cannot bypass a surviving opening actor")
	var activate_now: bool = not _activated and phase>=int(_activation.phase)
	if activate_now and not finished[int(_activation.after_event_finished)]: return reject("Opening activation precedes its source radio gate")
	var staged := []
	for actor in _actors:
		var next: RefCounted = actor.fork_for_frame()
		if not next.apply_scene(scene): return reject(next.error)
		if activate_now and next.snapshot().actor_id in _activation.actor_ids:
			if not next.apply_activation(_activation): return reject(next.error)
		staged.append(next)
	_actors = staged
	_phase = int(phase)
	_activated = _activated or activate_now
	return true

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate()
	result.activated = _activated
	result.phase = _phase
	result.actors = []
	for actor in _actors: result.actors.append(actor.snapshot())
	if _reputation!=null:result.reputation=_reputation.snapshot()
	elif _contract_encounter.get("kind")==7:result.reputation={"events":[]};result.current_reputation=current_reputation()
	if _provocation!=null:
		result.provocation=_provocation.snapshot();result.current_reputation=current_reputation()
	if not _contract_encounter.is_empty():result.contract_encounter=_contract_encounter.duplicate(true)
	if not _contract_settlement.is_empty():result.contract_settlement=_contract_settlement.duplicate(true)
	if _training_weapons.has("free_lifecycle"):result.free_context=_training_weapons.free_context.duplicate(true)
	return result

func normal_hit(actor_id: Variant, amount: Variant, nonplayer_source: Variant=false) -> Dictionary:
	error = ""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size():
		reject("Normal hit names an unavailable opening actor")
		return {}
	var actor: RefCounted=_actors[actor_id].fork_for_frame()
	var reaction:={}
	if _provocation!=null:
		reaction=_provocation.evaluate(actor.snapshot(),amount,nonplayer_source,_contact_random,_display_available)
		if reaction.is_empty():reject(_provocation.error);return {}
	var result: Dictionary = actor.normal_hit(amount,nonplayer_source)
	if result.is_empty():reject(actor.error);return {}
	var history: RefCounted=_reputation
	if result.destroyed_now and _reputation!=null:
		history=_reputation.fork_for_frame()
		if not history.record_lethal(actor.snapshot()):reject(history.error);return {}
	var staged:=_actors.duplicate();staged[actor_id]=actor
	if not reaction.is_empty():
		staged=_reaction_actors(reaction.owner,staged)
		if staged.is_empty():return {}
		_provocation=reaction.owner;_contact_random=reaction.random_state
		result.reactions=reaction.events.duplicate(true)
	_actors=staged;_reputation=history
	return result

func set_pose(actor_id: Variant, pose: Variant, physical_pose: Variant=null) -> bool:
	error=""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size(): return reject("Pose names an unavailable opening actor")
	if not _actors[actor_id].set_pose(pose,physical_pose): return reject(_actors[actor_id].error)
	return true

func refresh_hostility(actor_id: Variant) -> bool:
	error=""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size(): return reject("Hostility names an unavailable opening actor")
	if _provocation!=null:
		if _training_weapons.has("kappa_lifecycle"):
			var state: Dictionary=_provocation.snapshot()
			if not _actors[actor_id].refresh_kappa_hostility(current_reputation(),state.forced_hostile[actor_id],state.permanent_hostile[actor_id],_reputation_rules):return reject(_actors[actor_id].error)
			return true
		if _training_weapons.has("free_lifecycle"):
			if not _actors[actor_id].apply_free_hostility(current_reputation(),_provocation.snapshot().forced_hostile[actor_id],_reputation_rules):return reject(_actors[actor_id].error)
			return true
		if _training_weapons.has("alioth_lifecycle"):
			if not _actors[actor_id].refresh_alioth_hostility(_provocation.snapshot().forced_hostile[actor_id]):return reject(_actors[actor_id].error)
			return true
		if _training_weapons.has("capital_death"):
			if not _actors[actor_id].refresh_convoy_hostility(current_reputation(),_provocation.snapshot().forced_hostile[actor_id],_reputation_rules):return reject(_actors[actor_id].error)
			return true
		if not _contract_encounter.is_empty():
			if not _actors[actor_id].refresh_contract_hostility(_provocation.snapshot().forced_hostile[actor_id]):return reject(_actors[actor_id].error)
			return true
		if not _actors[actor_id].apply_local_hostility(current_reputation(),_provocation.snapshot().forced_hostile[actor_id],_reputation_rules):return reject(_actors[actor_id].error)
		return true
	if not _actors[actor_id].refresh_hostility(): return reject(_actors[actor_id].error)
	return true

func apply_destruction(actor_id: Variant, death: Dictionary) -> bool:
	error=""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size(): return reject("Destruction names an unavailable opening actor")
	if not _actors[actor_id].apply_destruction(death): return reject(_actors[actor_id].error)
	return true

func apply_freighter_destruction(actor_id: Variant,owner: RefCounted) -> bool:
	error=""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size():return reject("Freighter destruction names an unavailable actor")
	if not _actors[actor_id].apply_freighter_destruction(owner):return reject(_actors[actor_id].error)
	return true

func apply_debris_destruction(actor_id: int,owner: RefCounted) -> bool:
	error=""
	if actor_id<0 or actor_id>=_actors.size():return reject("Debris destruction names an unavailable actor")
	if not _actors[actor_id].apply_debris_destruction(owner):return reject(_actors[actor_id].error)
	return true

func shooter_states() -> Array:
	error=""
	if _actors.is_empty():
		reject("Configure opening actors before reading shooter state")
		return []
	var result := []
	for actor in _actors:
		var state: Dictionary=actor.snapshot()
		if not state.get("hostile") is bool:
			reject("Current NPC hostility is unavailable")
			return []
		# Source guns retain their statistics owner even while it is inactive.
		result.append({"present":true,"hostile":state.hostile})
	return result

func supports_weapon_hit(weapon: Variant) -> bool:
	var kinds: Array=[0]
	if not _training_weapons.is_empty() and weapon is Dictionary:
		if weapon.get("nonplayer_source",false)==true:
			var valid: bool=Kappa.npc_hit(_training_weapons,weapon) if _training_weapons.has("kappa_lifecycle") else FreeLife.npc_hit(_training_weapons,weapon) if _training_weapons.has("free_lifecycle") else Alioth.npc_hit(_training_weapons,weapon) if _training_weapons.has("alioth_lifecycle") else Convoy.npc_hit(_training_weapons,weapon) if _training_weapons.has("capital_death") else (ContractLife.npc_hit(_training_weapons,weapon) if not _contract_encounter.is_empty() else (Travel.npc_hit(_training_weapons,weapon) if _provocation!=null else TrainingWeapons.npc_hit(_training_weapons,weapon)))
			if not valid:return reject("NPC damage differs from this encounter's weapon declaration")
			kinds=[0,1]
		elif weapon.get("campaign_cursor") in [18,19] and preload("res://src/content/ordinary_fitting_definitions.gd").ordinary(weapon):kinds=[0,1,2]
		elif weapon.get("kind")==2:
			if not TrainingWeapons.dispersed_primary(weapon):return reject("Player damage lacks its verified primary declaration")
			kinds=[0,2]
	elif weapon is Dictionary and weapon.get("nonplayer_source",false)==true:return reject("This group has no verified NPC weapon contact path")
	error = WeaponHit.validate(weapon,_identity,_hit_policy,kinds)
	return error.is_empty()

func weapon_hit(actor_id: Variant, weapon: Variant) -> Dictionary:
	if not supports_weapon_hit(weapon): return {}
	return normal_hit(actor_id,weapon.ordinary_hit_policy.nonplayer_damage,weapon.get("nonplayer_source",false))

func record_contact(actor_id: Variant, incoming_velocity: Variant,point_box_index: Variant=null) -> bool:
	error = ""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size():
		return reject("Contact names an unavailable opening actor")
	if not _actors[actor_id].record_contact(incoming_velocity,point_box_index): return reject(_actors[actor_id].error)
	return true

func collision_context(actor_id: Variant) -> Dictionary:
	error = ""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size():
		reject("Collision target names an unavailable opening actor")
		return {}
	return _actors[actor_id].collision_context()

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._identity = _identity.duplicate()
	copy._activation = _activation.duplicate(true)
	copy._hit_policy = _hit_policy.duplicate(true)
	copy._training_weapons = _training_weapons.duplicate(true)
	copy._activated = _activated
	copy._phase = _phase
	copy._event_count = _event_count
	copy._escape_enabled=_escape_enabled
	if _reputation!=null:copy._reputation=_reputation.fork_for_frame()
	if _provocation!=null:copy._provocation=_provocation.fork_for_frame()
	copy._reputation_rules=_reputation_rules.duplicate(true);copy._contact_random=_contact_random.duplicate(true);copy._display_available=_display_available
	copy._contract_encounter=_contract_encounter.duplicate(true)
	copy._contract_settlement=_contract_settlement.duplicate(true)
	for actor in _actors: copy._actors.append(actor.fork_for_frame())
	return copy

func reject(message: String) -> bool:
	error = message
	return false
