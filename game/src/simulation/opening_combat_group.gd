extends RefCounted
## Ordinary NPC ownership; Opening alone uses the radio activation cue. AI and weapon
## target-list selection remain distinct from this canonical actor-ID inventory.
const EscapeCamera=preload("res://src/content/opening_escape_camera_definitions.gd")
const HitDefinitions = preload("res://src/content/ordinary_hit_definitions.gd")
const WeaponHit = preload("res://src/simulation/ordinary_weapon_hit.gd")
const Actor = preload("res://src/simulation/opening_combat_actor.gd")
const Activation = preload("res://src/content/npc_activation_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const TrainingWeapons = preload("res://src/content/combat_training_weapon_definitions.gd")
var error := ""
var _actors := []
var _activation := {}
var _hit_policy := {}
var _training_weapons := {}
var _identity := {}
var _activated := false
var _phase := -1
var _event_count := 0
var _escape_enabled:=false

func clear() -> void:
	error = ""
	_actors = []
	_activation = {}
	_hit_policy = {}
	_training_weapons = {}
	_identity = {}
	_activated = false
	_phase = -1
	_event_count = 0
	_escape_enabled=false

func configure(bindings: RefCounted, catalogues: RefCounted, difficulty: Variant) -> bool:
	clear()
	if bindings == null or catalogues == null: return reject("Opening combat group requires source content")
	var initial: Variant = bindings.opening_actors.get("npc_initialization",{})
	if not initial is Dictionary: return reject("Invalid NPC initialization scope")
	var activation: Variant = initial.get("activation",{})
	if not activation is Dictionary or not Activation.parameters(activation): return reject("Source opening activation is unavailable")
	var rows: Variant = bindings.opening_actors.get("actors")
	if not rows is Array or rows.is_empty(): return reject("Source opening actor population is unavailable")
	var actors := []
	for id in rows.size():
		var actor := Actor.new()
		if not actor.configure(bindings,catalogues,id,difficulty): return reject(actor.error)
		actors.append(actor)
	for id in activation.actor_ids:
		if int(id)>=actors.size(): return reject("Activation names an absent opening actor")
	var events: Variant = bindings.opening_dialogue.get("events")
	if not events is Array or activation.after_event_finished>=events.size(): return reject("Activation event is outside the source radio sequence")
	if bindings.opening_camera.get("pan",{}).get("engagement_after_event_finished") != activation.after_event_finished:
		return reject("Actor activation and camera engagement gates disagree")
	var hit_policy: Variant = bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(hit_policy): return reject("Invalid NPC weapon hit policy")
	_hit_policy = hit_policy.duplicate(true)
	_actors = actors
	_activation = activation.duplicate(true)
	_activation.actor_ids = []
	for id in activation.actor_ids: _activation.actor_ids.append(int(id))
	_identity = {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_event_count = events.size()
	return true

func configure_full_hold(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted, difficulty: Variant) -> bool:
	clear()
	var actor:=Actor.new()
	if not actor.configure_full_hold(bindings,catalogues,construction,difficulty):return reject(actor.error)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Second pirate lacks the ordinary NPC weapon hit policy")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(bindings.full_hold_pirate.campaign_cursor)}
	_actors=[actor];_hit_policy=policy.duplicate(true)
	return true


func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant) -> bool:
	clear()
	var actors:=[]
	for id in 4:
		var actor:=Actor.new()
		if not actor.configure_combat_training(bindings,catalogues,world,id,rank,difficulty):return reject(actor.error)
		actors.append(actor)
	var policy: Variant=bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not HitDefinitions.parameters(policy):return reject("Combat training lacks the ordinary NPC weapon hit policy")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":7}
	_actors=actors;_hit_policy=policy.duplicate(true)
	if TrainingWeapons.parameters(bindings.combat_training_weapons):_training_weapons=bindings.combat_training_weapons.duplicate(true)
	return true

func apply_combat_training_guidance(data: Dictionary, decision: Dictionary) -> bool:
	error=""
	var id: Variant=decision.get("actor_id")
	if _identity.get("campaign_cursor")!=7 or _actors.size()!=4 or not id is int or id<0 or id>=_actors.size():return reject("Combat-training activity names an unavailable actor")
	if not _actors[id].apply_combat_training_guidance(data,decision):return reject(_actors[id].error)
	_activated=_activated or bool(_actors[id].snapshot().active)
	return true

func apply_full_hold_guidance(data: Dictionary, decision: Dictionary) -> bool:
	error=""
	if _identity.get("campaign_cursor")!=4 or _actors.size()!=1:return reject("This group has no second-trip activity context")
	if not _actors[0].apply_full_hold_guidance(data,decision):return reject(_actors[0].error)
	_activated=_activated or bool(_actors[0].snapshot().active)
	return true

func apply_full_hold_appearance(data: Dictionary, root: Variant, statistics: Variant) -> bool:
	error=""
	if _identity.get("campaign_cursor")!=4 or _actors.size()!=1:return reject("This group has no second-trip appearance context")
	if not _actors[0].apply_full_hold_appearance(data,root,statistics):return reject(_actors[0].error)
	_activated=true
	return true

func configure_escape(bindings: RefCounted) -> bool:
	error=""
	if _activation.is_empty() or _escape_enabled or _phase>0 or bindings==null or bindings.binding_id!=_identity.get("binding_id") or not EscapeCamera.parameters(bindings.opening_staging.get("escape_camera",{})):
		return reject("Escape actor lifecycle requires matching fresh declarations")
	_escape_enabled=true
	return true

func update(scene: Variant, phase: Variant, preceding_radio: Variant) -> bool:
	error = ""
	if _actors.is_empty() or _activation.is_empty(): return reject("This combat group has no Opening radio activation owner")
	if not Numbers.integer(phase,0,16 if _escape_enabled else 4) or phase<_phase: return reject("Opening combat phase is invalid or regressed")
	if not preceding_radio is Dictionary: return reject("Opening activation requires preceding radio state")
	for key in _identity:
		if preceding_radio.get(key)!=_identity[key]: return reject("Activation radio belongs to another content identity")
	var finished: Variant = preceding_radio.get("finished")
	if not finished is Array or finished.size()!=_event_count: return reject("Activation radio completion flags are unavailable")
	for done in finished:
		if not done is bool: return reject("Invalid activation radio completion flag")
	if phase>4:
		if not _activated or not finished[10]:return reject("Escape precedes its earned encounter radio")
		for actor in _actors:
			if actor.snapshot().vitals.hull>0:return reject("Escape cannot bypass a surviving opening actor")
	var activate_now: bool = not _activated and phase>=int(_activation.phase)
	if activate_now and not finished[int(_activation.after_event_finished)]: return reject("Opening activation precedes its source radio gate")
	var staged := []
	for actor in _actors:
		var next: RefCounted = actor.fork_for_frame()
		if not next.apply_scene(scene): return reject(next.error)
		if activate_now and next.snapshot().actor_id in _activation.actor_ids:
			if not next.apply_activation(_activation): return reject(next.error)
		staged.append(next)
	_actors = staged
	_phase = int(phase)
	_activated = _activated or activate_now
	return true

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate()
	result.activated = _activated
	result.phase = _phase
	result.actors = []
	for actor in _actors: result.actors.append(actor.snapshot())
	return result

func normal_hit(actor_id: Variant, amount: Variant, nonplayer_source: Variant=false) -> Dictionary:
	error = ""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size():
		reject("Normal hit names an unavailable opening actor")
		return {}
	var result: Dictionary = _actors[actor_id].normal_hit(amount,nonplayer_source)
	if result.is_empty(): reject(_actors[actor_id].error)
	return result

func set_pose(actor_id: Variant, pose: Variant, physical_pose: Variant=null) -> bool:
	error=""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size(): return reject("Pose names an unavailable opening actor")
	if not _actors[actor_id].set_pose(pose,physical_pose): return reject(_actors[actor_id].error)
	return true

func refresh_hostility(actor_id: Variant) -> bool:
	error=""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size(): return reject("Hostility names an unavailable opening actor")
	if not _actors[actor_id].refresh_hostility(): return reject(_actors[actor_id].error)
	return true

func apply_destruction(actor_id: Variant, death: Dictionary) -> bool:
	error=""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size(): return reject("Destruction names an unavailable opening actor")
	if not _actors[actor_id].apply_destruction(death): return reject(_actors[actor_id].error)
	return true

func shooter_states() -> Array:
	error=""
	if _actors.is_empty():
		reject("Configure opening actors before reading shooter state")
		return []
	var result := []
	for actor in _actors:
		var state: Dictionary=actor.snapshot()
		if not state.get("hostile") is bool:
			reject("Current NPC hostility is unavailable")
			return []
		# Source guns retain their statistics owner even while it is inactive.
		result.append({"present":true,"hostile":state.hostile})
	return result

func supports_weapon_hit(weapon: Variant) -> bool:
	var kinds: Array=[0]
	if not _training_weapons.is_empty() and weapon is Dictionary:
		if weapon.get("nonplayer_source",false)==true:
			if not TrainingWeapons.npc_hit(_training_weapons,weapon):return reject("NPC damage differs from this encounter's weapon declaration")
			kinds=[0,1]
		elif weapon.get("kind")==2:
			if not TrainingWeapons.dispersed_primary(weapon):return reject("Player damage lacks its verified primary declaration")
			kinds=[0,2]
	elif weapon is Dictionary and weapon.get("nonplayer_source",false)==true:return reject("This group has no verified NPC weapon contact path")
	error = WeaponHit.validate(weapon,_identity,_hit_policy,kinds)
	return error.is_empty()

func weapon_hit(actor_id: Variant, weapon: Variant) -> Dictionary:
	if not supports_weapon_hit(weapon): return {}
	return normal_hit(actor_id,weapon.ordinary_hit_policy.nonplayer_damage,weapon.get("nonplayer_source",false))

func record_contact(actor_id: Variant, incoming_velocity: Variant) -> bool:
	error = ""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size():
		return reject("Contact names an unavailable opening actor")
	if not _actors[actor_id].record_contact(incoming_velocity): return reject(_actors[actor_id].error)
	return true

func collision_context(actor_id: Variant) -> Dictionary:
	error = ""
	if not actor_id is int or actor_id<0 or actor_id>=_actors.size():
		reject("Collision target names an unavailable opening actor")
		return {}
	return _actors[actor_id].collision_context()

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._identity = _identity.duplicate()
	copy._activation = _activation.duplicate(true)
	copy._hit_policy = _hit_policy.duplicate(true)
	copy._training_weapons = _training_weapons.duplicate(true)
	copy._activated = _activated
	copy._phase = _phase
	copy._event_count = _event_count
	copy._escape_enabled=_escape_enabled
	for actor in _actors: copy._actors.append(actor.fork_for_frame())
	return copy

func reject(message: String) -> bool:
	error = message
	return false
