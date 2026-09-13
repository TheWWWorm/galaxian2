extends RefCounted
## One ordered actor pass: retained guidance, pre-motion firing, then flight.
## Projectile contacts/motion belong to the world's earlier weapon pass. This
## owner neither advances projectile clocks again nor grants mission rewards.
const Guidance = preload("res://src/simulation/opening_npc_guidance.gd")
const Flight = preload("res://src/simulation/npc_flight.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Weapons = preload("res://src/simulation/opening_npc_weapons.gd")
const Holding = preload("res://src/content/npc_holding_definitions.gd")
const Death = preload("res://src/simulation/npc_destruction.gd")
const DeathAccounting = preload("res://src/simulation/npc_death_accounting.gd")
const Appearance=preload("res://src/content/full_hold_appearance_definitions.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
var error := ""
var _identity := {}
var _bindings: RefCounted
var _guidance := []
var _flight := []
var _has_hostility := false
var _destruction := []
var _accounting: RefCounted
var _started := false
var _full_hold_seed := {}
var _appearance_applied:=false
var _appearance_pending:=false

func configure(bindings: RefCounted, catalogues: RefCounted, difficulty: Variant) -> bool:
	clear()
	if bindings==null or not Holding.parameters(bindings.opening_actors.get("npc_initialization",{}).get("holding",{})):
		return reject("Ordered opening NPC control requires holding declarations")
	var controllers := []
	for id in 3:
		var guide := Guidance.new()
		if not guide.configure(bindings,catalogues,id,difficulty): return reject(guide.error)
		controllers.append(guide)
	_guidance=controllers;_flight=[null,null,null];_bindings=bindings
	_has_hostility=not bindings.opening_actors.npc_initialization.get("hostility",{}).is_empty()
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	if not bindings.opening_actors.npc_initialization.get("death_accounting",{}).is_empty():
		_accounting=DeathAccounting.new()
		if not _accounting.configure(bindings):
			var message: String=_accounting.error
			clear()
			return reject(message)
	return true

func configure_full_hold(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted, difficulty: Variant) -> bool:
	clear()
	var guide:=Guidance.new()
	if not guide.configure_full_hold(bindings,catalogues,construction,difficulty):return reject(guide.error)
	_guidance=[guide];_flight=[null];_bindings=bindings;_has_hostility=true
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":4}
	_full_hold_seed=construction.snapshot().scenery.world_initialization.npc_construction.actors[0].duplicate(true)
	return true

func set_full_hold_destruction(resources: RefCounted) -> bool:
	error=""
	if _full_hold_seed.is_empty() or _started or not _destruction.is_empty():return reject("Prepare second-trip destruction once before the first actor pass")
	var death:=Death.new();var accounting:=DeathAccounting.new()
	if not death.configure_full_hold(_bindings,resources,_full_hold_seed):return reject(death.error)
	if not accounting.configure_full_hold(_bindings):return reject(accounting.error)
	_destruction=[death];_accounting=accounting
	return true

func set_initial_route(actor_id: Variant, route: RefCounted) -> bool:
	error=""
	if not actor_id is int or actor_id<0 or actor_id>=_guidance.size(): return reject("Unknown NPC route owner")
	if not _guidance[actor_id].set_initial_route(route): return reject(_guidance[actor_id].error)
	return true

func apply_full_hold_appearance(combat: RefCounted, cursor: Variant, player: Dictionary) -> Dictionary:
	error=""
	if _full_hold_seed.is_empty() or not Appearance.parameters(_bindings.full_hold_appearance) or _destruction.size()!=1 or not combat is Combat:return fail("Prepare the verified pirate and destruction owners before its appearance")
	var rules: Dictionary=_bindings.full_hold_appearance
	if not cursor is int or cursor not in [int(rules.campaign_cursor),int(rules.trigger_cursor)]:return fail("Appearance requires the second-trip mission cursor")
	var scene: Dictionary=combat.snapshot()
	for key in _identity:
		if scene.get(key)!=_identity[key]:return fail("Appearance belongs to another flight")
	for key in ["base_content_id","binding_id"]:
		if player.get(key)!=_identity[key]:return fail("Appearance player belongs to another content identity")
	if not Flight.rigid_pose(player.get("pose")) or not player.get("ship_id") is int or player.ship_id!=0:return fail("Appearance requires the starter player's physical pose")
	if scene.get("actors",[]).size()!=1:return fail("Appearance requires the retained pirate population")
	if cursor==int(rules.campaign_cursor) and _appearance_applied:return fail("Appearance mission cursor regressed")
	var staged: RefCounted=fork_for_frame();var next: RefCounted=combat.fork_for_frame()
	if cursor!=int(rules.trigger_cursor) or _appearance_applied:return {"controller":staged,"combat":next,"applied":false}
	var actor: Dictionary=scene.actors[0];var life: Dictionary=_destruction[0].snapshot()
	var root: Transform3D=actor.pose
	if life.phase!="ready":
		if actor.pose!=life.statistics_pose or actor.get("body_pose")!=life.pose or actor.vitals.hull!=0 or actor.actor_mode!=life.mode or actor.active!=(life.phase!="retired"):return fail("Appearance body diverged from its retained death owner")
		root=life.pose
	elif _flight[0]!=null:
		var motion: Dictionary=_flight[0].snapshot()
		if actor.pose!=motion.pose:return fail("Appearance body diverged from its flight owner")
		root=motion.root_pose
	var offset:=Vector3(rules.offset[0],rules.offset[1],rules.offset[2])
	var position:=Vectors.added(player.pose.origin,offset)
	var statistics:=Transform3D(root.basis,position)
	root=Transform3D(Vectors.local_xyz(Vector3(0,float(rules.yaw_radians),0)),position)
	if staged._flight[0]==null:
		staged._flight[0]=Flight.new()
		if not staged._flight[0].configure(_bindings,root):return fail(staged._flight[0].error)
	elif not staged._flight[0].apply_scripted_pose(root):return fail(staged._flight[0].error)
	if not staged._destruction[0].reposition_full_hold(rules,root,statistics):return fail(staged._destruction[0].error)
	if not next.apply_full_hold_appearance(rules,root,statistics):return fail(next.error)
	staged._appearance_applied=true;staged._appearance_pending=true
	return {"controller":staged,"combat":next,"applied":true}

func set_initial_destruction(resources: RefCounted, construction: Dictionary) -> bool:
	error=""
	if _identity.is_empty() or _started or not _destruction.is_empty(): return reject("Prepare NPC destruction once before the first actor pass")
	if not _full_hold_seed.is_empty():return reject("Use retained cargo destruction for the second-trip pirate")
	for key in _identity:
		if construction.get(key)!=_identity[key]: return reject("NPC fragments belong to another content identity")
	var actors: Variant=construction.get("actors")
	if not actors is Array or actors.size()!=3: return reject("NPC destruction requires the retained opening population")
	var prepared := []
	for id in 3:
		var actor: Variant=actors[id]
		if not actor is Dictionary or actor.get("actor_id")!=id or not actor.get("cargo") is Array or not actor.cargo.is_empty() or not actor.get("fragments") is Array: return reject("NPC destruction requires cargo-free constructor fragments")
		var death := Death.new()
		if not death.configure(_bindings,resources,id,Transform3D.IDENTITY,0.0,actor.fragments): return reject(death.error)
		prepared.append(death)
	_destruction=prepared
	return true

func evaluate(combat: RefCounted, weapons: RefCounted, delta_ms: Variant, player: Dictionary, random_state: Variant) -> Dictionary:
	error=""
	if _identity.is_empty() or not combat is Combat or not weapons is Weapons: return fail("NPC control requires configured combat and weapon owners")
	var scene: Dictionary = combat.snapshot()
	var guns: Dictionary = weapons.snapshot()
	for key in _identity:
		if scene.get(key)!=_identity[key] or guns.get(key)!=_identity[key]: return fail("NPC control owners have different content identities")
	if scene.get("actors",[]).size()!=_guidance.size() or guns.get("actors",[]).size()!=_guidance.size():return fail("NPC control population differs from its configured owners")
	var staged: RefCounted = fork_for_frame()
	var next_combat: RefCounted = combat.fork_for_frame()
	var next_weapons: RefCounted = weapons.fork_for_frame()
	var next_random: Variant = random_state
	var events := []
	# Source world traversal is ascending, independent of targets or gun requests.
	for id in _guidance.size():
		var death: RefCounted=null if staged._destruction.is_empty() else staged._destruction[id]
		var life: Dictionary={} if death==null else death.snapshot()
		var actor: Dictionary = next_combat.snapshot().actors[id]
		if not life.is_empty() and life.phase!="ready":
			if actor.pose!=life.get("statistics_pose",life.pose) or actor.vitals.hull!=0 or actor.actor_mode!=life.mode or actor.active!=(life.phase!="retired"): return fail("NPC body diverged from its destruction owner")
			if not staged._full_hold_seed.is_empty() and actor.get("body_pose")!=life.pose:return fail("Cargo destruction hull diverged from its retained transform")
			# Retirement eligibility includes the retained cargo lifetime.
			if death.retires_before_update():
				var ended: Dictionary=death.advance(delta_ms,next_random)
				if ended.is_empty(): return fail(death.error)
				if not next_combat.apply_destruction(id,ended.state): return fail(next_combat.error)
				next_random=ended.random_state
				events.append({"actor_id":id,"decision":{},"firing":{},"movement":{},"destruction":ended})
				continue
			if not staged._full_hold_seed.is_empty():
				# Source statistics take the old hull transform before selection;
				# positive cargo motion replaces it again later in the same pass.
				var preceding: Transform3D=life.pose*Transform3D(life.bank_basis,Vector3.ZERO)
				if not next_combat.set_pose(id,preceding):return fail(next_combat.error)
		if staged._appearance_pending:
			if life.phase!="ready" or actor.pose!=life.statistics_pose or actor.get("body_pose")!=life.pose:return fail("Pending appearance poses diverged before the next NPC pass")
			if not next_combat.set_pose(id,staged._flight[id].snapshot().pose):return fail(next_combat.error)
			staged._appearance_pending=false
		if staged._has_hostility and not next_combat.refresh_hostility(id): return fail(next_combat.error)
		actor = next_combat.snapshot().actors[id]
		var root: Variant = actor.get("pose")
		if staged._flight[id]!=null and (life.is_empty() or life.phase=="ready"):
			if not actor.get("active"): return fail("Opening NPC control cannot return to holding after activation")
			var prior: Dictionary = staged._flight[id].snapshot()
			if actor.get("pose")!=prior.pose: return fail("Active NPC pose diverged from its flight owner")
			root=prior.root_pose
		elif not staged._full_hold_seed.is_empty() and not life.is_empty() and life.phase!="ready":root=life.pose
		var decision: Dictionary = staged._guidance[id].update(delta_ms,actor,root,player,next_random)
		if decision.is_empty(): return fail(staged._guidance[id].error)
		next_random=decision.random_state
		var firing := {}
		var movement := {}
		var destruction := {}
		var accounting := {}
		if decision.get("dying",false):
			if death==null: return fail("Prepare source NPC destruction resources before a lethal frame")
			# Death entry records counters before its random draws. The authored
			# one-time reactivation can enter this path again without healing.
			if life.phase=="ready" and staged._accounting!=null:
				if staged._appearance_applied and not staged._accounting.snapshot().events.is_empty():
					accounting=staged._accounting.record_scripted_restart(actor,_bindings.full_hold_appearance)
				else:accounting=staged._accounting.record(actor)
				if accounting.is_empty(): return fail(staged._accounting.error)
			if life.phase=="ready":
				var bank: Basis=Basis.IDENTITY
				if not staged._full_hold_seed.is_empty() and staged._flight[id]!=null:bank=staged._flight[id].bank_basis()
				if not death.capture(root if not staged._full_hold_seed.is_empty() else actor.pose,decision.speed,bank):return fail(death.error)
			destruction=death.advance(delta_ms,next_random)
			if destruction.is_empty(): return fail(death.error)
			if not next_combat.apply_destruction(id,destruction.state): return fail(next_combat.error)
			next_random=destruction.random_state
			if staged._full_hold_seed.is_empty():staged._flight[id]=null
			elif staged._flight[id]!=null and not staged._flight[id].apply_scripted_pose(destruction.state.pose):return fail(staged._flight[id].error)
		else:
			if _identity.has("campaign_cursor"):
				if not next_combat.apply_full_hold_guidance(_bindings.full_hold_control,decision):return fail(next_combat.error)
		if not decision.get("dying",false) and not decision.holding:
			if staged._flight[id]==null:
				staged._flight[id]=Flight.new()
				if not staged._flight[id].configure(_bindings,actor.pose): return fail(staged._flight[id].error)
			if decision.fire_requested:
				firing=next_weapons.fire(next_combat,[id])
				if firing.is_empty(): return fail(next_weapons.error)
			movement=staged._flight[id].advance(delta_ms,decision.direction,decision.speed,decision.steering_enabled,decision.travel_enabled)
			if movement.is_empty(): return fail(staged._flight[id].error)
			if not next_combat.set_pose(id,movement.pose,movement.root_pose if not staged._full_hold_seed.is_empty() else null): return fail(next_combat.error)
		var event := {"actor_id":id,"decision":decision,"firing":firing,"movement":movement}
		if not destruction.is_empty(): event.destruction=destruction
		if not accounting.is_empty(): event.death_accounting=accounting
		events.append(event)
	staged._started=true
	return {"controller":staged,"combat":next_combat,"weapons":next_weapons,"random_state":next_random,"actors":events}

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate();result.actors=[]
	if not _full_hold_seed.is_empty():result.appearance={"applied":_appearance_applied,"pending":_appearance_pending}
	if _accounting!=null: result.death_accounting=_accounting.snapshot()
	for id in _guidance.size():
		var actor := {"actor_id":id,"guidance":_guidance[id].snapshot(),"flight":{} if _flight[id]==null else _flight[id].snapshot()}
		if not _destruction.is_empty(): actor.destruction=_destruction[id].snapshot()
		result.actors.append(actor)
	return result

func destruction_owner(actor_id: int) -> RefCounted:
	return null if actor_id<0 or actor_id>=_destruction.size() else _destruction[actor_id].fork_for_frame()

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._bindings=_bindings
	copy._has_hostility=_has_hostility
	copy._started=_started
	copy._full_hold_seed=_full_hold_seed.duplicate(true)
	copy._appearance_applied=_appearance_applied;copy._appearance_pending=_appearance_pending
	if _accounting!=null: copy._accounting=_accounting.fork_for_frame()
	for death in _destruction: copy._destruction.append(death.fork_for_frame())
	for guide in _guidance: copy._guidance.append(guide.fork_for_frame())
	for flight in _flight: copy._flight.append(null if flight==null else flight.fork_for_frame())
	return copy

func clear() -> void:
	error="";_identity={};_bindings=null;_guidance=[];_flight=[]
	_has_hostility=false
	_destruction=[];_started=false
	_accounting=null
	_full_hold_seed={}
	_appearance_applied=false;_appearance_pending=false

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
