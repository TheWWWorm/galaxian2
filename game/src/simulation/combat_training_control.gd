extends RefCounted
const Kappa=preload("res://src/content/kappa_population_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
const AliothSequence=preload("res://src/simulation/alioth_attack.gd")
## Shared population guidance, motion and prepared cargo destruction. Local
## traffic requires its own reaction rules and retained career reputation.
const Rules=preload("res://src/content/combat_training_control_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const DeathRules=preload("res://src/content/combat_training_destruction_definitions.gd")
const DeathResources=preload("res://src/content/npc_destruction_resources.gd")
const Death=preload("res://src/simulation/npc_destruction.gd")
const Accounting=preload("res://src/simulation/npc_death_accounting.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Guidance=preload("res://src/simulation/opening_npc_guidance.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const AmbientLife=preload("res://src/content/ambient_lifecycle_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const ContractResults=preload("res://src/content/contract_flight_result_definitions.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
const DebrisDeath=preload("res://src/simulation/debris_destruction.gd")
const LaunchClock=preload("res://src/simulation/traffic_launch_clock.gd")
const FreightMotion=preload("res://src/simulation/freighter_motion.gd")
const FreightDeath=preload("res://src/simulation/freighter_destruction.gd")
var error:=""
var _identity:={}
var _rules:={}
var _combat: RefCounted
var _guidance:=[]
var _flight:=[]
var _random:={}
var _initial_actors:=[]
var _destruction:=[]
var _death_rules:={}
var _accounting: RefCounted
var _started:=false
var _max_ms:=0
var _local_patrol:=false
var _ambient:=false
var _flight_identity: RefCounted
var _scene_clocked:=false
var _contract:=false
var _convoy:=false
var _alioth:=false
var _kappa:=false
var _alioth_sequence:={}
var _bindings: RefCounted
var _construction: RefCounted
var _death_resources: RefCounted
var _launch_clock: RefCounted
var _cargo:=[]
var _launch_pending:=[]
var _contract_result:={}

func configure(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant) -> bool:
	clear()
	if bindings==null or not world is World or not Rules.parameters(bindings.combat_training_control):return reject("Combat-training control requires its verified world initialization")
	var combat:=Combat.new()
	if not combat.configure_combat_training(bindings,catalogues,world,rank,difficulty):return reject(combat.error)
	return _configure_controls(bindings,catalogues,world,rank,difficulty,combat,bindings.combat_training_control,false)

func configure_local_patrol(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant) -> bool:
	clear()
	if not world is World:return reject("Local patrol requires its prepared world")
	var data:=Travel.population(bindings,world.snapshot(),rank,difficulty)
	if data.is_empty():return reject("Local patrol requires a supported generated population")
	var combat:=Combat.new()
	if not combat.configure_local_patrol(bindings,catalogues,world,rank,difficulty):return reject(combat.error)
	return _configure_controls(bindings,catalogues,world,rank,difficulty,combat,data,true)

func configure_local_traffic(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant, equipment: RefCounted, reputation: Dictionary) -> bool:
	clear()
	if not world is World:return reject("Local combat requires its prepared world")
	var data:=Travel.population(bindings,world.snapshot(),rank,difficulty)
	var death:=Travel.destruction(bindings,world.snapshot(),rank,difficulty)
	if data.is_empty() or death.is_empty():return reject("Local combat requires its verified population and death rules")
	var combat:=Combat.new()
	if not combat.configure_local_traffic(bindings,catalogues,world,rank,difficulty,equipment,reputation):return reject(combat.error)
	if not _configure_controls(bindings,catalogues,world,rank,difficulty,combat,data,true):return false
	_death_rules=death
	return true

func _configure_controls(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant, combat: RefCounted, rules: Dictionary, local_patrol: bool) -> bool:
	var random:=Random.new()
	if not random.restore(world.snapshot().get("random_state")):return reject(random.error)
	var guidance:=[];var flight:=[]
	for id in int(rules.actor_count):
		var controller:=Guidance.new()
		var ready: bool=controller.configure_local_patrol(bindings,catalogues,world,id,rank,difficulty) if local_patrol else controller.configure_combat_training(bindings,catalogues,world,id,rank,difficulty)
		if not ready:return reject(controller.error)
		var motion:=Flight.new()
		if not motion.configure(bindings,combat.snapshot().actors[id].body_pose):return reject(motion.error)
		guidance.append(controller);flight.append(motion)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(rules.campaign_cursor),"rank":rank}
	_flight_identity=RefCounted.new()
	_rules=rules.duplicate(true);_local_patrol=local_patrol
	_combat=combat;_guidance=guidance;_flight=flight;_random=random.snapshot()
	_initial_actors=world.snapshot().npc_construction.actors.duplicate(true)
	_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	return true

func configure_ambient(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,rank: Variant,difficulty: Variant,equipment: RefCounted,reputation: Dictionary) -> bool:
	clear()
	if not construction is Construction or bindings==null or not AmbientLife.recycling_parameters(bindings.ambient_lifecycle):return reject("Mixed traffic control requires verified construction and recycling")
	var rules:=AmbientLife.guidance(bindings,construction.snapshot(),rank,difficulty)
	if rules.is_empty():return reject("Unsupported mixed traffic guidance")
	var combat:=Combat.new()
	if not combat.configure_ambient(bindings,catalogues,construction,rank,difficulty,equipment,reputation):return reject(combat.error)
	var clock:=LaunchClock.new()
	var zero: int=int(bindings.ambient_lifecycle.recycling.initial_world_clocks_ms)
	if not clock.configure(bindings,construction,zero,zero):return reject(clock.error)
	var guidance:=[];var flight:=[]
	var actors: Array=construction.snapshot().actors
	for id in actors.size():
		if actors[id].population_group=="freighter":
			var motion:=FreightMotion.new()
			if not motion.configure(bindings,construction,id):return reject(motion.error)
			guidance.append(null);flight.append(motion)
		else:
			var controller:=Guidance.new();var motion:=Flight.new()
			if not controller.configure_ambient(bindings,catalogues,construction,id,rank,difficulty) or not motion.configure(bindings,combat.snapshot().actors[id].body_pose):return reject(controller.error+motion.error)
			guidance.append(controller);flight.append(motion)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(rules.campaign_cursor),"rank":rank}
	_flight_identity=RefCounted.new()
	_rules=rules;_local_patrol=true;_ambient=true
	_combat=combat;_guidance=guidance;_flight=flight;_random=construction.snapshot().random_state.duplicate(true)
	_initial_actors=actors.duplicate(true);_cargo=actors.map(func(actor):return actor.cargo.duplicate(true))
	_launch_pending.resize(actors.size());_launch_pending.fill(false)
	_bindings=bindings;_construction=construction;_launch_clock=clock
	_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	return true

func configure_contract(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted) -> bool:
	clear()
	if not construction is Construction:return reject("Contract control requires its accepted generated population")
	var rules:=ContractLife.population(bindings,construction.snapshot())
	if rules.is_empty():rules=Junk.population(bindings,construction.snapshot())
	if rules.is_empty():return reject("Unsupported contract control lifecycle")
	var combat:=Combat.new()
	if not combat.configure_contract(bindings,catalogues,construction,equipment):return reject(combat.error)
	var guidance:=[];var flight:=[]
	for id in int(rules.actor_count):
		if int(rules.mission.kind)==7:
			guidance.append(null);flight.append(null)
			continue
		var controller:=Guidance.new();var motion:=Flight.new()
		if not controller.configure_contract(bindings,catalogues,construction,id) or not motion.configure(bindings,combat.snapshot().actors[id].body_pose):return reject(controller.error+motion.error)
		guidance.append(controller);flight.append(motion)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(rules.campaign_cursor),"rank":int(rules.rank)}
	_flight_identity=RefCounted.new()
	_rules=rules;_death_rules=rules;_contract=true
	_combat=combat;_guidance=guidance;_flight=flight;_random=construction.snapshot().random_state.duplicate(true)
	_initial_actors=construction.snapshot().actors.duplicate(true)
	_bindings=bindings;_construction=construction;_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	if ContractResults.available(bindings):_contract_result={"clock_ms":0,"elapsed_ms":0,"mode":0,"retired":false}
	return true

