extends RefCounted
## Four-actor guidance, motion and prepared cargo destruction. The encounter
## owns weapon updates, player input, radio and mission completion separately.
const Rules=preload("res://src/content/combat_training_control_definitions.gd")
const DeathRules=preload("res://src/content/combat_training_destruction_definitions.gd")
const DeathResources=preload("res://src/content/npc_destruction_resources.gd")
const Death=preload("res://src/simulation/npc_destruction.gd")
const Accounting=preload("res://src/simulation/npc_death_accounting.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Guidance=preload("res://src/simulation/opening_npc_guidance.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
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

func configure(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant) -> bool:
	clear()
	if bindings==null or not world is World or not Rules.parameters(bindings.combat_training_control):return reject("Combat-training control requires its verified world initialization")
	var combat:=Combat.new()
	if not combat.configure_combat_training(bindings,catalogues,world,rank,difficulty):return reject(combat.error)
	var random:=Random.new()
	if not random.restore(world.snapshot().get("random_state")):return reject(random.error)
	var guidance:=[];var flight:=[]
	for id in int(bindings.combat_training_control.actor_count):
		var controller:=Guidance.new()
		if not controller.configure_combat_training(bindings,catalogues,world,id,rank,difficulty):return reject(controller.error)
		var motion:=Flight.new()
		if not motion.configure(bindings,combat.snapshot().actors[id].body_pose):return reject(motion.error)
		guidance.append(controller);flight.append(motion)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(bindings.combat_training_control.campaign_cursor),"rank":rank}
	_rules=bindings.combat_training_control.duplicate(true)
	_combat=combat;_guidance=guidance;_flight=flight;_random=random.snapshot()
	_initial_actors=world.snapshot().npc_construction.actors.duplicate(true)
	_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	return true

func set_destruction(bindings: RefCounted, resources: RefCounted) -> bool:
	error=""
	if _identity.is_empty() or _started or not _destruction.is_empty() or bindings==null or not resources is DeathResources or not DeathRules.parameters(bindings.combat_training_destruction):return reject("Prepare training destruction once before the first actor pass")
	for key in ["base_content_id","binding_id"]:
		if bindings.get(key)!=_identity[key]:return reject("Training destruction belongs to another content identity")
	var owners:=[]
	for id in int(_rules.actor_count):
		var seed: Dictionary=_initial_actors[id].duplicate(true)
		seed.merge(_identity)
		var owner:=Death.new()
		if not owner.configure_combat_training(bindings,resources,seed):return reject(owner.error)
		owners.append(owner)
	var accounting:=Accounting.new()
	if not accounting.configure_combat_training(bindings):return reject(accounting.error)
	_destruction=owners;_accounting=accounting;_death_rules=bindings.combat_training_destruction.duplicate(true)
	return true

func advance(delta_ms: Variant, player: Dictionary, combat: RefCounted=null, random_state: Variant=null) -> Dictionary:
	error=""
	if _identity.is_empty() or (combat!=null and not combat is Combat):return fail("Configure combat-training control before advancing")
	if not _destruction.is_empty() and (not Vitals.integer(delta_ms) or delta_ms>_max_ms):return fail("Invalid training destruction frame duration")
	var staged: RefCounted=fork_for_frame()
	if combat!=null:staged._combat=combat.fork_for_frame()
	if random_state!=null:
		var random:=Random.new()
		if not random.restore(random_state):return fail(random.error)
		staged._random=random.snapshot()
	var decisions:=[];var firing:=[];var death_events:=[]
	for id in int(_rules.actor_count):
		var body: Dictionary=staged._combat.snapshot()
		for key in ["base_content_id","binding_id","campaign_cursor"]:
			if body.get(key)!=_identity[key]:return fail("Incoming combat bodies belong to another encounter")
		if body.actors.size()!=int(_rules.actor_count):return fail("Incoming combat population changed")
		if body.actors[id].vitals.hull==0 and _destruction.is_empty():return fail("Combat-training destruction is not connected")
		var life: Dictionary={} if staged._destruction.is_empty() else staged._destruction[id].snapshot()
		var motion: Dictionary=staged._flight[id].snapshot()
		if not life.is_empty():
			var old: Dictionary=body.actors[id]
			if life.phase=="ready":
				if old.body_pose!=motion.root_pose or old.pose!=motion.pose:return fail("Training combat pose disagrees with retained flight")
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
		if not staged._combat.apply_combat_training_guidance(_rules,decision):return fail(staged._combat.error)
		if decision.fire_requested:firing.append({"actor_id":id,"target_actor_id":int(decision.target_actor_id),"pose":actor.pose})
		var moved: Dictionary=staged._flight[id].snapshot()
		if decision.travel_enabled or decision.steering_enabled:
			moved=staged._flight[id].advance(delta_ms,decision.direction,decision.speed,decision.steering_enabled,decision.travel_enabled)
			if moved.is_empty():return fail(staged._flight[id].error)
		if not staged._combat.set_pose(id,moved.pose,moved.root_pose):return fail(staged._combat.error)
		staged._random=decision.random_state.duplicate(true);decisions.append(decision)
	_combat=staged._combat;_guidance=staged._guidance;_flight=staged._flight;_random=staged._random
	_destruction=staged._destruction;_accounting=staged._accounting;_started=true
	var result:=_identity.duplicate()
	result.merge({"decisions":decisions,"firing_requests":firing,"random_state":_random.duplicate(true),"combat":_combat.snapshot()})
	if not _destruction.is_empty():result.death_events=death_events;result.defeat_status=defeat_status()
	return result

func defeat_status() -> Dictionary:
	if _death_rules.is_empty():return {}
	var rule: Dictionary=_death_rules.defeat_condition
	var count:=0
	var actors: Array=_combat.snapshot().actors
	for id in range(int(rule.begin),int(rule.end)):
		if actors[id].actor_mode==int(rule.actor_mode):count+=1
	return {"kind":int(rule.kind),"defeated":count,"required":int(rule.end)-int(rule.begin),"satisfied":count==int(rule.end)-int(rule.begin)}

func combat_owner() -> RefCounted:
	return null if _combat==null else _combat.fork_for_frame()

func snapshot() -> Dictionary:
	if _identity.is_empty():return {}
	var result:=_identity.duplicate()
	result.merge({"combat":_combat.snapshot(),"guidance":_guidance.map(func(owner):return owner.snapshot()),
		"flight":_flight.map(func(owner):return owner.snapshot()),"random_state":_random.duplicate(true)})
	if not _destruction.is_empty():
		result.destruction=_destruction.map(func(owner):return owner.snapshot())
		result.accounting=_accounting.snapshot();result.defeat_status=defeat_status()
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._rules=_rules.duplicate(true);copy._random=_random.duplicate(true)
	copy._combat=null if _combat==null else _combat.fork_for_frame()
	copy._guidance=_guidance.map(func(owner):return owner.fork_for_frame())
	copy._flight=_flight.map(func(owner):return owner.fork_for_frame())
	copy._initial_actors=_initial_actors.duplicate(true);copy._death_rules=_death_rules.duplicate(true)
	copy._destruction=_destruction.map(func(owner):return owner.fork_for_frame())
	copy._accounting=null if _accounting==null else _accounting.fork_for_frame()
	copy._started=_started;copy._max_ms=_max_ms
	return copy

func clear() -> void:
	error="";_identity={};_rules={};_combat=null;_guidance=[];_flight=[];_random={}
	_initial_actors=[];_destruction=[];_death_rules={};_accounting=null;_started=false;_max_ms=0

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
