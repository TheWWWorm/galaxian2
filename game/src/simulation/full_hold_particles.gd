extends RefCounted
const FlightStages=preload("res://src/content/flight_stages.gd")
## Second-trip particle ownership. The player tail precedes the early particle
## managers, the death poll follows them, and the NPC pass updates next-frame
## roots and flags. Each registered emitter has an independent random stream.
const Definitions=preload("res://src/content/full_hold_particle_definitions.gd")
const Smoke=preload("res://src/simulation/opening_damage_particles.gd")
const Emitter=preload("res://src/simulation/damage_particle_emitter.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const ConvoyEffects=preload("res://src/content/convoy_effect_definitions.gd")
const Capture=preload("res://src/simulation/convoy_capture.gd")
var error:=""
var _identity:={}
var _smoke: RefCounted
var _emitters:={}
var _manager_ms:=0
var _elapsed_ms:=0
var _burst_count:=0
var _births:={}
var _death_identity: RefCounted
var _presentation_identity: RefCounted
var _emp:={}
var _emp_bound:=false
var _emp_capture_ms:=-1
var _emp_phase:=0

func configure(bindings: RefCounted,combat: Dictionary,death: RefCounted,seed_seconds: Variant) -> bool:
	error=""
	if bindings==null or not Definitions.parameters(bindings.full_hold_particles) or not death is Death or death.presentation_identity()==null or not seed_seconds is int:return reject("Second-flight particles require their declared population, player death owner and seed")
	var initial: Dictionary=death.snapshot()
	for key in ["base_content_id","binding_id"]:
		if initial.get(key)!=bindings.get(key) or combat.get(key)!=bindings.get(key):return reject("Second-flight particles belong to another departure")
	var training: bool=combat.get("campaign_cursor")==7
	var local_flight: bool=combat.get("campaign_cursor") in (FlightStages.LOCAL+FlightStages.POST_SAHI)
	if initial.get("phase")!="ready" or initial.get("departure_cursor")!=(int(combat.campaign_cursor) if local_flight else (7 if training else 4)):return reject("Register ordinary-flight particles before player death in the same encounter")
	var smoke:=Smoke.new()
	var ready:=smoke.configure_local_traffic(bindings,combat,seed_seconds) if local_flight else (smoke.configure_combat_training(bindings,combat,seed_seconds) if training else smoke.configure_full_hold(bindings,combat,seed_seconds))
	if not ready:return reject(smoke.error)
	return _configure_registered(bindings,combat,death,int(seed_seconds),smoke)

func configure_first_mining(bindings: RefCounted,death: RefCounted,seed_seconds: Variant) -> bool:
	error=""
	if bindings==null or bindings.source_architecture!="x86_64" or not Definitions.parameters(bindings.full_hold_particles) or not death is Death or death.presentation_identity()==null or not seed_seconds is int:
		return reject("First mining particles require verified Mac sprite presets and player destruction")
	var state: Dictionary=death.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=bindings.get(key):return reject("First mining particles belong to another departure")
	if state.get("phase")!="ready" or state.get("departure_cursor")!=2 or state.get("campaign_cursor")!=2 or state.get("equipment_ids")!=[90,81]:
		return reject("First mining particles require the fresh Betty departure and its retained equipment")
	var smoke:=Smoke.new()
	if not smoke.configure_first_mining(bindings,seed_seconds):return reject(smoke.error)
	return _configure_registered(bindings,{"campaign_cursor":2,"actors":[]},death,int(seed_seconds),smoke)

func _configure_registered(bindings: RefCounted,combat: Dictionary,death: RefCounted,seed_seconds: int,smoke: RefCounted) -> bool:
	var emitters:={}
	var keys:=["player"]
	for id in combat.actors.size():
		if combat.actors[id].get("population_group") not in ["freighter","capital","debris"]:keys.append("npc%d"%id)
	keys.append("world")
	for key in keys:
		var emitter:=Emitter.new()
		if not emitter.configure_full_hold(bindings,bindings.base_content_id,11 if key=="world" else 9,seed_seconds):return reject(emitter.error)
		emitters[key]=emitter
	if combat.actors.any(func(actor):return actor.get("population_group")=="debris"):
		var emitter:=Emitter.new()
		if not emitter.configure_junk(bindings,seed_seconds):return reject(emitter.error)
		emitters.junk=emitter
	var emp:={}
	if combat.get("campaign_cursor")==14 and combat.actors.any(func(actor):return actor.get("convoy",false)) and ConvoyEffects.available(bindings):
		for id in bindings.mido_travel.convoy_effects.actor_ids:
			var key:="npc%d"%int(id)
			if not emitters.has(key):return reject("Convoy EMP registration lost its fighter")
			emp[key]={}
			for preset in bindings.mido_travel.convoy_effects.preset_ids:
				var emitter:=Emitter.new()
				if not emitter.configure_convoy_emp(bindings,int(preset),seed_seconds):return reject(emitter.error)
				emp[key]["emp%d"%int(preset)]=emitter
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_smoke=smoke;_emitters=emitters;_manager_ms=0;_elapsed_ms=0;_burst_count=0;_births={}
	_death_identity=death.presentation_identity();_presentation_identity=RefCounted.new()
	_emp=emp;_emp_bound=false;_emp_capture_ms=-1;_emp_phase=0
	return true

func has_convoy_emp() -> bool:return not _emp.is_empty()

func apply_convoy_capture(capture: RefCounted) -> bool:
	error=""
	if not has_convoy_emp() or not capture is Capture:return reject("Convoy sprites require their native capture owner")
	var state: Dictionary=capture.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=_identity.get(key):return reject("EMP capture belongs to another departure")
	if state.get("campaign_cursor")!=14 or int(state.phase)<_emp_phase or int(state.elapsed_ms)<=_emp_capture_ms:return reject("EMP capture is stale or regressed")
	var target: Dictionary=state.frame.get("emp_target",{})
	if not target.is_empty():
		if _emp_bound or target.get("actor_id")!=0 or state.phase!=Capture.Stage.PULSE:return reject("EMP target does not match its single source activation")
		var next:=fork_for_frame()
		for emitter in next._emp.npc0.values():
			if not emitter.rebind_transform() or not emitter.set_emitting(true) or not emitter.set_visible(true):return reject(emitter.error)
		next._emp_bound=true
		adopt(next)
	# The Mac capture-view stop addresses the nozzle manager, not this effects
	# manager. Do not redirect it here or clear the attached EMP sprites.
	_emp_capture_ms=int(state.elapsed_ms);_emp_phase=int(state.phase)
	return true

func apply_player_tail(death: RefCounted) -> bool:
	error=""
	if not matches_death(death):return reject("Particle tail lost its configured player destruction")
	var state: Dictionary=death.snapshot()
	if not state.events.get("breakup",false) or _burst_count>0:return true
	if not Flight.rigid_pose(state.statistics_pose):return reject("Player burst requires the retained statistics position")
	var next:=fork_for_frame()
	next._emitters.player.set_emitting(false);next._emitters.player.set_visible(false)
	var result: Dictionary=next._emitters.world.emit_once(state.statistics_pose.origin)
	if result.has("error"):return reject(next._emitters.world.error)
	next._burst_count=1
	adopt(next);return true

func apply_player_poll(death: RefCounted) -> bool:
	error=""
	if not matches_death(death):return reject("Particle poll lost its configured player destruction")
	var state: Dictionary=death.snapshot()
	# Only the emitted poll cue can re-enable the trail. Reading a retained flag
	# on an action-only frame must not become an extra source operation.
	var cues: Array=state.events.get("particle_events",[])
	if not cues.is_empty() and cues.back()=={"emitting":true}:
		if not _emitters.player.set_emitting(true):return reject(_emitters.player.error)
	return true

func advance(player_root: Variant,delta_ms: Variant) -> bool:
	error=""
	if _identity.is_empty() or not Flight.rigid_pose(player_root) or not Numbers.integer(delta_ms,0,1000):return reject("Second-flight particles require a rigid player root and bounded milliseconds")
	if delta_ms==0:return true
	var next:=fork_for_frame();var interval:=_manager_ms+int(delta_ms)
	next._births={}
	# General sprites precede smoke and fire. The root already retained by the
	# shared NPC smoke/fire owner is also the preset-9 emitter's logical root.
	for key in _emitters:
		var pose: Transform3D=player_root if key=="player" else _smoke.npc_root(int(key.trim_prefix("npc"))) if key.begins_with("npc") else Transform3D.IDENTITY
		var result: Dictionary=next._emitters[key].advance(pose,delta_ms,interval)
		if result.has("error"):return reject(next._emitters[key].error)
		next._births[key]=int(result.births)
	if not next._smoke.advance(player_root,delta_ms):return reject(next._smoke.error)
	for key in _emp:
		var pose: Transform3D=player_root if _emp_bound and key=="npc0" else _smoke.npc_root(int(key.trim_prefix("npc")))
		for kind in _emp[key]:
			var result: Dictionary=next._emp[key][kind].advance(pose,delta_ms,interval)
			if result.has("error"):return reject(next._emp[key][kind].error)
			next._births[key+"_"+kind]=int(result.births)
	next._manager_ms=0 if interval>=10 else interval
	next._elapsed_ms+=int(delta_ms)
	adopt(next);return true

func finish_npc_pass(before: Dictionary,after: Dictionary,events: Array,delta_ms: Variant,detail: Variant) -> bool:
	error=""
	if _smoke==null:return reject("Configure second-flight particles before the NPC pass")
	var next:=fork_for_frame()
	if not next._smoke.finish_npc_pass(before,after,events,delta_ms,detail):return reject(next._smoke.error)
	for event in events:
		var death: Dictionary=event.get("destruction",{})
		if not death.is_empty():
			for burst in death.get("bursts",[]):
				if not next._emitters.has("junk") or burst.get("preset_id")!=21 or burst.get("member_index")!=0 or burst.get("count")!=1 or burst.get("size_override")!=-1:return reject("The debris burst changed its verified sprite operation")
				var emitted: Dictionary=next._emitters.junk.emit_once(burst.position)
				if emitted.has("error"):return reject(next._emitters.junk.error)
			var key:="npc%d"%int(event.actor_id)
			if not next._emitters.has(key):continue
			if death.started:next._emitters[key].set_emitting(true)
			if death.breakup:next._emitters[key].set_emitting(false)
	adopt(next);return true

func matches_death(death: RefCounted) -> bool:
	return not _identity.is_empty() and death is Death and death.presentation_identity()==_death_identity

func presentation_identity() -> RefCounted:return _presentation_identity

func snapshot() -> Dictionary:
	if _identity.is_empty():return {}
	var result:=_identity.duplicate()
	var smoke: Dictionary=_smoke.snapshot()
	result.manager_ms=_manager_ms;result.elapsed_ms=_elapsed_ms;result.burst_count=_burst_count
	result.births=_births.duplicate(true);result.smoke_fire_births=smoke.births
	result.owners={}
	for key in _emitters:
		result.owners[key]=smoke.owners.get(key,{})
		result.owners[key]["junk_burst" if key=="junk" else "burst" if key=="world" else "trail"]=_emitters[key].snapshot()
	if has_convoy_emp():
		result.emp={"bound_to_player":_emp_bound,"capture_elapsed_ms":_emp_capture_ms,"phase":_emp_phase}
		for key in _emp:
			for kind in _emp[key]:result.owners[key][kind]=_emp[key][kind].snapshot()
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._manager_ms=_manager_ms;copy._elapsed_ms=_elapsed_ms;copy._burst_count=_burst_count;copy._births=_births.duplicate(true)
	if _smoke!=null:copy._smoke=_smoke.fork_for_frame()
	for key in _emitters:copy._emitters[key]=_emitters[key].fork_for_frame()
	for key in _emp:
		copy._emp[key]={}
		for kind in _emp[key]:copy._emp[key][kind]=_emp[key][kind].fork_for_frame()
	copy._emp_bound=_emp_bound;copy._emp_capture_ms=_emp_capture_ms;copy._emp_phase=_emp_phase
	copy._death_identity=_death_identity;copy._presentation_identity=_presentation_identity
	return copy

func adopt(next: RefCounted) -> void:
	_smoke=next._smoke;_emitters=next._emitters;_manager_ms=next._manager_ms;_elapsed_ms=next._elapsed_ms;_burst_count=next._burst_count;_births=next._births
	_emp=next._emp;_emp_bound=next._emp_bound;_emp_capture_ms=next._emp_capture_ms;_emp_phase=next._emp_phase

func clear() -> void:
	error="";_identity={};_smoke=null;_emitters={};_manager_ms=0;_elapsed_ms=0;_burst_count=0;_births={};_death_identity=null;_presentation_identity=null
	_emp={};_emp_bound=false;_emp_capture_ms=-1;_emp_phase=0

func reject(message: String) -> bool:error=message;return false