func _set_contract_destruction(bindings: RefCounted,resources: RefCounted) -> bool:
	if _started or _accounting!=null or bindings!=_bindings or not resources is DeathResources:return reject("Prepare contract destruction once before flight starts")
	var owners:=[]
	for id in _initial_actors.size():
		if int(_rules.mission.kind)==7:
			var owner:=DebrisDeath.new()
			if not owner.configure(bindings,resources,_construction,id):return reject(owner.error)
			owners.append(owner)
			continue
		var seed: Dictionary=_initial_actors[id].duplicate(true)
		seed.merge(_identity,true)
		var owner:=Death.new()
		if not owner.configure_contract(bindings,resources,_construction,seed):return reject(owner.error)
		owners.append(owner)
	var accounting:=Accounting.new()
	if not accounting.configure_contract(bindings,_construction):return reject(accounting.error)
	_destruction=owners;_accounting=accounting;_death_resources=resources
	return true

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted,reputation: Dictionary) -> bool:
	clear()
	if not construction is Construction:return reject("Convoy control requires its generated encounter")
	var rules:=Convoy.lifecycle(bindings,construction.snapshot())
	if rules.is_empty():return reject("Unsupported convoy control lifecycle")
	var combat:=Combat.new()
	if not combat.configure_convoy(bindings,catalogues,construction,equipment,reputation):return reject(combat.error)
	var guidance:=[];var flight:=[]
	for id in int(rules.actor_count):
		if rules.actors[id].population_group=="capital":
			var motion:=FreightMotion.new()
			if not motion.configure_convoy(bindings,id):return reject(motion.error)
			guidance.append(null);flight.append(motion)
		else:
			var controller:=Guidance.new();var motion:=Flight.new()
			if not controller.configure_convoy(bindings,catalogues,construction,id) or not motion.configure(bindings,combat.snapshot().actors[id].body_pose):return reject(controller.error+motion.error)
			guidance.append(controller);flight.append(motion)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(rules.campaign_cursor),"rank":int(rules.rank)}
	_flight_identity=RefCounted.new();_rules=rules;_death_rules=rules;_convoy=true
	_combat=combat;_guidance=guidance;_flight=flight;_random=construction.snapshot().random_state.duplicate(true)
	_initial_actors=construction.snapshot().actors.duplicate(true)
	_bindings=bindings;_construction=construction;_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	return true

func _set_convoy_destruction(bindings: RefCounted,resources: RefCounted,capital_resources: RefCounted) -> bool:
	if _started or _accounting!=null or bindings!=_bindings or not resources is DeathResources:return reject("Prepare convoy destruction once before flight starts")
	var owners:=[]
	for id in _initial_actors.size():
		var owner: RefCounted
		if _initial_actors[id].population_group=="capital":
			owner=FreightDeath.new()
			if not owner.configure_convoy(bindings,capital_resources,_construction,id):return reject(owner.error)
		else:
			owner=Death.new()
			var seed: Dictionary=_initial_actors[id].duplicate(true);seed.merge(_identity,true)
			if not owner.configure_convoy(bindings,resources,_construction,seed):return reject(owner.error)
		owners.append(owner)
	var accounting:=Accounting.new()
	if not accounting.configure_convoy(bindings,_construction):return reject(accounting.error)
	_destruction=owners;_accounting=accounting;_death_resources=resources
	return true

