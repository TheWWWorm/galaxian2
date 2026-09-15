extends RefCounted
## Native bounded sprite simulation in source world units and milliseconds.
## The manager supplies its shared elapsed interval, including this frame. Every
## registered emitter must be advanced, including disabled and invisible ones.
## Ownership, damage triggers and rendering are separate from this component.
const Definitions=preload("res://src/content/damage_particle_definitions.gd")
const FullHold=preload("res://src/content/full_hold_particle_definitions.gd")
const Engines=preload("res://src/content/engine_particle_definitions.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
const Convoy=preload("res://src/content/convoy_effect_definitions.gd")
const Appearance=preload("res://src/presentation/damage_particle_appearance.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Library=preload("res://src/content/library.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const RESET_POSITION=Vector3(4294967296.0,4294967296.0,4294967296.0)
const MAX_BIRTHS_PER_FRAME:=16384
var error:=""
var binding_id:=""
var base_content_id:=""
var _preset:={}
var _slots: Array=[]
var _random:=Random.new()
var _cursor:=0
var _remainder_ms:=0.0
var _enabled:=false
var _visible:=true
var _update_existing:=true
var _dirty:=true
var _force_velocity:=true
var _baseline:=Vector3.ZERO
var _velocity:=Vector3.ZERO
var _fade_rgb:=false

func configure(bindings: RefCounted,content_id: String,preset_id: Variant,seed: Variant) -> bool:
	clear()
	if bindings==null:return reject("Damage particles require content bindings")
	return _configure_rows(bindings,content_id,preset_id,seed,bindings.damage_particles.get("presets",[]))

func configure_full_hold(bindings: RefCounted,content_id: String,preset_id: Variant,seed: Variant) -> bool:
	clear()
	if bindings==null or bindings.source_architecture!="x86_64" or not FullHold.parameters(bindings.full_hold_particles):return reject("This content has no supported second-flight particle declarations")
	if not _configure_rows(bindings,content_id,preset_id,seed,bindings.full_hold_particles.presets):return false
	_enabled=bindings.full_hold_particles.burst_initial_emitting if _preset.preset_id==bindings.full_hold_particles.burst_preset else bindings.full_hold_particles.player_initial_emitting
	return true

func configure_junk(bindings: RefCounted,seed: Variant) -> bool:
	clear()
	if not Junk.available(bindings):return reject("Junk explosion particles are unavailable")
	var rules: Dictionary=bindings.early_contracts.junk_lifecycle
	if not _configure_rows(bindings,bindings.base_content_id,int(rules.burst_preset.preset_id),seed,[rules.burst_preset]):return false
	_enabled=bool(rules.burst_initial_emitting)
	return true

func configure_convoy_emp(bindings: RefCounted,preset_id: Variant,seed: Variant) -> bool:
	clear()
	if not Convoy.available(bindings):return reject("Original convoy EMP sprites are unavailable")
	var rules: Dictionary=bindings.mido_travel.convoy_effects
	if not _configure_rows(bindings,bindings.base_content_id,preset_id,seed,rules.presets):return false
	_enabled=rules.initial_emitting;_visible=rules.initial_visible;_fade_rgb=rules.fade_in_rgb
	return true

func configure_nozzle(bindings: RefCounted,mounts: RefCounted,ship_id: Variant,nozzle_index: Variant,seed: Variant) -> bool:
	clear()
	var resolved:=Engines.resolve(bindings,mounts,ship_id)
	if resolved.has("error"):return reject(resolved.error)
	if not Numbers.integer(nozzle_index,0,resolved.presets.size()-1):return reject("The requested player nozzle is unavailable")
	if not _configure_rows(bindings,resolved.base_content_id,resolved.presets[int(nozzle_index)].preset_id,seed,resolved.presets):return false
	_enabled=bindings.engine_particles.initial_emitting
	return true

func _configure_rows(bindings: RefCounted,content_id: String,preset_id: Variant,seed: Variant,rows: Variant) -> bool:
	if not Library.valid_hash(content_id) or bindings.base_content_id!=content_id or not Library.valid_hash(bindings.binding_id):return reject("Damage particles belong to unavailable or different content")
	if not Definitions.emitter_parameters(bindings.damage_particles) or not rows is Array:return reject("This content has no supported damage particle emitter defaults")
	if not Numbers.integer(preset_id,0,47) or not seed is int:return reject("Particle preset and random seed must be explicit integers")
	for row in rows:
		if row.preset_id==preset_id:_preset=row.duplicate(true)
	if _preset.is_empty():return reject("The requested damage particle preset is unavailable")
	if not Definitions.sprite_preset(_preset):return reject("Invalid particle appearance parameters")
	_random.seed_from(seed)
	for index in int(_preset.capacity):
		_slots.append({"appearance":{"slot":index,"age_ms":-1,"size":0},"position":RESET_POSITION,"velocity":Vector3.ZERO})
	binding_id=bindings.binding_id;base_content_id=content_id
	return true

func emit_once(position: Variant) -> Dictionary:
	error=""
	# The verified world burst requests member zero, one particle and the preset
	# size. Other manual presets and size overrides need their own source proof.
	if _preset.is_empty() or int(_preset.preset_id) not in [11,21] or _preset.flags!=0x02000101:return fail("Configure the supported manual sprite before requesting a burst")
	if not position is Vector3 or not position.is_finite():return fail("A particle burst requires a finite source world position")
	var next:=fork_for_frame()
	var appearance: Dictionary=next._new_appearance()
	if appearance.has("error"):return fail(appearance.error)
	next._slots[_cursor]={"appearance":appearance,"position":position,"velocity":Vector3.ZERO}
	_slots=next._slots;_random=next._random;_cursor=(_cursor+1)%_slots.size()
	# A direct birth does not consult or change emission/visibility, the manager
	# clock or the movement baseline. Visibility changes still reset live slots.
	return {"births":1}

func clear() -> void:
	error="";binding_id="";base_content_id="";_preset={};_slots=[];_random.clear()
	_cursor=0;_remainder_ms=0;_enabled=false;_visible=true;_update_existing=true
	_dirty=true;_force_velocity=true;_baseline=Vector3.ZERO;_velocity=Vector3.ZERO
	_fade_rgb=false

func rebind_transform() -> bool:
	error=""
	if _preset.is_empty():return reject("Configure a sprite before rebinding its transform")
	# Source retargeting retains the preceding root and live particles, and forces
	# the next velocity update. It does not reset to the new transform's origin.
	_dirty=false;_force_velocity=true
	return true

func set_emitting(value: Variant) -> bool:
	error=""
	if _preset.is_empty() or not value is bool:return reject("Configure damage particles and supply an emission flag")
	if value and not _enabled:_remainder_ms=0
	_enabled=value;return true

func set_visible(value: Variant) -> bool:
	error=""
	if _preset.is_empty() or not value is bool:return reject("Configure damage particles and supply a visibility flag")
	if _visible and not value:reset()
	_visible=value;return true

func set_update_existing(value: Variant) -> bool:
	error=""
	if _preset.is_empty() or not value is bool:return reject("Configure damage particles and supply an update flag")
	_update_existing=value;return true

func reset() -> bool:
	error=""
	if _preset.is_empty():return reject("Configure damage particles before resetting")
	for slot in _slots:
		slot.appearance.age_ms=-1;slot.appearance.size=0;slot.position=RESET_POSITION
	_remainder_ms=0;_dirty=true
	return true

func snapshot() -> Dictionary:
	if _preset.is_empty():return {}
	var result:={"binding_id":binding_id,"base_content_id":base_content_id,"preset":_preset.duplicate(true),
		"slots":_slots.duplicate(true),"random":_random.snapshot(),"cursor":_cursor,
		"remainder_ms":_remainder_ms,"enabled":_enabled,"visible":_visible,
		"update_existing":_update_existing,"dirty":_dirty,"force_velocity":_force_velocity,
		"baseline":_baseline,"velocity":_velocity}
	if _fade_rgb:result.fade_in_rgb=true
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy.binding_id=binding_id;copy.base_content_id=base_content_id
	copy._preset=_preset.duplicate(true);copy._slots=_slots.duplicate(true);copy._random=_random.fork()
	copy._cursor=_cursor;copy._remainder_ms=_remainder_ms
	copy._enabled=_enabled;copy._visible=_visible;copy._update_existing=_update_existing
	copy._dirty=_dirty;copy._force_velocity=_force_velocity;copy._baseline=_baseline;copy._velocity=_velocity
	copy._fade_rgb=_fade_rgb
	return copy

func advance(pose: Variant,delta_ms: Variant,manager_elapsed_ms: Variant) -> Dictionary:
	error=""
	if _preset.is_empty():return fail("Configure damage particles before advancing")
	if not pose is Transform3D or not pose.is_finite():return fail("Damage particles require a finite source world transform")
	for interval in [delta_ms,manager_elapsed_ms]:
		if not Numbers.integer(interval,0,1010):return fail("Damage particle manager intervals must be whole milliseconds")
	if delta_ms>1000 or manager_elapsed_ms<delta_ms or manager_elapsed_ms-delta_ms>9:return fail("Particle manager time must include this frame and at most nine retained milliseconds")
	# A paused native frame changes nothing. In particular, never force a velocity
	# division by a zero manager interval after reset.
	if delta_ms==0:return {"births":0}
	var staged:=fork_for_frame()
	var result: Dictionary=staged._advance(pose,single(delta_ms),single(manager_elapsed_ms))
	if result.has("error"):return fail(result.error)
	_slots=staged._slots;_random=staged._random;_cursor=staged._cursor
	_remainder_ms=staged._remainder_ms;_dirty=staged._dirty;_force_velocity=staged._force_velocity
	_baseline=staged._baseline;_velocity=staged._velocity
	return result

func _advance(pose: Transform3D,delta_ms: float,manager_elapsed_ms: float) -> Dictionary:
	if _update_existing:
		for index in _slots.size():
			if not move_particle(index,delta_ms):return fail(error)
	if _dirty:
		_velocity=Vector3.ZERO;_baseline=pose.origin;_force_velocity=true;_dirty=false
		return {"births":0}
	if manager_elapsed_ms>9 or _force_velocity:
		_velocity=Vectors.scaled(pose.origin-_baseline,single(1000.0/manager_elapsed_ms))
		_baseline=pose.origin;_force_velocity=false
		if not _velocity.is_finite() or not is_finite(Vectors.dot(_velocity,_velocity)):return fail("Damage particle velocity exceeds finite source bounds")
	# Source flag bit eight selects direct emission and rejects automatic births
	# before the timer. Its inherited 500/s field must never create a trail.
	if not _enabled or not _visible or (int(_preset.flags)&0x100)!=0:return {"births":0}
	if Vectors.dot(_velocity,_velocity)<float(_preset.get("minimum_squared_speed",0)):return {"births":0}
	var total:=single(_remainder_ms+delta_ms)
	var movement:=divided(Vectors.scaled(_velocity,total),1000.0)
	var inverse_distance:=inverse_length(movement)
	var inverse_speed:=inverse_length(_velocity)
	if not is_finite(inverse_distance) or inverse_distance<=0 or not is_finite(inverse_speed) or inverse_speed<=0:return fail("Damage particle distance exceeds finite source bounds")
	var distance:=single(1.0/inverse_distance)
	var distance_emission: bool=_preset.flags==0x11
	var requested: float=single(distance/single(_preset.distance_spacing)) if distance_emission else single(single(single(_preset.emission_per_second)*total)*single(0.001))
	if not is_finite(requested) or requested>MAX_BIRTHS_PER_FRAME:return fail("Particle births exceed the supported frame work limit")
	var count:=int(requested)
	if distance_emission:
		if requested<=0:return {"births":0}
		_remainder_ms=single(single(single(requested-single(count))*total)/requested)
	else:
		_remainder_ms=single(total+single(single(float(count)*-1000.0)/single(_preset.emission_per_second)))
	if count<=0:return {"births":0}
	# The timer consumes the entire requested count even when short movement
	# collapses this update to one newborn at the current emitter position.
	var short_movement:=distance<1.0
	if short_movement:count=1
	var spacing:=single(_preset.distance_spacing) if distance_emission else single(distance/float(count))
	var start_position:=pose.origin-movement
	var inherited:=Vectors.scaled(_velocity,single(_preset.relative_velocity_factor))
	for birth in count:
		var progress:=birth+1
		var velocity:=Vector3.ZERO
		var scatter:=int(_preset.velocity_scatter)
		if scatter>0:
			velocity=Vector3(_random.next_int(scatter*2)-scatter,_random.next_int(scatter*2)-scatter,_random.next_int(scatter*2)-scatter)
		velocity=Vectors.added(velocity,-inherited)
		velocity=Vectors.added(velocity,Vectors.scaled(pose.basis.z,single(_preset.local_velocity_z)))
		var position:=pose.origin if short_movement else Vectors.added(start_position,Vectors.scaled(Vectors.scaled(movement,single(float(progress)*spacing)),inverse_distance))
		if distance_emission:position=Vectors.added(position,Vectors.scaled(pose.basis.x,single(_preset.local_offset_x)))
		position=Vectors.added(position,Vectors.scaled(pose.basis.y,single(_preset.local_offset_y)))
		position=Vectors.added(position,Vectors.scaled(pose.basis.z,single(_preset.local_offset_z)))
		var z_jitter:=int(_preset.local_offset_z_jitter)
		if z_jitter>0:position=Vectors.added(position,Vectors.scaled(pose.basis.z,float(_random.next_int(z_jitter))))
		scatter=int(_preset.scatter_xz)
		if scatter>0:
			position.x=single(position.x+float(_random.next_int(scatter*2)-scatter))
			position.z=single(position.z+float(_random.next_int(scatter*2)-scatter))
		scatter=int(_preset.scatter_y)
		if scatter>0:position.y=single(position.y+float(_random.next_int(scatter*2)-scatter))
		var appearance:=_new_appearance()
		if appearance.has("error"):return fail(appearance.error)
		velocity=Vectors.added(velocity,Vectors.scaled(inherited,2.0))
		if not position.is_finite() or not velocity.is_finite():return fail("Damage particle birth exceeds finite source bounds")
		_slots[_cursor]={"appearance":appearance,"position":position,"velocity":velocity}
		var residual:=0.0 if short_movement else minf(delta_ms,single(single(single(float(count-progress)*spacing)*1000.0)*inverse_speed))
		if not move_particle(_cursor,residual):return fail(error)
		_cursor=(_cursor+1)%_slots.size()
	return {"births":count}

func _new_appearance() -> Dictionary:
	var size_sample:=0
	if _preset.size_jitter>0:
		size_sample=_random.next_int(int(_preset.size_jitter))
		# Sprite geometry uses one size; both auxiliary dimensions still consume
		# their own draws on this emitter's independent random stream.
		_random.next_int(int(_preset.size_jitter));_random.next_int(int(_preset.size_jitter))
	return Appearance.start(_preset,_cursor,size_sample)

func move_particle(index: int,delta_ms: float) -> bool:
	var slot: Dictionary=_slots[index]
	if slot.appearance.age_ms<0:return true
	var appearance:=Appearance.advance(_preset,slot.appearance,delta_ms)
	if appearance.has("error"):return reject(appearance.error)
	slot.appearance=appearance
	if appearance.age_ms<0:slot.position=RESET_POSITION
	else:
		slot.position=Vectors.added(slot.position,Vectors.scaled(Vectors.scaled(slot.velocity,delta_ms),single(0.001)))
		if not slot.position.is_finite():return reject("Damage particle movement exceeds finite source bounds")
	return true

static func single(value: float) -> float:return Appearance.single(value)

static func divided(value: Vector3,divisor: float) -> Vector3:
	return Vector3(single(value.x/divisor),single(value.y/divisor),single(value.z/divisor))

static func inverse_length(value: Vector3) -> float:
	var square:=Vectors.dot(value,value)
	if not is_finite(square) or square<0:return NAN
	# Shared binary32 approximation used by the verified distance-spacing path.
	var bits:=PackedByteArray();bits.resize(4);bits.encode_float(0,square)
	bits.encode_u32(0,0x5f3759df-(bits.decode_u32(0)>>1))
	var estimate:=bits.decode_float(0)
	return single(single(single(single(single(square*-0.5)*estimate)*estimate)+1.5)*estimate)

func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:error=message;return {"error":message}
