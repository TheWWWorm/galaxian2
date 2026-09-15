extends RefCounted
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
## Native freighter breakup and retained wreck. Flight resolves the lethal pose;
## the encounter separately owns accounting, player salvage and world effects.
const Definitions=preload("res://src/content/freighter_destruction_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const Resources=preload("res://src/content/freighter_destruction_resources.gd")
const Motion=preload("res://src/simulation/freighter_motion.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const ConstructionRules=preload("res://src/content/npc_construction_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Explosion=preload("res://src/simulation/type_zero_explosion.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Volumes=preload("res://src/content/station_collision_volumes.gd")
var error:=""
var _state:={}
var _rules:={}
var _construction_rules:={}
var _resources:={}
var _max_ms:=0
var _identity: RefCounted

func configure(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if bindings==null or not resources is Resources or not Definitions.parameters(bindings.freighter_destruction):return reject("Freighter death requires its source declarations and resources")
	var motion:=Motion.new()
	if not motion.configure(bindings,construction,actor_id):return reject(motion.error)
	var packet: Dictionary=construction.snapshot()
	var rules:=Definitions.for_free(bindings,int(packet.actors[actor_id].actor_kind),packet.free_context) if packet.has("free_context") else Definitions.for_context(bindings,packet.campaign_cursor,packet.population.station_id)
	return _configure_population(bindings,resources,construction,actor_id,rules)

func configure_convoy(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is Construction or not resources is Resources:return reject("Capital-ship death requires its generated encounter and resources")
	var data:=Convoy.lifecycle(bindings,construction.snapshot())
	var motion:=Motion.new()
	if data.is_empty() or not actor_id is int or not motion.configure_convoy(bindings,actor_id):return reject("Unsupported convoy capital-ship death")
	var row: Dictionary=construction.snapshot().actors[actor_id]
	if row.body_pose!=motion.snapshot().body_pose or row.population_group!="capital":return reject("Capital-ship death changed the initial convoy pose")
	return _configure_population(bindings,resources,construction,actor_id,Definitions.for_convoy(bindings))

func configure_alioth_attack(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor_id: Variant) -> bool:
	clear()
	if not construction is Construction or not resources is Resources:return reject("Alioth freighter death requires its original resources")
	var motion:=Motion.new()
	if not motion.configure_alioth_attack(bindings,construction,actor_id):return reject(motion.error)
	return _configure_population(bindings,resources,construction,actor_id,Definitions.for_alioth(bindings))

func _configure_population(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor_id: int,rules: Dictionary) -> bool:
	if rules.is_empty():return reject("Unsupported large-ship lifecycle context")
	var population: Dictionary=construction.snapshot()
	var row: Dictionary=population.actors[int(actor_id)]
	var pack: Dictionary=resources.for_faction(int(row.actor_kind))
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if pack.get(key)!=population.get(key):return reject("Freighter death resources belong to another population")
	if pack.get("model",{}).get("model_id")!=int(rules.model_id) or pack.get("cargo_model",{}).get("model_id")!=int(rules.cargo_model_id) or pack.get("initial_material",{}).get("id")!=int(rules.initial_material_id) or pack.get("wreck_material",{}).get("id")!=int(rules.wreck_material_id):return reject("Freighter destruction resources have another faction's models")
	if not valid_cargo(row.get("cargo")) or not row.get("fragments") is Array or not row.fragments.is_empty():return reject("Freighter death requires retained cargo and delayed debris construction")
	var shared: Dictionary=bindings.opening_actors.get("npc_initialization",{}).get("construction",{})
	if not ConstructionRules.parameters(shared):return reject("Freighter debris requires verified shared sampling")
	var model:=Explosion.model_clock(pack.get("model"))
	var effect:=Explosion.create(pack,[],int(shared.fragment_resource))
	if model.is_empty() or effect.is_empty():return reject("Invalid freighter animation or explosion clocks")
	_rules=rules.duplicate(true);_construction_rules=shared.duplicate(true);_resources=pack
	if _rules.is_empty():return reject("Unsupported freighter lifecycle context")
	_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(_rules.campaign_cursor),
		"actor_id":int(actor_id),"population_group":row.population_group,"model_scale":float(rules.get("model_scale",1.0)),"actor_kind":int(_rules.actor_kind),"hull_catalogue_id":int(_rules.hull_catalogue_id),"subtype":int(_rules.subtype),
		"phase":"ready","mode":0,"pose":row.body_pose,"statistics_pose":row.statistics_pose,"active":true,
		"world_movement_enabled":true,"interaction_blocked":true,"animation":model,"wreck_elapsed_ms":0,"cleanup_elapsed_ms":0,
		"material_id":int(_rules.initial_material_id),"wreck_shape_origin":Vector3.ZERO,"wreck_shapes":pack.wreck_shapes.duplicate(true),
		"fragments":[],"effect":effect,"effect_scale":float(_rules.initial_effect_scale),
		"cargo":{"entries":row.cargo.duplicate(true),"eligible":not row.cargo.is_empty(),"model_exists":false,
			"model_id":int(_rules.cargo_model_id),"resource":pack.cargo_model.resource,"pose":Transform3D.IDENTITY,"rotation_radians":Vector3.ZERO}}
	_identity=RefCounted.new()
	return true

func advance(delta_ms: Variant,random_state: Variant,lethal_actor: Dictionary={}) -> Dictionary:
	error=""
	if _state.is_empty() or not Vitals.integer(delta_ms) or delta_ms>_max_ms:return fail("Invalid freighter destruction duration")
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	var next:=_state.duplicate(true);var started: bool=next.phase=="ready";var breakup:=false;var cleaned:=false
	var sounds: Array[Dictionary]=[]
	if started:
		if not fresh_lethal(lethal_actor):return fail("Freighter death requires its fresh, exhausted native combat actor")
		next.pose=lethal_actor.body_pose;next.statistics_pose=next.pose
		next.phase="animation";next.mode=int(_rules.animation_mode);next.world_movement_enabled=false
		next.interaction_blocked=bool(_rules.interaction_blocked_during_animation)
		if next.cargo.eligible:
			next.cargo.model_exists=true;next.cargo.pose=Transform3D(Basis.IDENTITY,next.pose.origin)
		next.fragments=Construction.sample_fragments(random,_construction_rules)
		next.effect=Explosion.create(_resources,next.fragments,int(_construction_rules.fragment_resource))
		if next.effect.is_empty():return fail("Freighter debris failed to construct")
		Explosion.trigger(next.effect,next.pose.origin)
		sounds.append({"source_id":int(_rules.initial_sound_id),"position":next.pose.origin})
		sounds.append(effect_sound(random,next.pose.origin))
	elif not lethal_actor.is_empty():return fail("Freighter destruction was already started")
	# Each actor pass advances the current phase only. Finishing the animation
	# starts a fresh explosion; no excess time leaks into the wreck timers.
	Explosion.advance(next.effect,int(delta_ms))
	if next.phase=="animation":
		Playback.advance([next.animation],int(delta_ms))
		if not next.animation.playing:
			next.phase="wreck";next.mode=int(_rules.wreck_mode);breakup=true
			next.effect=Explosion.create(_resources,next.fragments,int(_construction_rules.fragment_resource))
			next.effect_scale=float(_rules.final_effect_scale)
			Explosion.trigger(next.effect,next.pose.origin)
			sounds.append(effect_sound(random,next.pose.origin))
	else:
		next.wreck_elapsed_ms+=int(delta_ms);next.cleanup_elapsed_ms+=int(delta_ms)
		var cargo_present: bool=next.cargo.eligible and next.active and next.cargo.model_exists
		if cargo_present:
			var radians:=Vitals.single(Vitals.single(float(delta_ms >> int(_rules.cargo_rotation_delta_shift))*float(_rules.cargo_angle_fraction))*float(_rules.cargo_angle_tau))
			var angle:=float(int(radians))
			next.cargo.rotation_radians=Vectors.added(next.cargo.rotation_radians,Vector3.ONE*angle)
			next.cargo.pose.basis=Vectors.local_xyz(next.cargo.rotation_radians)
		if (cargo_present and next.cleanup_elapsed_ms>int(_rules.cleanup_after_ms)) or (not cargo_present and not next.effect.active):
			next.interaction_blocked=true
			if next.cleanup_elapsed_ms>int(_rules.cleanup_after_ms):cleaned=next.active;next.active=false
		if next.wreck_elapsed_ms>=int(_rules.wreck_change_at_ms) and next.material_id==int(_rules.initial_material_id):
			next.material_id=int(_rules.wreck_material_id);next.wreck_shape_origin=next.pose.origin
	_state=next
	return {"state":snapshot(),"random_state":random.snapshot(),"started":started,"breakup":breakup,"cleaned_now":cleaned,"audio_events":sounds}

func fresh_lethal(actor: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor","actor_id","actor_kind","hull_catalogue_id","subtype"]:
		if actor.get(key)!=_state[key]:return false
	var vitals: Variant=actor.get("vitals")
	return vitals is Dictionary and vitals.get("hull") is int and vitals.hull==0 and actor.get("population_group")==_state.population_group and actor.get("local_combat")==true and actor.get("active")==true and actor.get("actor_mode")==0 and Flight.rigid_pose(actor.get("body_pose"))

func effect_sound(random: RefCounted,position: Vector3) -> Dictionary:
	return {"source_id":int(_rules.effect_sound_base)+random.next_int(int(_rules.effect_sound_bound)),"position":position}

func wreck_point(point: Variant) -> Dictionary:
	error=""
	if _state.is_empty() or _state.phase!="wreck" or not point is Vector3 or not point.is_finite():return fail("Wreck contact requires its completed animation and a finite sample")
	for index in _state.wreck_shapes.size():
		var shape: Dictionary=_state.wreck_shapes[index]
		var center:=Vectors.added(_state.wreck_shape_origin,shape.center)
		var hit:=Volumes.contains_point(point,center,shape.half_extents) if shape.kind==1 else Volumes.contains_sphere(point,center,shape.radius)
		if hit:return {"hit":true,"shape_index":index}
	return {"hit":false}

static func valid_cargo(entries: Variant) -> bool:
	if not entries is Array or entries.size()>233:return false
	for entry in entries:
		if not entry is Dictionary or entry.size()!=2 or not Vitals.integer(entry.get("item_id")) or entry.item_id>=233 or not Vitals.integer(entry.get("quantity")) or entry.quantity<1:return false
	return true

func snapshot() -> Dictionary:return _state.duplicate(true)
func presentation_identity() -> RefCounted:return _identity
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true);copy._resources=_resources.duplicate(true)
	copy._construction_rules=_construction_rules.duplicate(true);copy._max_ms=_max_ms;copy._identity=_identity
	return copy
func clear() -> void:error="";_state={};_rules={};_resources={};_construction_rules={};_max_ms=0;_identity=null
func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:error=message;return {}