func configure_alioth_attack(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,equipment: RefCounted,reputation: Dictionary) -> bool:
	clear()
	if not construction is Construction:return reject("Alioth control requires its generated encounter")
	var rules:=Alioth.lifecycle(bindings,construction.snapshot())
	if rules.is_empty():return reject("Unsupported Alioth control lifecycle")
	var combat:=Combat.new()
	if not combat.configure_alioth_attack(bindings,catalogues,construction,equipment,reputation):return reject(combat.error)
	var guidance:=[];var flight:=[]
	for id in int(rules.actor_count):
		if rules.actors[id].population_group=="freighter":
			var motion:=FreightMotion.new()
			if not motion.configure_alioth_attack(bindings,construction,id):return reject(motion.error)
			guidance.append(null);flight.append(motion)
		else:
			var controller:=Guidance.new();var motion:=Flight.new()
			if not controller.configure_alioth_attack(bindings,catalogues,construction,id) or not motion.configure(bindings,combat.snapshot().actors[id].body_pose):return reject(controller.error+motion.error)
			guidance.append(controller);flight.append(motion)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(rules.campaign_cursor),"rank":int(rules.rank)}
	_flight_identity=RefCounted.new();_rules=rules;_death_rules=rules;_alioth=true
	_combat=combat;_guidance=guidance;_flight=flight;_random=construction.snapshot().random_state.duplicate(true)
	_initial_actors=construction.snapshot().actors.duplicate(true)
	_alioth_sequence={"revision":0,"elapsed_ms":0,"phase":AliothSequence.Stage.ATTACK}
	_launch_pending.resize(_initial_actors.size());_launch_pending.fill(false)
	_bindings=bindings;_construction=construction;_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	return true

func configure_kappa_rescue(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,reputation: Dictionary) -> bool:
	clear()
	if not construction is Construction:return reject("Kappa control requires its generated encounter")
	var rules:=Kappa.lifecycle(bindings,construction.snapshot())
	if rules.is_empty():return reject("Unsupported Kappa control lifecycle")
	var combat:=Combat.new()
	if not combat.configure_kappa_rescue(bindings,catalogues,construction,reputation):return reject(combat.error)
	var guidance:=[];var flight:=[]
	for id in int(rules.actor_count):
		var controller:=Guidance.new();var motion:=Flight.new()
		if not controller.configure_kappa_rescue(bindings,catalogues,construction,id) or not motion.configure(bindings,combat.snapshot().actors[id].body_pose):return reject(controller.error+motion.error)
		guidance.append(controller);flight.append(motion)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(rules.campaign_cursor),"rank":int(rules.rank)}
	_flight_identity=RefCounted.new();_rules=rules;_death_rules=rules;_kappa=true
	_combat=combat;_guidance=guidance;_flight=flight;_random=construction.snapshot().random_state.duplicate(true)
	_initial_actors=construction.snapshot().actors.duplicate(true)
	_bindings=bindings;_construction=construction;_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	return true

func _set_kappa_destruction(bindings: RefCounted,resources: RefCounted) -> bool:
	if _started or _accounting!=null or bindings!=_bindings or not resources is DeathResources:return reject("Prepare Kappa destruction once before flight starts")
	var owners:=[]
	for id in _initial_actors.size():
		var owner:=Death.new()
		var seed: Dictionary=_initial_actors[id].duplicate(true);seed.merge(_identity,true)
		if not owner.configure_kappa_rescue(bindings,resources,_construction,seed):return reject(owner.error)
		owners.append(owner)
	var accounting:=Accounting.new()
	if not accounting.configure_kappa_rescue(bindings,_construction):return reject(accounting.error)
	_destruction=owners;_accounting=accounting;_death_resources=resources
	return true

func _validate_kappa_combat(body: Dictionary) -> bool:
	if body.get("provocation",{}).get("station_id")!=int(_rules.station_id):return reject("Kappa combat belongs to another station")
	var prior: Array=_combat.snapshot().actors
	for id in prior.size():
		for key in ["actor_id","actor_kind","hull_catalogue_id","rank","difficulty","kappa_rescue","permanent_friendly","scenery"]:
			if body.actors[id].get(key)!=prior[id].get(key):return reject("Kappa combat changed its constructed cast")
		if body.actors[id].systems_hit_serial<prior[id].systems_hit_serial or (prior[id].script_hostile and not body.actors[id].script_hostile):return reject("Kappa combat lost retained hits or mission hostility")
	return true

func evaluate_alioth_sequence(owner: RefCounted,weapons: RefCounted,shared_random_state: Variant=null) -> Dictionary:
	error=""
	if not _alioth or _accounting==null or not owner is AliothSequence or not weapons is Weapons:return fail("Alioth sequence requires its complete retained combat owners")
	var sequence: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if sequence.get(key)!=_identity[key]:return fail("Alioth sequence belongs to another encounter")
	if sequence.get("revision")!=_alioth_sequence.revision+1 or sequence.elapsed_ms<_alioth_sequence.elapsed_ms or sequence.elapsed_ms>_alioth_sequence.elapsed_ms+_max_ms or sequence.phase<_alioth_sequence.phase or sequence.phase>_alioth_sequence.phase+1:return fail("Alioth sequence repeated or skipped a retained frame")
	# Player contacts and effects can consume the shared stream between actor
	# passes. The owning frame supplies that current state without an extra tick.
	var random:=Random.new()
	if not random.restore(_random if shared_random_state==null else shared_random_state):return fail(random.error)
	if sequence.get("frame",{}).get("input_random_state")!=random.snapshot():return fail("Alioth sequence lost the current world random state")
	var staged:=fork_for_frame();var next_weapons: RefCounted=weapons.fork_for_frame()
	if not next_weapons.apply_alioth_sequence(owner):return fail(next_weapons.error)
	for row in sequence.frame.actor_overrides:
		var id: Variant=row.get("actor_id")
		if id not in [3,4,5,6] or not row.get("clear_targets",false):return fail("Alioth sequence changed the wrong ship")
		if not staged._guidance[id].apply_alioth_escape(owner) or not staged._flight[id].apply_scripted_pose(row.body_pose):return fail(staged._guidance[id].error+staged._flight[id].error)
		var prior: Dictionary=staged._combat.snapshot().actors[id]
		if staged._destruction[id].snapshot().phase!="ready":
			if not staged._destruction[id].apply_alioth_escape(owner):return fail(staged._destruction[id].error)
		else:staged._launch_pending[id]=true
		# Body placement happens immediately. The ordinary pass refreshes the
		# collision/statistics pose and preserves its existing bank history.
		if not staged._combat.set_pose(id,prior.pose,row.body_pose):return fail(staged._combat.error)
	if not staged._combat.apply_alioth_sequence(owner):return fail(staged._combat.error)
	staged._alioth_sequence={"revision":sequence.revision,"elapsed_ms":sequence.elapsed_ms,"phase":sequence.phase}
	staged._random=sequence.frame.random_state.duplicate(true)
	return {"controller":staged,"weapons":next_weapons,"random_state":staged._random.duplicate(true)}

