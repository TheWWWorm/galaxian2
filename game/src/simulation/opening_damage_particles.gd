extends RefCounted
## Native fresh-opening smoke/fire owners. The weapon pass samples retained NPC
## roots before controller and NPC work; those later passes only change flags and
## the roots used next frame. Every emitter has its own random stream.
const Definitions=preload("res://src/content/damage_particle_owner_definitions.gd")
const Emitter=preload("res://src/simulation/damage_particle_emitter.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const FullHold=preload("res://src/content/full_hold_particle_definitions.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
var error:=""
var _identity:={}
var _rules:={}
var _emitters:={}
var _roots: Array=[]
var _damaged: Array=[]
var _modes: Array=[]
var _death_phases: Array=[]
var _manager_ms:=0
var _elapsed_ms:=0
var _resets:=0
var _births:={}
var _presentation_identity: RefCounted
var _npc_count:=3

func configure(bindings: RefCounted,combat: Dictionary,seed_seconds: Variant) -> bool:
	clear()
	if bindings==null or not Definitions.parameters(bindings.damage_particles.get("owners",{})) or not seed_seconds is int:return reject("Fresh damage effects require owner declarations and an explicit seed")
	_rules=bindings.damage_particles.owners.duplicate(true)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	var cursor: Variant=bindings.opening_actors.get("npc_initialization",{}).get("world_initialization",{}).get("campaign_cursor")
	if not Numbers.integer(cursor,0,int(_rules.player_max_campaign_cursor)) or not valid_combat(combat):
		clear();return reject("Fresh damage effects require their initialized opening population")
	return _configure_owners(bindings,combat,seed_seconds,["player","npc0","npc1","npc2"],int(bindings.opening_actors.npc_initialization.get("holding",{}).get("actor_mode",0)))

func configure_full_hold(bindings: RefCounted,combat: Dictionary,seed_seconds: Variant) -> bool:
	clear()
	if bindings==null or not FullHold.parameters(bindings.full_hold_particles) or not Definitions.parameters(bindings.damage_particles.get("owners",{})) or not seed_seconds is int:return reject("Second-flight smoke/fire requires its verified owners and seed")
	_rules=bindings.damage_particles.owners.duplicate(true)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_npc_count=int(bindings.full_hold_particles.npc_count)
	if combat.get("campaign_cursor")!=4 or not valid_combat(combat):clear();return reject("Second-flight smoke/fire requires its one initialized pirate")
	return _configure_owners(bindings,combat,seed_seconds,["npc0"],5)

func configure_combat_training(bindings: RefCounted,combat: Dictionary,seed_seconds: Variant) -> bool:
	clear()
	if bindings==null or Training.flight(bindings).is_empty() or not FullHold.parameters(bindings.full_hold_particles) or not Definitions.parameters(bindings.damage_particles.get("owners",{})) or not seed_seconds is int:return reject("Training smoke/fire requires its ordinary particle owners and seed")
	_rules=bindings.damage_particles.owners.duplicate(true)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":7}
	_npc_count=4
	if not valid_combat(combat):clear();return reject("Training smoke/fire requires the complete initialized cast")
	return _configure_owners(bindings,combat,seed_seconds,["npc0","npc1","npc2","npc3"],[5,5,5,0])

func _configure_owners(bindings: RefCounted,combat: Dictionary,seed_seconds: int,keys: Array,initial_mode: Variant) -> bool:
	for key in keys:
		var pair:=[]
		for preset in [15,42]:
			var emitter:=Emitter.new()
			if not emitter.configure(bindings,bindings.base_content_id,preset,seed_seconds):
				var message:=emitter.error;clear();return reject(message)
			pair.append(emitter)
		_emitters[key]=pair
	for actor in combat.actors:
		var expected: int=initial_mode[int(actor.actor_id)] if initial_mode is Array else int(initial_mode)
		if actor.actor_mode!=expected:clear();return reject("Damage effects must join the fresh held NPCs")
		_roots.append(actor.pose);_damaged.append(false);_modes.append(int(actor.actor_mode));_death_phases.append("ready")
	_presentation_identity=RefCounted.new()
	return true

func presentation_identity() -> RefCounted:return _presentation_identity

func advance(player_root: Variant,delta_ms: Variant) -> bool:
	error=""
	if _identity.is_empty() or not Flight.rigid_pose(player_root) or not Numbers.integer(delta_ms,0,1000):return reject("Damage effects require a finite player root and bounded whole milliseconds")
	if delta_ms==0:return true
	var next:=fork_for_frame()
	var interval: int=next._manager_ms+int(delta_ms)
	next._births={}
	# Smoke and fire managers traverse registered owners independently. All eight
	# streams still advance their baselines while their emission flag is clear.
	for preset_index in 2:
		for key in _emitters:
			var pose: Transform3D=player_root if key=="player" else _roots[int(key.trim_prefix("npc"))]
			var emitter: RefCounted=next._emitters[key][preset_index]
			var event: Dictionary=emitter.advance(pose,delta_ms,interval)
			if event.has("error"):return reject(emitter.error)
			if not next._births.has(key):next._births[key]=[0,0]
			next._births[key][preset_index]=int(event.births)
	next._manager_ms=0 if interval>=10 else interval
	next._elapsed_ms+=int(delta_ms)
	adopt(next);return true

func apply_controller(escape: Dictionary) -> bool:
	error=""
	if _identity.is_empty():return reject("Configure damage effects before controller cues")
	if escape.is_empty():return true
	if not _emitters.has("player"):return reject("Opening controller cues cannot change second-flight smoke/fire")
	for key in _identity:
		if escape.get(key)!=_identity[key]:return reject("Damage effect cues belong to another opening")
	var frame: Variant=escape.get("frame")
	if not frame is Dictionary or not frame.get("world_change",{}) is Dictionary or not frame.get("ship_restore",false) is bool:return reject("Invalid damage effect controller cues")
	var next:=fork_for_frame()
	if not frame.get("world_change",{}).is_empty():
		# Source relocation resets fire then smoke, keeping registrations, RNG,
		# ring cursors, flags and the shared manager clock.
		for index in [1,0]:
			for pair in next._emitters.values():pair[index].reset()
		next._resets+=1
	if frame.get("ship_restore",false):next.set_pair("player",true)
	adopt(next);return true

func finish_npc_pass(before: Dictionary,after: Dictionary,events: Array,delta_ms: Variant,detail: Variant) -> bool:
	error=""
	if _identity.is_empty() or not valid_combat(before) or not valid_combat(after) or events.size()!=_npc_count or not Numbers.integer(delta_ms,0,1000):return reject("Damage effects require the ordered NPC pass")
	if not (detail is float or detail is int) or not is_finite(detail) or detail<0 or detail>1:return reject("Damage effects require the world detail value")
	var next:=fork_for_frame()
	for id in _npc_count:
		var event: Variant=events[id]
		if not event is Dictionary or event.get("actor_id")!=id or not event.get("decision") is Dictionary or not event.get("movement") is Dictionary or not event.get("destruction",{}) is Dictionary:return reject("Invalid NPC effect event")
		var actor: Dictionary=before.actors[id];var result: Dictionary=after.actors[id]
		var death: Dictionary=event.get("destruction",{})
		var skipped: bool=(event.decision.is_empty() or event.decision.get("retired",false)) and not death.is_empty()
		var key:="npc%d" % id
		if not skipped:
			var threshold:=Emitter.single(Emitter.single(float(actor.max_hull))*Emitter.single(float(_rules.npc_hull_fraction)))
			var low:=Emitter.single(float(actor.vitals.hull))<threshold
			if low and not next._damaged[id]:
				next._damaged[id]=true
				if not _rules.npc_uses_detail_gate or detail>0:next.set_pair(key,actor.actor_mode!=_rules.npc_suppressed_mode)
			elif not low and next._damaged[id]:
				next._damaged[id]=false;next.set_pair(key,false)
			# Mode-nine release and entry are transitions, not a continuous gate.
			# A damaged Mac NPC released at detail zero still enables its trails.
			if next._damaged[id] and _modes[id]!=result.actor_mode:
				if _modes[id]==_rules.npc_suppressed_mode and result.actor_mode==_rules.active_mode:next.set_pair(key,true)
				elif result.actor_mode==_rules.npc_suppressed_mode:next.set_pair(key,false)
		if not death.is_empty():
			var state: Variant=death.get("state")
			if not state is Dictionary or state.get("phase") not in ["tumble","explosion","retired"] or not state.get("spin") is Vector3 or not state.spin.is_finite() or not Flight.rigid_pose(state.get("pose")) or not death.get("started") is bool or not death.get("breakup") is bool:return reject("Invalid NPC death effect event")
			if death.breakup and (not _rules.npc_uses_detail_gate or detail>0):next.set_pair(key,false)
			# The emitter attaches to the logical root. Retain that root through
			# death spin instead of adding the visual bank to its local axes.
			if not skipped and (death.started or _death_phases[id]=="tumble"):
				if delta_ms>0:next._roots[id].basis=next._roots[id].basis*Vectors.local_xyz(state.spin)
				next._roots[id].origin=state.pose.origin
			next._death_phases[id]=state.phase
		elif not event.movement.is_empty():
			if not Flight.rigid_pose(event.movement.get("root_pose")):return reject("NPC trail requires the unbanked movement root")
			next._roots[id]=event.movement.root_pose
		else:next._roots[id]=result.pose
		if not Flight.rigid_pose(next._roots[id]):return reject("NPC particle root exceeded finite source bounds")
		next._modes[id]=int(result.actor_mode)
	adopt(next);return true

func set_pair(key: String,enabled: bool) -> void:
	for emitter in _emitters[key]:emitter.set_emitting(enabled)

func valid_combat(combat: Dictionary) -> bool:
	for key in _identity:
		if combat.get(key)!=_identity[key]:return false
	var actors: Variant=combat.get("actors")
	if not actors is Array or actors.size()!=_npc_count:return false
	for id in _npc_count:
		var actor: Variant=actors[id]
		var minimum_mode:=0 if _identity.get("campaign_cursor")==7 and id==3 else 1
		if not actor is Dictionary or actor.get("actor_id")!=id or not Flight.rigid_pose(actor.get("pose")) or not Numbers.integer(actor.get("actor_mode"),minimum_mode,9):return false
		if not actor.get("vitals") is Dictionary or not Numbers.integer(actor.vitals.get("hull"),0,2147483647) or not Numbers.integer(actor.get("max_hull"),1,2147483647):return false
	return true

func npc_root(actor_id: int) -> Transform3D:
	return _roots[actor_id] if actor_id>=0 and actor_id<_roots.size() else Transform3D.IDENTITY

func snapshot() -> Dictionary:
	if _identity.is_empty():return {}
	var result:=_identity.duplicate()
	result.manager_ms=_manager_ms;result.elapsed_ms=_elapsed_ms;result.resets=_resets
	result.births=_births.duplicate(true);result.owners={}
	for key in _emitters:
		var pair: Array=_emitters[key]
		var row:={"smoke":pair[0].snapshot(),"fire":pair[1].snapshot()}
		if key!="player":
			var id:=int(key.trim_prefix("npc"))
			row.root_pose=_roots[id];row.damaged=_damaged[id];row.mode=_modes[id];row.death_phase=_death_phases[id]
		result.owners[key]=row
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._rules=_rules.duplicate(true)
	for key in _emitters:
		copy._emitters[key]=[]
		for emitter in _emitters[key]:copy._emitters[key].append(emitter.fork_for_frame())
	copy._roots=_roots.duplicate();copy._damaged=_damaged.duplicate();copy._modes=_modes.duplicate();copy._death_phases=_death_phases.duplicate()
	copy._manager_ms=_manager_ms;copy._elapsed_ms=_elapsed_ms;copy._resets=_resets;copy._births=_births.duplicate(true)
	copy._presentation_identity=_presentation_identity
	copy._npc_count=_npc_count
	return copy

func adopt(next: RefCounted) -> void:
	_emitters=next._emitters;_roots=next._roots;_damaged=next._damaged;_modes=next._modes;_death_phases=next._death_phases
	_manager_ms=next._manager_ms;_elapsed_ms=next._elapsed_ms;_resets=next._resets;_births=next._births

func clear() -> void:
	error="";_identity={};_rules={};_emitters={};_roots=[];_damaged=[];_modes=[];_death_phases=[]
	_manager_ms=0;_elapsed_ms=0;_resets=0;_births={}
	_presentation_identity=null
	_npc_count=3

func reject(message: String) -> bool:error=message;return false
