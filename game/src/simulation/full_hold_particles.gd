extends RefCounted
## Second-trip particle ownership. The player tail precedes the early particle
## managers, the death poll follows them, and the NPC pass updates next-frame
## roots and flags. Each registered emitter has an independent random stream.
const Definitions=preload("res://src/content/full_hold_particle_definitions.gd")
const Smoke=preload("res://src/simulation/opening_damage_particles.gd")
const Emitter=preload("res://src/simulation/damage_particle_emitter.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
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

func configure(bindings: RefCounted,combat: Dictionary,death: RefCounted,seed_seconds: Variant) -> bool:
	error=""
	if bindings==null or not Definitions.parameters(bindings.full_hold_particles) or not death is Death or death.presentation_identity()==null or not seed_seconds is int:return reject("Second-flight particles require their declared population, player death owner and seed")
	var initial: Dictionary=death.snapshot()
	for key in ["base_content_id","binding_id"]:
		if initial.get(key)!=bindings.get(key) or combat.get(key)!=bindings.get(key):return reject("Second-flight particles belong to another departure")
	if initial.get("phase")!="ready":return reject("Register second-flight particles before player death")
	var smoke:=Smoke.new()
	if not smoke.configure_full_hold(bindings,combat,seed_seconds):return reject(smoke.error)
	var emitters:={}
	for key in ["player","npc0","world"]:
		var emitter:=Emitter.new()
		if not emitter.configure_full_hold(bindings,bindings.base_content_id,11 if key=="world" else 9,seed_seconds):return reject(emitter.error)
		emitters[key]=emitter
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_smoke=smoke;_emitters=emitters;_manager_ms=0;_elapsed_ms=0;_burst_count=0;_births={}
	_death_identity=death.presentation_identity();_presentation_identity=RefCounted.new()
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
	var npc_root: Transform3D=_smoke.snapshot().owners.npc0.root_pose
	next._births={}
	# General sprites precede smoke and fire. The root already retained by the
	# shared NPC smoke/fire owner is also the preset-9 emitter's logical root.
	for key in _emitters:
		var pose: Transform3D=player_root if key=="player" else npc_root if key=="npc0" else Transform3D.IDENTITY
		var result: Dictionary=next._emitters[key].advance(pose,delta_ms,interval)
		if result.has("error"):return reject(next._emitters[key].error)
		next._births[key]=int(result.births)
	if not next._smoke.advance(player_root,delta_ms):return reject(next._smoke.error)
	next._manager_ms=0 if interval>=10 else interval
	next._elapsed_ms+=int(delta_ms)
	adopt(next);return true

func finish_npc_pass(before: Dictionary,after: Dictionary,events: Array,delta_ms: Variant,detail: Variant) -> bool:
	error=""
	if _smoke==null:return reject("Configure second-flight particles before the NPC pass")
	var next:=fork_for_frame()
	if not next._smoke.finish_npc_pass(before,after,events,delta_ms,detail):return reject(next._smoke.error)
	var death: Dictionary=events[0].get("destruction",{})
	if not death.is_empty():
		if death.started:next._emitters.npc0.set_emitting(true)
		if death.breakup:next._emitters.npc0.set_emitting(false)
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
	result.owners={"player":{"trail":_emitters.player.snapshot()},"npc0":smoke.owners.npc0,"world":{"burst":_emitters.world.snapshot()}}
	result.owners.npc0.trail=_emitters.npc0.snapshot()
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._manager_ms=_manager_ms;copy._elapsed_ms=_elapsed_ms;copy._burst_count=_burst_count;copy._births=_births.duplicate(true)
	if _smoke!=null:copy._smoke=_smoke.fork_for_frame()
	for key in _emitters:copy._emitters[key]=_emitters[key].fork_for_frame()
	copy._death_identity=_death_identity;copy._presentation_identity=_presentation_identity
	return copy

func adopt(next: RefCounted) -> void:
	_smoke=next._smoke;_emitters=next._emitters;_manager_ms=next._manager_ms;_elapsed_ms=next._elapsed_ms;_burst_count=next._burst_count;_births=next._births

func clear() -> void:
	error="";_identity={};_smoke=null;_emitters={};_manager_ms=0;_elapsed_ms=0;_burst_count=0;_births={};_death_identity=null;_presentation_identity=null

func reject(message: String) -> bool:error=message;return false