func _set_alioth_destruction(bindings: RefCounted,resources: RefCounted,capital_resources: RefCounted) -> bool:
	if _started or _accounting!=null or bindings!=_bindings or not resources is DeathResources:return reject("Prepare Alioth destruction once before flight starts")
	var owners:=[]
	for id in _initial_actors.size():
		var owner: RefCounted
		if _initial_actors[id].population_group=="freighter":
			owner=FreightDeath.new()
			if not owner.configure_alioth_attack(bindings,capital_resources,_construction,id):return reject(owner.error)
		else:
			owner=Death.new()
			var seed: Dictionary=_initial_actors[id].duplicate(true);seed.merge(_identity,true)
			if not owner.configure_alioth_attack(bindings,resources,_construction,seed):return reject(owner.error)
		owners.append(owner)
	var accounting:=Accounting.new()
	if not accounting.configure_alioth_attack(bindings,_construction):return reject(accounting.error)
	_destruction=owners;_accounting=accounting;_death_resources=resources
	return true


func apply_convoy_capture(capture: RefCounted,combat: RefCounted=null) -> bool:
	error=""
	if not _convoy:return reject("This controller has no convoy capture context")
	if combat!=null and not combat is Combat:return reject("Capture requires the current native combat group")
	var group: RefCounted=(_combat if combat==null else combat).fork_for_frame();var flight:=_flight.duplicate()
	var body: Dictionary=group.snapshot()
	if not _validate_convoy_combat(body):return false
	if not group.apply_convoy_capture(capture):return reject(group.error)
	for id in _initial_actors.size():
		if _initial_actors[id].population_group!="capital":continue
		flight[id]=_flight[id].fork_for_frame()
		if not flight[id].apply_capture(capture):return reject(flight[id].error)
	_combat=group;_flight=flight
	return true

