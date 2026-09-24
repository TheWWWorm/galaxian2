extends RefCounted
## One normal player-exhaust manager. Drawing is independent of emission and
## particle ageing; the caller supplies the retained player statistics pose.
const Definitions=preload("res://src/content/engine_particle_owner_definitions.gd")
const Engines=preload("res://src/content/engine_particle_definitions.gd")
const Emitter=preload("res://src/simulation/damage_particle_emitter.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _identity:={}
var _emitters: Array=[]
var _manager_ms:=0
var _elapsed_ms:=0
var _engine_enabled:=true
var _player_hidden:=false
var _draw_enabled:=true
var _births:={}
var _presentation_identity: RefCounted

func configure(bindings: RefCounted,mounts: RefCounted,ship_id: Variant,seed_seconds: Variant) -> bool:
	error=""
	if not Definitions.available_for(bindings,ship_id) or not seed_seconds is int:return reject("Normal player exhaust requires its verified hull ownership and explicit seed")
	var resolved:=Engines.resolve(bindings,mounts,ship_id)
	if resolved.has("error"):return reject(resolved.error)
	var emitters: Array=[]
	for index in resolved.presets.size():
		var emitter:=Emitter.new()
		if not emitter.configure_nozzle(bindings,mounts,ship_id,index,seed_seconds):return reject(emitter.error)
		emitters.append(emitter)
	_identity={"base_content_id":resolved.base_content_id,"binding_id":resolved.binding_id,"ship_id":int(ship_id)}
	_emitters=emitters;_manager_ms=0;_elapsed_ms=0;_births={}
	_engine_enabled=Definitions.VALUES.initial_engine_enabled
	_player_hidden=Definitions.VALUES.initial_player_hidden
	_draw_enabled=Definitions.VALUES.initial_draw_enabled
	_presentation_identity=RefCounted.new()
	return true

func engine_enabled() -> bool:return _engine_enabled

func set_engine_enabled(value: Variant) -> bool:
	error=""
	if _identity.is_empty() or not value is bool:return reject("Configure player exhaust before changing its engine flag")
	var next:=fork_for_frame()
	for emitter in next._emitters:
		if not emitter.set_emitting(value):return reject(emitter.error)
	# This source operation writes drawing directly. A preceding player-hidden
	# operation must not silently override a later engine enable.
	next._engine_enabled=value;next._draw_enabled=value
	adopt(next);return true

func set_player_hidden(value: Variant) -> bool:
	error=""
	if _identity.is_empty() or not value is bool:return reject("Configure player exhaust before changing its player draw gate")
	_player_hidden=value;_draw_enabled=not value and _engine_enabled
	return true

func set_nozzle_emitting(index: Variant,value: Variant) -> bool:
	error=""
	if _identity.is_empty() or not Numbers.integer(index,0,_emitters.size()-1) or not value is bool:return reject("Player exhaust requires a registered nozzle and an emission flag")
	var next:=fork_for_frame()
	if not next._emitters[int(index)].set_emitting(value):return reject(next._emitters[int(index)].error)
	# A retained manager handle changes only this emitter. Live slots, the
	# manager draw gate and the requested engine flag remain independent.
	adopt(next);return true

func advance(statistics_pose: Variant,delta_ms: Variant,boost_active: Variant=false) -> bool:
	error=""
	if _identity.is_empty() or not Flight.rigid_pose(statistics_pose) or not Numbers.integer(delta_ms,0,1000):return reject("Player exhaust requires a rigid statistics pose and bounded milliseconds")
	if not boost_active is bool or boost_active:return reject("Boost exhaust is unavailable; its envelope has not been verified")
	if delta_ms==0:return true
	var next:=fork_for_frame();var interval:=_manager_ms+int(delta_ms)
	next._births={}
	# A hidden manager still updates every registered emitter, its movement
	# baseline and its private RNG. No emitter visibility operation belongs here.
	for index in next._emitters.size():
		var result: Dictionary=next._emitters[index].advance(statistics_pose,delta_ms,interval)
		if result.has("error"):return reject(next._emitters[index].error)
		next._births["player_nozzle%d"%index]=int(result.births)
	next._manager_ms=0 if interval>=int(Definitions.VALUES.manager_velocity_interval_ms) else interval
	next._elapsed_ms+=int(delta_ms)
	adopt(next);return true

func presentation_identity() -> RefCounted:return _presentation_identity

func snapshot() -> Dictionary:
	if _identity.is_empty():return {}
	var result:=_identity.duplicate()
	result.mode="normal";result.manager_ms=_manager_ms;result.elapsed_ms=_elapsed_ms
	result.engine_enabled=_engine_enabled;result.player_hidden=_player_hidden;result.draw_enabled=_draw_enabled
	result.births=_births.duplicate();result.owners={}
	for index in _emitters.size():
		result.owners["player_nozzle%d"%index]={"draw_enabled":_draw_enabled,"exhaust":_emitters[index].snapshot()}
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._manager_ms=_manager_ms;copy._elapsed_ms=_elapsed_ms
	copy._engine_enabled=_engine_enabled;copy._player_hidden=_player_hidden;copy._draw_enabled=_draw_enabled
	copy._births=_births.duplicate();copy._presentation_identity=_presentation_identity
	for emitter in _emitters:copy._emitters.append(emitter.fork_for_frame())
	return copy

func adopt(next: RefCounted) -> void:
	_emitters=next._emitters;_manager_ms=next._manager_ms;_elapsed_ms=next._elapsed_ms
	_engine_enabled=next._engine_enabled;_player_hidden=next._player_hidden;_draw_enabled=next._draw_enabled
	_births=next._births

func clear() -> void:
	error="";_identity={};_emitters=[];_manager_ms=0;_elapsed_ms=0;_births={}
	_engine_enabled=true;_player_hidden=false;_draw_enabled=true;_presentation_identity=null

func reject(message: String) -> bool:error=message;return false
