extends RefCounted
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
const AliothSequence=preload("res://src/simulation/alioth_attack.gd")
## Native NPC death motion and retained animation clocks. The encounter owner must
## enter at a verified lethal frame, after selection and before live-mode flight.
## Accounting, particles, sound playback and camera shake have separate owners.
const Definitions = preload("res://src/content/npc_destruction_definitions.gd")
const FullHold = preload("res://src/content/full_hold_destruction_definitions.gd")
const Training = preload("res://src/content/combat_training_destruction_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Ambient=preload("res://src/content/ambient_combat_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Appearance=preload("res://src/content/full_hold_appearance_definitions.gd")
const Resources = preload("res://src/content/npc_destruction_resources.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Frames = preload("res://src/simulation/frame_clock.gd")
const Flight = preload("res://src/simulation/npc_flight.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Vectors = preload("res://src/simulation/source_vectors.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Explosion = preload("res://src/simulation/type_zero_explosion.gd")
var error := ""
var _parameters := {}
var _state := {}
var _max_ms := 0
var _presentation_identity: RefCounted
var _cargo_rules := {}

func configure(bindings: RefCounted, resources: RefCounted, actor_id: Variant, pose: Variant, speed: Variant, fragments: Array) -> bool:
	clear()
	if not bindings is Bindings or not actor_id is int or actor_id<0 or actor_id>=bindings.opening_actors.get("actors",[]).size():return reject("Unsupported NPC death actor")
	if bindings.opening_actors.actors[actor_id].actor_kind!=bindings.opening_actors.get("npc_initialization",{}).get("destruction",{}).get("actor_kind"):return reject("Unsupported NPC death actor")
	return _configure_motion(bindings,resources,actor_id,pose,speed,fragments)

func _configure_motion(bindings: RefCounted, resources: RefCounted, actor_id: int, pose: Variant, speed: Variant, fragments: Array) -> bool:
	if not bindings is Bindings or not resources is Resources or not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id): return reject("NPC death requires source-bound resources")
	var parameters: Variant=bindings.opening_actors.get("npc_initialization",{}).get("destruction")
	if not Definitions.parameters(parameters) or not Frames.valid_parameters(bindings.frame_clock): return reject("NPC death declarations are unavailable")
	if not Flight.rigid_pose(pose): return reject("NPC death requires a finite source ship pose")
	if not (speed is float or speed is int) or not is_finite(speed) or speed<0 or not is_finite(Vitals.single(speed)): return reject("NPC death requires a finite nonnegative speed")
	var effect: Dictionary=resources.snapshot()
	if effect.get("base_content_id")!=bindings.base_content_id or effect.get("binding_id")!=bindings.binding_id: return reject("NPC death resources belong to another content identity")
	if not effect.get("models") is Array or effect.models.size()!=3: return reject("NPC death requires its three source model resources")
	if fragments.size()<3 or fragments.size()>9: return reject("NPC death requires retained constructor fragments")
	var clock:=Explosion.create(effect,fragments,int(parameters.fragment_model_id))
	if clock.is_empty():return reject("Invalid retained NPC fragments or animation ranges")
	_parameters=parameters.duplicate(true)
	_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actor_id":actor_id,
		"phase":"ready","mode":-1,"pose":pose,"forward":pose.basis.z,"speed":Vitals.single(speed),
		"spin":Vector3.ZERO,"countdown_ms":0,"cleanup_elapsed_ms":0,
		"drift_speed":0.0,"drift_direction":Vector3.ZERO,"fragments":fragments.duplicate(true),
		"effect":clock}
	_presentation_identity=RefCounted.new()
	return true

func configure_full_hold(bindings: RefCounted, resources: RefCounted, actor: Dictionary) -> bool:
	clear()
	if not bindings is Bindings or not resources is Resources or not FullHold.parameters(bindings.full_hold_destruction):return reject("Second-trip death requires verified cargo resources and declarations")
	var rules: Dictionary=bindings.full_hold_destruction
	for key in ["actor_id","actor_kind","hull_catalogue_id","subtype"]:
		if not actor.get(key) is int or actor[key]!=int(rules[key]):return reject("Unsupported cargo-bearing death actor")
	return _configure_cargo(bindings,resources,actor,rules,resources.snapshot().get("cargo_model"))

func configure_combat_training(bindings: RefCounted, resources: RefCounted, actor: Dictionary) -> bool:
	clear()
	if not bindings is Bindings or not resources is Resources or not Training.parameters(bindings.combat_training_destruction):return reject("Training death requires verified cargo resources and declarations")
	var data: Dictionary=bindings.combat_training_destruction
	var id: Variant=actor.get("actor_id")
	if not id is int or id<0 or id>=int(data.actor_count):return reject("Unsupported training death actor")
	for key in ["actor_id","actor_kind","hull_catalogue_id","subtype"]:
		if not actor.get(key) is int or actor[key]!=int(data.actors[id][key]):return reject("Training death actor changed")
	for key in ["base_content_id","binding_id"]:
		if actor.get(key)!=bindings.get(key):return reject("Training death actor belongs to another content pack")
	if actor.get("campaign_cursor")!=int(data.campaign_cursor):return reject("Training death actor belongs to another encounter")
	var pack: Dictionary=resources.snapshot()
	if pack.get("campaign_cursor")!=int(data.campaign_cursor) or not pack.get("cargo_models") is Array or pack.cargo_models.size()!=int(data.actor_count):return reject("Training death requires all cargo models")
	var rules: Dictionary=data.cargo.duplicate(true)
	rules.merge(data.actors[id]);rules.campaign_cursor=int(data.campaign_cursor)
	return _configure_cargo(bindings,resources,actor,rules,pack.cargo_models[id])

func _configure_cargo(bindings: RefCounted, resources: RefCounted, actor: Dictionary, rules: Dictionary, model: Variant) -> bool:
	var entries: Variant=actor.get("cargo")
	if not entries is Array or not actor.get("fragments") is Array:return reject("NPC death requires retained cargo and fragments")
	for entry in entries:
		if not entry is Dictionary or entry.size()!=2 or not Vitals.integer(entry.get("item_id")) or entry.item_id>=233 or not Vitals.integer(entry.get("quantity")) or entry.quantity<1:return reject("Invalid retained pirate cargo")
	if not model is Dictionary or model.get("model_id")!=int(rules.cargo_model_id) or model.get("resource")!=rules.cargo_model_resource:return reject("NPC death lacks its container model")
	if not _configure_motion(bindings,resources,int(rules.actor_id),actor.get("body_pose"),0.0,actor.fragments):return false
	_cargo_rules=rules.duplicate(true)
	_state.campaign_cursor=int(rules.campaign_cursor)
	_state.statistics_pose=_state.pose
	_state.bank_basis=Basis.IDENTITY
	_state.cargo={"entries":entries.duplicate(true),"eligible":not entries.is_empty(),"model_exists":false,
		"model_id":int(rules.cargo_model_id),"resource":String(model.resource),"pose":Transform3D.IDENTITY,"rotation_radians":Vector3.ZERO}
	return true

func configure_contract(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor: Dictionary) -> bool:
	clear()
	if not construction is Construction or not resources is Resources:return reject("Contract death requires its generated population and cargo resources")
	var packet: Dictionary=construction.snapshot()
	var data:=ContractLife.population(bindings,packet)
	var id: Variant=actor.get("actor_id")
	if data.is_empty() or not Vitals.integer(id) or id>=int(data.actor_count):return reject("Unsupported contract death actor")
	for key in ["actor_kind","hull_catalogue_id","subtype","population_group","cargo","fragments"]:
		if actor.get(key)!=packet.actors[id].get(key):return reject("Contract death changed its retained construction")
	var pack: Dictionary=resources.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if actor.get(key)!=packet.get(key) or pack.get(key)!=packet.get(key):return reject("Contract death belongs to another encounter")
	if pack.get("contract_encounter")!=packet.contract_encounter or not pack.get("cargo_models") is Array or pack.cargo_models.size()!=int(data.actor_count):return reject("Contract death lacks its prepared cargo models")
	var rules: Dictionary=data.cargo.duplicate(true)
	rules.merge(data.actors[id]);rules.campaign_cursor=int(data.campaign_cursor)
	return _configure_cargo(bindings,resources,actor,rules,pack.cargo_models[id])

func configure_convoy(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor: Dictionary) -> bool:
	clear()
	if not construction is Construction or not resources is Resources:return reject("Convoy death requires its generated population and resources")
	var packet: Dictionary=construction.snapshot()
	var data:=Convoy.lifecycle(bindings,packet)
	var id: Variant=actor.get("actor_id")
	if data.is_empty() or not Vitals.integer(id) or id>=int(data.actor_count) or actor.get("population_group")!="fighter":return reject("Unsupported convoy small-ship death")
	for key in ["actor_kind","hull_catalogue_id","subtype","population_group","cargo","fragments"]:
		if actor.get(key)!=packet.actors[id].get(key):return reject("Convoy death changed its retained construction")
	var pack: Dictionary=resources.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if actor.get(key)!=packet.get(key) or pack.get(key)!=packet.get(key):return reject("Convoy death belongs to another encounter")
	if pack.get("convoy_context")!=packet.convoy_context or not pack.get("cargo_models") is Array or pack.cargo_models.size()!=int(data.actor_count):return reject("Convoy death lacks its cargo models")
	var rules: Dictionary=data.cargo.duplicate(true)
	rules.merge(data.actors[id]);rules.campaign_cursor=int(data.campaign_cursor)
	return _configure_cargo(bindings,resources,actor,rules,pack.cargo_models[id])

func configure_alioth_attack(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor: Dictionary) -> bool:
	clear()
	if not construction is Construction or not resources is Resources:return reject("Alioth death requires its generated population and resources")
	var packet: Dictionary=construction.snapshot()
	var data:=Alioth.lifecycle(bindings,packet)
	var id: Variant=actor.get("actor_id")
	if data.is_empty() or not Vitals.integer(id) or id>=int(data.actor_count) or actor.get("population_group")!="fighter":return reject("Unsupported Alioth small-ship death")
	for key in ["actor_kind","hull_catalogue_id","subtype","population_group","cargo","fragments"]:
		if actor.get(key)!=packet.actors[id].get(key):return reject("Alioth death changed its retained construction")
	var pack: Dictionary=resources.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if actor.get(key)!=packet.get(key) or pack.get(key)!=packet.get(key):return reject("Alioth death belongs to another encounter")
	if pack.get("alioth_context")!=packet.alioth_context or not pack.get("cargo_models") is Array or pack.cargo_models.size()!=int(data.actor_count):return reject("Alioth death lacks its cargo models")
	var rules: Dictionary=data.cargo.duplicate(true)
	rules.merge(data.actors[id]);rules.campaign_cursor=int(data.campaign_cursor)
	return _configure_cargo(bindings,resources,actor,rules,pack.cargo_models[id])


func configure_local_traffic(bindings: RefCounted, resources: RefCounted, actor: Dictionary, data: Dictionary) -> bool:
	clear()
	if not bindings is Bindings or not resources is Resources or not Travel.destruction_parameters(bindings,data):return reject("Local death requires its own cargo resources and declarations")
	var id: Variant=actor.get("actor_id")
	if not id is int or id<0 or id>=int(data.get("actor_count",0)) or data.actor_count not in [1,4]:return reject("Local death is outside its generated population")
	for key in ["actor_id","actor_kind","hull_catalogue_id","subtype"]:
		if not actor.get(key) is int or actor[key]!=int(data.actors[id][key]):return reject("Local death actor changed")
	for key in ["base_content_id","binding_id"]:
		if actor.get(key)!=bindings.get(key):return reject("Local death belongs to another content pack")
	var pack: Dictionary=resources.snapshot()
	if actor.get("campaign_cursor")!=10 or pack.get("campaign_cursor")!=10:return reject("Local death belongs to another encounter")
	var rules: Dictionary=data.cargo.duplicate(true)
	rules.merge(data.actors[id]);rules.campaign_cursor=10
	return _configure_cargo(bindings,resources,actor,rules,pack.get("cargo_model"))

func configure_ambient(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor: Dictionary) -> bool:
	clear()
	if not construction is Construction or not resources is Resources:return reject("Ambient death requires its generated construction and cargo resources")
	var packet: Dictionary=construction.snapshot()
	var ordinary:=FreeLife.population(bindings,packet) if packet.has("free_context") else {}
	if (packet.has("free_context") and ordinary.is_empty()) or (not packet.has("free_context") and Ambient.population(bindings,packet,0,0.5).is_empty()):return reject("Unsupported ambient death population")
	var id: Variant=actor.get("actor_id")
	if not Vitals.integer(id) or id>=packet.actors.size():return reject("Ambient death actor is outside its population")
	for key in ["actor_kind","hull_catalogue_id","subtype","population_group"]:
		if actor.get(key)!=packet.actors[id].get(key):return reject("Ambient death actor changed construction")
	if actor.population_group=="freighter":return reject("Freighter destruction has a separate native owner")
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if actor.get(key)!=packet.get(key) or resources.snapshot().get(key)!=packet.get(key):return reject("Ambient death belongs to another content identity")
	var rules: Dictionary=bindings.combat_training_destruction.cargo.duplicate(true)
	rules.merge(bindings.mido_travel.traffic_combat.death,true)
	rules.actor_id=id;rules.campaign_cursor=int(packet.campaign_cursor)
	var model: Variant=resources.snapshot().get("cargo_model")
	if not ordinary.is_empty():
		var models: Variant=resources.snapshot().get("cargo_models")
		if resources.snapshot().get("free_context")!=packet.free_context or not models is Array or models.size()!=packet.actors.size():return reject("Ordinary death requires its faction cargo models")
		rules.merge(ordinary.actors[id],true);model=models[id]
	if not _configure_cargo(bindings,resources,actor,rules,model):return false
	if actor.has("spawn_generation"):
		if not Vitals.integer(actor.spawn_generation):clear();return reject("Invalid ambient death generation")
		_state.spawn_generation=actor.spawn_generation
	return true

static func model_clock(model: Variant) -> Dictionary:
	return Explosion.model_clock(model)

func capture(pose: Variant, speed: Variant, bank: Basis=Basis.IDENTITY) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="ready": return reject("Capture NPC motion before starting its death")
	if not Flight.rigid_pose(pose) or not (speed is float or speed is int) or not is_finite(speed) or speed<0 or not is_finite(Vitals.single(speed)): return reject("Invalid initial NPC death motion")
	if not Flight.rigid_pose(Transform3D(bank,Vector3.ZERO)):return reject("Invalid retained NPC bank")
	if _cargo_rules.is_empty() and bank!=Basis.IDENTITY:return reject("This death context has no separate bank owner")
	_state.pose=pose;_state.forward=pose.basis.z;_state.speed=Vitals.single(speed)
	if not _cargo_rules.is_empty():
		_state.bank_basis=bank
		_state.statistics_pose=pose*Transform3D(bank,Vector3.ZERO)
	return true

func reposition_full_hold(declarations: Dictionary, pose: Variant, statistics_pose: Variant) -> bool:
	error=""
	if _cargo_rules.is_empty() or not Appearance.parameters(declarations) or _state.get("appearance_applied",false) or not Flight.rigid_pose(pose) or not Flight.rigid_pose(statistics_pose):return reject("Scripted placement requires the unplaced pirate death owner and verified declarations")
	# Source activation changes mode but never heals or resets effect/cargo clocks.
	# An exhausted actor starts a new tumble on its next ordinary actor pass.
	_state.pose=pose;_state.statistics_pose=statistics_pose
	_state.phase="ready";_state.mode=1
	_state.appearance_applied=true
	return true

func apply_alioth_escape(owner: RefCounted) -> bool:
	error=""
	if not owner is AliothSequence or _state.get("campaign_cursor")!=16 or _cargo_rules.is_empty():return reject("Alioth placement requires its retained destruction owner")
	var sequence: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if sequence.get(key)!=_state[key]:return reject("Alioth destruction belongs to another sequence")
	if sequence.phase!=AliothSequence.Stage.ESCAPE_VIEW:return reject("No Alioth escape placement is pending")
	for row in sequence.frame.actor_overrides:
		if row.actor_id!=_state.actor_id:continue
		if not Flight.rigid_pose(row.body_pose):return reject("Invalid Alioth body placement")
		# The story moves the body even during breakup. It neither restarts death
		# nor moves already separated cargo, debris, or the statistics sample.
		_state.pose=row.body_pose
		return true
	return reject("Alioth escape does not relocate this actor")

func retires_before_update() -> bool:
	if _state.is_empty():return false
	return _state.phase=="retired" or (_state.phase=="explosion" and not _state.effect.active and (_cargo_rules.is_empty() or not _state.cargo.eligible or _state.cleanup_elapsed_ms>int(_cargo_rules.cleanup_after_ms)))

func advance(delta_ms: Variant, random_state: Variant) -> Dictionary:
	error=""
	if _state.is_empty() or not Vitals.integer(delta_ms) or delta_ms>_max_ms: return fail("Invalid NPC death frame duration")
	var random := Random.new()
	if not random.restore(random_state): return fail(random.error)
	var next := _state.duplicate(true)
	var started := false;var breakup := false;var expired := false;var retired := false
	var sounds := []
	var audio_events: Array[Dictionary]=[]
	# Early retirement precedes target selection. Cargo extends that lifetime;
	# its later cleanup branch can also retire in the pass that crosses 60 s.
	if next.phase!="retired" and retires_before_update():
		next.phase="retired";retired=true
	elif next.phase!="retired":
		if not _cargo_rules.is_empty():next.statistics_pose=next.pose*Transform3D(next.bank_basis,Vector3.ZERO)
		if next.phase=="ready":
			next.phase="tumble";next.mode=int(_parameters.dying_mode);started=true
			next.countdown_ms=int(_parameters.delay_base_ms)+random.next_int(int(_parameters.delay_bound_ms))
			next.spin=Vectors.scaled(random_direction(random),float(_parameters.spin_scale))
			sounds.append(int(_parameters.death_sound))
			audio_events.append({"source_id":int(_parameters.death_sound),"position":next.pose.origin})
		if next.phase=="tumble":
			var preceding_position: Vector3=next.pose.origin
			if delta_ms>0:
				# Native local X/Y/Z composition, once per source update. Spin is
				# independent of elapsed time; the captured travel direction is not.
				var spin: Vector3=next.spin
				next.pose.basis=next.pose.basis*Vectors.local_xyz(spin)
			next.pose.origin=Vectors.added(next.pose.origin,Vectors.scaled(Vectors.scaled(next.forward,Vitals.single(float(delta_ms))),next.speed))
			next.countdown_ms-=delta_ms
			if next.countdown_ms<0:
				breakup=true;next.phase="explosion";next.mode=int(_parameters.explosion_mode);next.countdown_ms=0
				Explosion.trigger(next.effect,preceding_position)
				sounds.append(int(_parameters.breakup_sound_base)+random.next_int(int(_parameters.breakup_sound_bound)))
				audio_events.append({"source_id":sounds.back(),"position":preceding_position})
				next.drift_speed=Vitals.single(Vitals.single(float(random.next_int(int(_parameters.drift_bound)))*float(_parameters.drift_scale))+float(_parameters.drift_base))
				next.drift_direction=random_direction(random)
				if not _cargo_rules.is_empty() and next.cargo.eligible:
					next.cargo.model_exists=true
					next.cargo.pose=Transform3D(Basis.IDENTITY,next.pose.origin)
					next.statistics_pose=next.cargo.pose
		else:
			next.countdown_ms+=delta_ms
			expired=Explosion.advance(next.effect,delta_ms)
			next.cleanup_elapsed_ms+=delta_ms
			if not _cargo_rules.is_empty():
				var moving: bool=next.cargo.eligible and next.cargo.model_exists and delta_ms>0
				if moving:
					if next.drift_speed>0:
						var displacement:=Vectors.scaled(next.drift_direction,next.drift_speed)
						next.cargo.pose.origin=Vectors.added(next.cargo.pose.origin,displacement)
						next.pose.origin=Vectors.added(next.pose.origin,displacement)
						var decayed:=Vitals.single(next.drift_speed*float(_cargo_rules.cargo_drift_decay))
						next.drift_speed=0.0 if decayed<float(_cargo_rules.cargo_drift_cutoff) else decayed
					var units:=float(delta_ms >> int(_cargo_rules.cargo_rotation_delta_shift))
					var radians:=Vitals.single(Vitals.single(units*float(_cargo_rules.cargo_angle_fraction))*float(_cargo_rules.cargo_angle_tau))
					# Source truncates the radians to an integer before rotation. All
					# supported frame durations consequently produce zero here.
					var angle:=Vitals.single(float(int(radians)))
					next.cargo.rotation_radians=Vectors.added(next.cargo.rotation_radians,Vector3.ONE*angle)
					next.cargo.pose.basis=Vectors.local_xyz(next.cargo.rotation_radians)
					next.statistics_pose=next.cargo.pose
				if next.cleanup_elapsed_ms>int(_cargo_rules.cleanup_after_ms) and not next.effect.active:
					if moving:
						next.cargo.model_exists=false;next.cleanup_elapsed_ms=0
					next.phase="retired";retired=true
	if not next.pose.is_finite() or not next.spin.is_finite() or not next.drift_direction.is_finite(): return fail("NPC death exceeded source coordinate precision")
	if not _cargo_rules.is_empty() and (not next.statistics_pose.is_finite() or not next.cargo.pose.is_finite()):return fail("NPC cargo exceeded source coordinate precision")
	_state=next
	return {"state":snapshot(),"random_state":random.snapshot(),"started":started,"breakup":breakup,
		"expired":expired,"retired_now":retired,"sound_events":sounds,"audio_events":audio_events}

func random_direction(random: RefCounted) -> Vector3:
	var value := Vector3.ZERO
	for axis in 3: value[axis]=random.next_int(int(_parameters.axis_bound))+int(_parameters.axis_offset)
	return Vectors.normalized(value)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func presentation_identity() -> RefCounted:
	return _presentation_identity

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._parameters=_parameters.duplicate(true);copy._state=_state.duplicate(true);copy._max_ms=_max_ms
	copy._presentation_identity=_presentation_identity
	copy._cargo_rules=_cargo_rules.duplicate(true)
	return copy

func clear() -> void:
	error="";_parameters={};_state={};_max_ms=0
	_presentation_identity=null
	_cargo_rules={}

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