func _validate_convoy_combat(body: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if body.get(key)!=_identity[key]:return reject("Convoy combat belongs to another encounter")
	if body.get("provocation",{}).get("station_id")!=int(_rules.station_id) or body.get("actors",[]).size()!=_initial_actors.size():return reject("Convoy combat lost its source population")
	var prior: Array=_combat.snapshot().actors
	for id in prior.size():
		for key in ["actor_id","actor_kind","hull_catalogue_id","rank","difficulty","convoy_phase","convoy_script_retired"]:
			if body.actors[id].get(key)!=prior[id].get(key):return reject("Convoy combat changed its construction or retained capture phase")
	return true

func _validate_alioth_combat(body: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if body.get(key)!=_identity[key]:return reject("Alioth combat belongs to another encounter")
	if body.get("provocation",{}).get("station_id")!=int(_rules.station_id) or body.get("actors",[]).size()!=_initial_actors.size():return reject("Alioth combat lost its source population")
	var prior: Array=_combat.snapshot().actors
	for id in prior.size():
		for key in ["actor_id","actor_kind","hull_catalogue_id","rank","difficulty","alioth_phase","alioth_elapsed_ms","alioth_script_retired"]:
			if body.actors[id].get(key)!=prior[id].get(key):return reject("Alioth combat changed its construction or retained sequence")
	return true

func set_destruction(bindings: RefCounted, resources: RefCounted,freighter_resources: RefCounted=null) -> bool:
	error=""
	if _kappa:return _set_kappa_destruction(bindings,resources)
	if _alioth:return _set_alioth_destruction(bindings,resources,freighter_resources)
	if _convoy:return _set_convoy_destruction(bindings,resources,freighter_resources)
	if _contract:return _set_contract_destruction(bindings,resources)
	if _ambient:return _set_ambient_destruction(bindings,resources,freighter_resources)
	if _local_patrol and not _combat.has_local_reactions():return reject("Local traffic cannot borrow training destruction or accounting")
	if _identity.is_empty() or _started or _accounting!=null or bindings==null or not resources is DeathResources or not DeathRules.parameters(bindings.combat_training_destruction):return reject("Prepare training destruction once before the first actor pass")
	for key in ["base_content_id","binding_id"]:
		if bindings.get(key)!=_identity[key]:return reject("Training destruction belongs to another content identity")
	var owners:=[]
	for id in int(_rules.actor_count):
		var seed: Dictionary=_initial_actors[id].duplicate(true)
		seed.merge(_identity)
		var owner:=Death.new()
		var ready: bool=owner.configure_local_traffic(bindings,resources,seed,_death_rules) if _local_patrol else owner.configure_combat_training(bindings,resources,seed)
		if not ready:return reject(owner.error)
		owners.append(owner)
	var accounting:=Accounting.new()
	var ready: bool=accounting.configure_local_traffic(bindings,_death_rules) if _local_patrol else accounting.configure_combat_training(bindings)
	if not ready:return reject(accounting.error)
	_destruction=owners;_accounting=accounting
	if not _local_patrol:_death_rules=bindings.combat_training_destruction.duplicate(true)
	return true

func _set_ambient_destruction(bindings: RefCounted,resources: RefCounted,freighter_resources: RefCounted) -> bool:
	if _started or _accounting!=null or bindings!=_bindings or not resources is DeathResources:return reject("Prepare mixed destruction once before traffic starts")
	var owners:=[]
	for id in _initial_actors.size():
		var owner: RefCounted
		if _initial_actors[id].population_group=="freighter":
			owner=FreightDeath.new()
			if not owner.configure(bindings,freighter_resources,_construction,id):return reject(owner.error)
		else:
			owner=Death.new()
			if not owner.configure_ambient(bindings,resources,_construction,_ambient_seed(id)):return reject(owner.error)
		owners.append(owner)
	var accounting:=Accounting.new()
	if not accounting.configure_ambient(bindings,_construction):return reject(accounting.error)
	_destruction=owners;_accounting=accounting;_death_resources=resources
	return true

func _ambient_seed(id: int) -> Dictionary:
	var seed: Dictionary=_initial_actors[id].duplicate(true)
	seed.merge(_identity,true)
	var actor: Dictionary=_combat.snapshot().actors[id]
	seed.body_pose=actor.body_pose;seed.spawn_generation=actor.spawn_generation
	seed.cargo=_cargo[id].duplicate(true)
	return seed

func evaluate_ambient_world_logic(delta_ms: Variant,combat: RefCounted,random_state: Dictionary) -> Dictionary:
	error=""
	if not _ambient or _launch_clock==null or _accounting==null or not combat is Combat:return fail("World traffic logic requires its prepared mixed controller")
	var incoming: Dictionary=combat.snapshot()
	var generations: Array=_accounting.snapshot().spawn_generations
	if not incoming.get("actors") is Array or incoming.actors.size()!=generations.size():return fail("Incoming traffic population changed")
	for id in generations.size():
		if not incoming.actors[id] is Dictionary or not incoming.actors[id].get("spawn_generation") is int or incoming.actors[id].spawn_generation!=generations[id]:return fail("World logic received an earlier traffic instance")
	var staged:=fork_for_frame();staged._combat=combat.fork_for_frame()
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	staged._random=random.snapshot()
	var request: Dictionary=staged._launch_clock.advance(delta_ms,staged._combat.snapshot())
	if request.is_empty():return fail(staged._launch_clock.error)
	var ids:=[]
	if request.actor_id>=0:ids.append(request.actor_id)
	ids.append_array(request.patrol_actor_ids)
	for id in ids:
		var before: Dictionary=staged._combat.snapshot().actors[id]
		var retired: RefCounted=staged._destruction[id] if before.vitals.hull==0 else null
		if not staged._combat.relaunch_ambient(id,_bindings,retired):return fail(staged._combat.error)
		var actor: Dictionary=staged._combat.snapshot().actors[id]
		if not staged._accounting.register_relaunch(actor) or not staged._guidance[id].relaunch_ambient(actor) or not staged._flight[id].apply_scripted_pose(actor.body_pose):return fail(staged._accounting.error+staged._guidance[id].error+staged._flight[id].error)
		var cargo: Dictionary=_construction.sample_relaunch_cargo(staged._random)
		if cargo.is_empty():return fail(_construction.error)
		staged._cargo[id]=cargo.cargo;staged._random=cargo.random_state
		var death:=Death.new()
		if not death.configure_ambient(_bindings,_death_resources,_construction,staged._ambient_seed(id)):return fail(death.error)
		staged._destruction[id]=death;staged._launch_pending[id]=true
	return {"controller":staged,"combat":staged._combat,"random_state":staged._random.duplicate(true),"relaunches":ids,"clock":request}

func advance(delta_ms: Variant, player: Dictionary, combat: RefCounted=null, random_state: Variant=null) -> Dictionary:
	error=""
	if not _contract_result.is_empty() and _contract_result.mode!=0:return fail("Acknowledge the contract result before advancing flight")
	if _identity.is_empty() or (combat!=null and not combat is Combat):return fail("Configure combat-training control before advancing")
	if (_ambient or _contract or _convoy or _alioth or _kappa) and _accounting==null:return fail("Actor control requires its prepared destruction and accounting")
	if (not _destruction.is_empty() or _local_patrol or _contract or _convoy or _alioth or _kappa) and (not Vitals.integer(delta_ms) or delta_ms>_max_ms):return fail("Invalid ordinary actor frame duration")
	if _local_patrol and combat!=null and (not _combat.has_local_reactions() or not combat.has_local_reactions()):return fail("Local traffic damage and retaliation are not connected")
	var staged: RefCounted=fork_for_frame()
	if combat!=null:staged._combat=combat.fork_for_frame()
	if random_state!=null:
		var random:=Random.new()
		if not random.restore(random_state):return fail(random.error)
		staged._random=random.snapshot()
	var decisions:=[];var firing:=[];var death_events:=[]
	var body: Dictionary=staged._combat.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if body.get(key)!=_identity[key]:return fail("Incoming combat bodies belong to another encounter")
	if not body.get("actors") is Array or body.actors.size()!=int(_rules.actor_count):return fail("Incoming combat population changed")
	if _convoy and not _validate_convoy_combat(body):return {}
	if _alioth and not _validate_alioth_combat(body):return {}
	if _kappa and not _validate_kappa_combat(body):return {}
	if _contract and body.get("contract_encounter")!=_construction.snapshot().contract_encounter:return fail("Incoming combat belongs to another accepted contract")
	if _contract and body.get("contract_settlement",{})!=_combat.snapshot().get("contract_settlement",{}):return fail("Incoming combat lost its acknowledged result standing")
	if _local_patrol and _combat.has_local_reactions() and body.get("provocation",{}).get("station_id")!=int(_rules.station_id):return fail("Incoming local combat belongs to another station")
	for id in int(_rules.actor_count):
		body=staged._combat.snapshot()
		if (_convoy and body.actors[id].get("convoy_script_retired",false)) or (_alioth and body.actors[id].get("alioth_script_retired",false)):
			# The story directly deactivates these actors. A previously running
			# breakup stops too; neither path starts a new death/accounting event.
			decisions.append({"actor_id":id,"fire_requested":false,"script_retired":true})
			continue
		if _contract and int(_rules.mission.kind)==7:
			var debris: Dictionary=staged._advance_debris(id,int(delta_ms))
			if debris.is_empty():return fail(staged.error)
			decisions.append(debris.decision)
			if debris.has("death"):death_events.append(debris.death)
			continue
		if ((_ambient or _alioth) and _initial_actors[id].population_group=="freighter") or (_convoy and _initial_actors[id].population_group=="capital"):
			var freight: Dictionary=staged._advance_freighter(id,int(delta_ms))
			if freight.is_empty():return fail(staged.error)
			decisions.append(freight.decision)
			if freight.has("death"):death_events.append(freight.death)
			continue
		if body.actors[id].vitals.hull==0 and _destruction.is_empty():return fail("Combat-training destruction is not connected")
		var life: Dictionary={} if staged._destruction.is_empty() else staged._destruction[id].snapshot()
		var motion: Dictionary=staged._flight[id].snapshot()
		if not life.is_empty():
			var old: Dictionary=body.actors[id]
			if life.phase=="ready":
				var departing: bool=_ambient and old.get("travel_cycle",-1)>=0 and old.actor_mode in [4,6]
				var placed: bool=(_ambient or _alioth) and staged._launch_pending[id]
				if old.body_pose!=motion.root_pose or (not departing and not (_alioth and placed) and old.pose!=(motion.root_pose if placed else staged._flight[id].systems_statistics_pose() if _kappa else motion.pose)):return fail("Combat pose disagrees with retained flight")
				if placed:
					if not staged._combat.set_pose(id,motion.pose,motion.root_pose):return fail(staged._combat.error)
					staged._launch_pending[id]=false
			else:
				if old.body_pose!=life.pose or old.pose!=life.statistics_pose or old.vitals.hull!=0 or old.actor_mode!=life.mode or old.active!=(life.phase!="retired"):return fail("Training body disagrees with retained destruction")
			if staged._destruction[id].retires_before_update():
				var retired: Dictionary=staged._destruction[id].advance(delta_ms,staged._random)
				if retired.is_empty() or not staged._combat.apply_destruction(id,retired.state):return fail(staged._destruction[id].error+staged._combat.error)
				staged._random=retired.random_state.duplicate(true);death_events.append(retired)
				decisions.append({"actor_id":id,"dying":true,"retired":true})
				continue
			if life.phase!="ready":
				if not staged._combat.set_pose(id,life.pose*Transform3D(life.bank_basis,Vector3.ZERO),life.pose):return fail(staged._combat.error)
		if _kappa and not staged._combat.advance_systems(id,delta_ms):return fail(staged._combat.error)
		if not staged._combat.refresh_hostility(id):return fail(staged._combat.error)
		body=staged._combat.snapshot()
		var actor: Dictionary=body.actors[id]
		var root: Transform3D=motion.root_pose if life.is_empty() or life.phase=="ready" else life.pose
		var decision: Dictionary=staged._guidance[id].update(delta_ms,actor,root,player,staged._random,body.actors)
		if decision.is_empty():return fail(staged._guidance[id].error)
		if decision.get("dying",false):
			if life.is_empty():return fail("Training death lacks its prepared resources")
			var accounting_event: Dictionary={}
			if life.phase=="ready":
				accounting_event=staged._accounting.record(actor)
				if accounting_event.is_empty():return fail(staged._accounting.error)
				if not staged._destruction[id].capture(root,decision.speed,staged._flight[id].bank_basis()):return fail(staged._destruction[id].error)
			var death: Dictionary=staged._destruction[id].advance(delta_ms,decision.random_state)
			if death.is_empty() or not staged._combat.apply_destruction(id,death.state):return fail(staged._destruction[id].error+staged._combat.error)
			death.accounting_event=accounting_event;death_events.append(death)
			staged._random=death.random_state.duplicate(true);decisions.append(decision)
			continue
		var applied: bool=staged._combat.apply_kappa_guidance(decision) if _kappa else staged._combat.apply_alioth_guidance(decision) if _alioth else staged._combat.apply_convoy_guidance(decision) if _convoy else (staged._combat.apply_contract_guidance(decision) if _contract else (staged._combat.apply_ambient_guidance(decision) if _ambient else (staged._combat.apply_local_patrol_guidance(decision) if _local_patrol else staged._combat.apply_combat_training_guidance(_rules,decision))))
		if not applied:return fail(staged._combat.error)
		if _local_patrol and not staged._combat.has_local_reactions() and decision.fire_requested:return fail("Local traffic weapon control is not connected")
		if decision.fire_requested:firing.append({"actor_id":id,"target_actor_id":int(decision.target_actor_id),"pose":actor.pose})
		var moved: Dictionary=staged._flight[id].snapshot()
		if decision.get("traffic_departure",false):
			moved=staged._flight[id].advance_forward_only(delta_ms,decision.speed)
			if moved.is_empty() or not staged._combat.apply_ambient_departure_pose(id,moved.root_pose):return fail(staged._flight[id].error+staged._combat.error)
		elif decision.get("traffic_waiting",false):pass
		elif decision.travel_enabled or decision.steering_enabled:
			moved=staged._flight[id].advance_with_systems(delta_ms,decision.direction,decision.speed,decision.steering_enabled,decision.travel_enabled,staged._combat.systems_for_frame(id)) if _kappa else staged._flight[id].advance(delta_ms,decision.direction,decision.speed,decision.steering_enabled,decision.travel_enabled)
			if moved.is_empty():return fail(staged._flight[id].error)
		if not decision.get("traffic_departure",false) and not decision.get("traffic_waiting",false) and not staged._combat.set_pose(id,staged._flight[id].systems_statistics_pose() if _kappa else moved.pose,moved.root_pose):return fail(staged._combat.error)
		staged._random=decision.random_state.duplicate(true);decisions.append(decision)
	_combat=staged._combat;_guidance=staged._guidance;_flight=staged._flight;_random=staged._random
	_destruction=staged._destruction;_accounting=staged._accounting;_started=true
	_launch_pending=staged._launch_pending
	if not _contract_result.is_empty() and not _scene_clocked:
		_contract_result.clock_ms+=int(delta_ms);_contract_result.elapsed_ms+=int(delta_ms)
	var result:=_identity.duplicate()
	result.merge({"decisions":decisions,"firing_requests":firing,"random_state":_random.duplicate(true),"combat":_combat.snapshot()})
	if not _destruction.is_empty():result.death_events=death_events;result.defeat_status=defeat_status()
	return result

func _advance_debris(id: int,delta_ms: int) -> Dictionary:
	var actor: Dictionary=_combat.snapshot().actors[id]
	var life: Dictionary=_destruction[id].snapshot()
	var credit:={}
	if actor.vitals.hull==0 and life.phase=="ready":
		credit=_accounting.record(actor)
		if credit.is_empty():return fail(_accounting.error)
	var death: Dictionary=_destruction[id].advance(delta_ms,_random,actor)
	if death.is_empty():return fail(_destruction[id].error)
	if death.state.phase=="destroyed" and not _combat.apply_debris_destruction(id,_destruction[id]):return fail(_combat.error)
	_random=death.random_state
	var result:={"decision":{"actor_id":id,"fire_requested":false,"dying":actor.vitals.hull==0,"stationary":true}}
	if death.started:
		death.accounting_event=credit;result.death=death
	return result

func _advance_freighter(id: int,delta_ms: int) -> Dictionary:
	if not _combat.refresh_hostility(id):return fail(_combat.error)
	var actor: Dictionary=_combat.snapshot().actors[id]
	var life: Dictionary=_destruction[id].snapshot()
	var decision:={"actor_id":id,"fire_requested":false,"dying":actor.vitals.hull==0}
	if life.phase=="ready":
		var motion: Dictionary=_flight[id].snapshot()
		if actor.body_pose!=motion.body_pose or actor.pose!=motion.statistics_pose or not actor.active or actor.actor_mode!=0:return fail("Freighter body disagrees with retained cruise")
		if not _flight[id].update(delta_ms,true):return fail(_flight[id].error)
		motion=_flight[id].snapshot()
		if not _combat.set_pose(id,motion.statistics_pose,motion.body_pose):return fail(_combat.error)
		actor=_combat.snapshot().actors[id]
		# Freighter cruise precedes its hull test in the ordinary actor pass.
		# A lethal contact therefore still permits this last displacement.
		if actor.vitals.hull>0:return {"decision":decision}
	var credit:={}
	if life.phase=="ready":
		credit=_accounting.record(actor)
		if credit.is_empty():return fail(_accounting.error)
	elif actor.body_pose!=life.pose or actor.pose!=life.statistics_pose or actor.actor_mode!=life.mode or actor.active!=life.active or actor.vitals.hull!=0:return fail("Freighter body disagrees with retained destruction")
	var death: Dictionary=_destruction[id].advance(delta_ms,_random,actor if life.phase=="ready" else {})
	if death.is_empty() or not _combat.apply_freighter_destruction(id,_destruction[id]):return fail(_destruction[id].error+_combat.error)
	death.accounting_event=credit;_random=death.random_state
	return {"decision":decision,"death":death}

func defeat_status() -> Dictionary:
	if _convoy or _alioth or _kappa:return {}
	if _contract:return _contract_defeat_status()
	if _death_rules.is_empty() or _local_patrol:return {}
	var rule: Dictionary=_death_rules.defeat_condition
	var count:=0
	var actors: Array=_combat.snapshot().actors
	for id in range(int(rule.begin),int(rule.end)):
		if actors[id].actor_mode==int(rule.actor_mode):count+=1
	return {"kind":int(rule.kind),"defeated":count,"required":int(rule.end)-int(rule.begin),"satisfied":count==int(rule.end)-int(rule.begin)}

func _contract_defeat_status() -> Dictionary:
	if _accounting==null or _contract_result.get("retired",false):return {}
	if int(_rules.mission.kind)==7:
		var actors: Array=_combat.snapshot().actors
		var count:=actors.filter(func(actor):return actor.actor_mode==int(_rules.lifecycle.destroyed_mode)).size()
		return {"kind":7,"defeated":count,"required":actors.size(),"satisfied":count==actors.size(),"failed":false}
	var rule: Dictionary=_rules.lifecycle.objectives
	var actors: Array=_combat.snapshot().actors
	var challenge: bool=int(_rules.mission.kind)==12
	var begin:=int(rule.challenge_first_actor) if challenge else 0
	var count:=0
	for id in range(begin,actors.size()):
		if actors[id].actor_kind==int(rule.challenge_actor_kind) and actors[id].actor_mode==int(rule.destroyed_mode):count+=1
	var required:=actors.size()-begin
	var totals: Dictionary=_accounting.snapshot().counter_deltas
	var majority: bool=totals.world_player_kills>totals.world_other_kills
	return {"kind":int(rule.challenge_success_kind if challenge else rule.pirate_kind),
		"failure_kind":int(rule.challenge_failure_kind) if challenge else -1,
		"defeated":count,"required":required,"satisfied":count==required and (not challenge or majority),
		"failed":challenge and count==required and not majority}

func sample_scene_clock(world_ms: int,poll_ms: int) -> bool:
	error=""
	if _contract_result.is_empty():return true
	if _contract_result.mode!=0 or world_ms<int(_contract_result.elapsed_ms) or world_ms>2147483647 or poll_ms<0 or poll_ms>2147483647:return reject("The scene lost its retained contract clock")
	if not _scene_clocked and (_started or _contract_result.elapsed_ms!=0):return reject("Connect the scene clock before the first actor update")
	_scene_clocked=true;_contract_result.elapsed_ms=world_ms;_contract_result.clock_ms=poll_ms
	return true

func poll_contract_result(radio_active: bool,periodic_poll_allowed: bool=true) -> Dictionary:
	error=""
	if _contract_result.is_empty() or _accounting==null:return fail("Contract flight results are unavailable")
	if _contract_result.retired or _contract_result.mode!=0:return _contract_result.duplicate(true)
	var rules: Dictionary=_bindings.early_contracts.flight_results
	var status:=defeat_status()
	var mode:=0
	if periodic_poll_allowed and status.satisfied and _contract_result.clock_ms>=int(rules.success_poll_milliseconds) and not radio_active:
		mode=int(rules.success_result_mode)
	elif status.failed:mode=int(rules.failure_result_mode)
	elif periodic_poll_allowed and int(_rules.mission.kind)==7 and _contract_result.clock_ms>=int(rules.success_poll_milliseconds) and _contract_result.elapsed_ms>int(_rules.lifecycle.deadline_milliseconds):
		mode=int(rules.failure_result_mode)
	if mode!=0:
		if not _combat.open_contract_result(_bindings,mode):return fail(_combat.error)
		_contract_result.mode=mode
		if int(_rules.mission.kind)==7 and mode==int(rules.failure_result_mode):_contract_result.clock_ms=0
	elif periodic_poll_allowed and _contract_result.clock_ms>=int(rules.success_poll_milliseconds):
		_contract_result.clock_ms=0
	return _contract_result.duplicate(true)

func acknowledge_contract_result() -> bool:
	error=""
	if _contract_result.is_empty() or _contract_result.mode==0 or _contract_result.retired:return reject("No contract flight result awaits acknowledgement")
	if not _combat.retire_contract_result():return reject(_combat.error)
	_contract_result.mode=0;_contract_result.retired=true
	return true

func evaluate(combat: RefCounted, weapons: RefCounted, milliseconds: int, player: Dictionary, random_state: Dictionary) -> Dictionary:
	error=""
	if _local_patrol and not _combat.has_local_reactions():return fail("Local traffic weapon control is not connected")
	if not weapons is Weapons:return fail("Training actor updates require their retained weapon pools")
	var staged:=fork_for_frame(false);var next_weapons: RefCounted=weapons.fork_for_frame()
	var operation: Dictionary=staged.advance(milliseconds,player,combat,random_state)
	if operation.is_empty():return fail(staged.error)
	# These ordinary NPC shots consume no random values and cannot contact
	# anything until the next weapon phase. Preserve each pre-motion pose and
	# actor order while committing their independent pools with the whole pass.
	var fired: Dictionary=next_weapons.fire_combat_training(staged._combat,operation.firing_requests)
	if fired.is_empty():return fail(next_weapons.error)
	var events:=[]
	for id in operation.decisions.size():
		var event:={"actor_id":id,"decision":operation.decisions[id],"firing":{},"movement":{} if staged._flight[id]==null else staged._flight[id].snapshot()}
		for fire in fired.actors:
			if fire.actor_id==id:event.firing={"actors":[fire]}
		for death in operation.get("death_events",[]):
			if death.state.actor_id==id:
				event.destruction=death
				if not death.get("accounting_event",{}).is_empty():event.death_accounting=death.accounting_event
		events.append(event)
	return {"controller":staged,"combat":staged._combat,"weapons":next_weapons,"random_state":operation.random_state,"actors":events}

func destruction_owner(actor_id: int) -> RefCounted:
	return null if actor_id<0 or actor_id>=_destruction.size() else _destruction[actor_id].fork_for_frame()

func combat_owner() -> RefCounted:
	return null if _combat==null else _combat.fork_for_frame()

func flight_identity() -> RefCounted:
	return _flight_identity

func snapshot() -> Dictionary:
	if _identity.is_empty():return {}
	var result:=_identity.duplicate()
	result.merge({"combat":_combat.snapshot(),"guidance":_guidance.map(func(owner):return {} if owner==null else owner.snapshot()),
		"flight":_flight.map(func(owner):return {} if owner==null else owner.snapshot()),"random_state":_random.duplicate(true)})
	if _local_patrol:result.support_state="ordinary_combat" if _combat.has_local_reactions() else "patrol_only"
	if _contract:result.support_state="contract_combat"
	if _convoy:result.support_state="convoy_combat"
	if _kappa:result.support_state="kappa_combat"
	if _alioth:result.support_state="alioth_combat";result.alioth_sequence=_alioth_sequence.duplicate(true)
	if not _contract_result.is_empty():result.contract_result=_contract_result.duplicate(true)
	if _ambient:result.traffic_clock=_launch_clock.snapshot();result.cargo=_cargo.duplicate(true)
	if _accounting!=null:
		result.destruction=_destruction.map(func(owner):return owner.snapshot())
		result.accounting=_accounting.snapshot();result.defeat_status=defeat_status()
	return result

func fork_for_frame(copy_motion:=true) -> RefCounted:
	var copy: RefCounted=get_script().new()
	# Configuration is immutable after setup; only live state needs a private copy.
	copy._identity=_identity.duplicate();copy._rules=_rules;copy._random=_random.duplicate(true)
	copy._combat=null if _combat==null else _combat.fork_for_frame()
	# Clock/result observations retain motion. advance() always takes a full
	# private motion copy before changing guidance, flight or destruction.
	copy._guidance=_guidance.map(func(owner):return null if owner==null else owner.fork_for_frame()) if copy_motion else _guidance
	copy._flight=_flight.map(func(owner):return null if owner==null else owner.fork_for_frame()) if copy_motion else _flight
	copy._initial_actors=_initial_actors;copy._death_rules=_death_rules
	copy._destruction=_destruction.map(func(owner):return owner.fork_for_frame()) if copy_motion else _destruction
	copy._accounting=null if _accounting==null else _accounting.fork_for_frame()
	copy._started=_started;copy._max_ms=_max_ms
	copy._local_patrol=_local_patrol;copy._contract=_contract
	copy._convoy=_convoy;copy._alioth=_alioth;copy._kappa=_kappa
	copy._alioth_sequence=_alioth_sequence.duplicate(true)
	copy._ambient=_ambient;copy._bindings=_bindings;copy._construction=_construction;copy._death_resources=_death_resources
	copy._launch_clock=null if _launch_clock==null else _launch_clock.fork_for_frame()
	copy._cargo=_cargo.duplicate(true);copy._launch_pending=_launch_pending.duplicate()
	copy._contract_result=_contract_result.duplicate(true)
	copy._flight_identity=_flight_identity
	copy._scene_clocked=_scene_clocked
	return copy

func clear() -> void:
	error="";_identity={};_rules={};_combat=null;_guidance=[];_flight=[];_random={}
	_initial_actors=[];_destruction=[];_death_rules={};_accounting=null;_started=false;_max_ms=0;_local_patrol=false
	_ambient=false;_contract=false;_bindings=null;_construction=null;_death_resources=null;_launch_clock=null;_cargo=[];_launch_pending=[]
	_convoy=false;_alioth=false;_kappa=false
	_alioth_sequence={}
	_contract_result={}
	_flight_identity=null
	_scene_clocked=false

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
