extends RefCounted
## Shared native projectile pools for the verified ordinary NPC populations.
## The encounter owner decides who requests fire and when updates run. Target
## selection, shooter state, AI and mission consequences remain outside this owner.
## Explicit player updates apply contacts before each gun's movement and cleanup.
const Actor = preload("res://src/simulation/opening_combat_actor.gd")
const Definitions = preload("res://src/content/opening_npc_weapon_definitions.gd")
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Library = preload("res://src/content/library.gd")
const PlayerContacts = preload("res://src/simulation/ordinary_player_contacts.gd")
const Player = preload("res://src/simulation/opening_player_state.gd")
const Audio = preload("res://src/simulation/weapon_audio.gd")
const NPCContacts = preload("res://src/simulation/ordinary_npc_contacts.gd")
const Training = preload("res://src/content/combat_training_weapon_definitions.gd")
var error := ""
var _identity := {}
var _definition := {}
var _guns: Array = []
var _audio := {}
var _definitions := []
var _actor_audio := []
var _training := {}

func clear() -> void:
	error = ""
	_identity = {}
	_definition = {}
	_guns = []
	_audio = {}
	_definitions=[];_actor_audio=[];_training={}

func configure(bindings: RefCounted, catalogues: RefCounted) -> bool:
	clear()
	if not _matching_content(bindings,catalogues):return reject("NPC weapons require matching source content and bindings")
	var data: Variant = bindings.opening_actors.get("npc_initialization",{}).get("primary_weapon",{})
	if not Definitions.parameters(data): return reject("Source opening NPC weapons are unavailable")
	var rows: Variant = bindings.opening_actors.get("actors")
	if not rows is Array or rows.size()!=3: return reject("Source opening NPC population is unavailable")
	for i in rows.size():
		if rows[i].get("actor_id")!=i or rows[i].get("actor_kind")!=data.actor_kind or rows[i].get("hull_catalogue_id")!=[2,23,2][i]: return reject("NPC weapon declaration does not match the opening population")

	return _configure(bindings,catalogues,data,rows.size())

func configure_full_hold(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted) -> bool:
	clear()
	if Actor.full_hold_initial(bindings,catalogues,construction).is_empty():return reject("Second pirate weapons require its matching detached world")
	if not _configure(bindings,catalogues,bindings.full_hold_pirate.primary_weapon,1):return false
	_identity.campaign_cursor=int(bindings.full_hold_pirate.campaign_cursor)
	return true

static func _matching_content(bindings: RefCounted, catalogues: RefCounted) -> bool:
	return bindings!=null and catalogues!=null and Library.valid_hash(bindings.base_content_id) and Library.valid_hash(bindings.binding_id) and bindings.base_content_id==catalogues.content_id

func _configure(bindings: RefCounted, catalogues: RefCounted, data: Dictionary, count: int) -> bool:
	var rows:=[]
	for _id in count:rows.append(data)
	if not _configure_rows(bindings,catalogues,rows):return false
	_definition=data.duplicate(true);_audio=_actor_audio[0].duplicate()
	return true

func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, world: RefCounted, rank: Variant, difficulty: Variant) -> bool:
	clear()
	if not _matching_content(bindings,catalogues) or not Training.parameters(bindings.combat_training_weapons):return reject("This pack has no combat-training weapons")
	# The canonical combat constructor validates the retained four actors,
	# identities, entry rank and difficulty without consuming effect draws.
	var combat:=Combat.new()
	if not combat.configure_combat_training(bindings,catalogues,world,rank,difficulty):return reject(combat.error)
	if not _configure_rows(bindings,catalogues,bindings.combat_training_weapons.npc_weapons):return false
	_identity.campaign_cursor=int(bindings.combat_training_weapons.campaign_cursor)
	_training=bindings.combat_training_weapons.duplicate(true)
	for id in _training.target_memberships.size():_training.target_memberships[id]=_training.target_memberships[id].map(func(value):return int(value))
	return true

func _configure_rows(bindings: RefCounted, catalogues: RefCounted, rows: Array) -> bool:
	var guns:=[];var sounds:=[]
	for data in rows:
		var weapon:=_resolve_weapon(bindings,catalogues,data)
		if weapon.is_empty():return false
		var gun:=Projectiles.new()
		if not gun.configure(weapon):return reject(gun.error)
		guns.append(gun)
		var selected_audio:={}
		var audio: Dictionary=bindings.weapon_parameters.get("audio",{})
		if not audio.is_empty():
			selected_audio=Audio.npc_entry(audio,int(data.actor_kind))
			if selected_audio.is_empty():return reject("NPC lacks supported weapon sound selection")
		sounds.append(selected_audio)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_guns=guns;_actor_audio=sounds;_definitions=rows.duplicate(true)
	return true

func _resolve_weapon(bindings: RefCounted, catalogues: RefCounted, data: Dictionary) -> Dictionary:
	var items: Variant = catalogues.tables.get("items")
	if not items is Array or data.item_id>=items.size(): return fail("NPC weapon names an absent catalogue item")
	var arrays: Variant = items[int(data.item_id)].get("arrays")
	if not arrays is Array or arrays.size()!=3 or arrays[2].size()<6 or arrays[2][3]!=data.category or arrays[2][5]!=data.get("catalogue_kind",data.kind):
		return fail("NPC weapon catalogue category or kind disagrees with its declaration")
	if bindings.resolve(int(data.model_resource_id),"mesh").is_empty(): return fail("NPC weapon visual resource is unavailable")
	var weapon := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"launch_mode":"ordinary"}
	for key in ["item_id", "category", "kind", "damage", "interval_ms", "lifetime_ms", "projectile_capacity"]: weapon[key]=int(data[key])
	weapon.speed_units_per_millisecond=float(data.speed_units_per_millisecond)
	if data.has("nonplayer_source"):
		var policy: Dictionary=bindings.weapon_parameters.get("ordinary_hit_policy",{})
		var properties: Dictionary=items[int(data.item_id)].get("properties",{})
		var extra: Variant=properties.get(int(policy.get("additional_damage_property",-1)),int(policy.get("missing_additional_damage",0)))
		if extra!=int(policy.get("missing_additional_damage",0)) or policy.is_empty():return fail("NPC weapon requires unsupported additional damage")
		weapon.campaign_cursor=int(bindings.combat_training_weapons.campaign_cursor)
		weapon.nonplayer_source=bool(data.nonplayer_source)
		weapon.ordinary_hit_policy={"additional_damage":int(extra),"additional_damage_required":false,"nonplayer_damage":weapon.damage}
		weapon.collision_bounds={"mode":bindings.weapon_parameters.collision_bounds.mode}
	return weapon

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate()
	result.definition=_definition.duplicate(true)
	result.audio=_audio.duplicate()
	result.actors=[]
	for id in _guns.size():
		result.actors.append({"actor_id":id,"projectiles":_guns[id].snapshot()})
		if not _training.is_empty():
			result.actors[-1].definition=_definitions[id].duplicate(true)
			result.actors[-1].audio=_actor_audio[id].duplicate()
	return result

func fire(combat: RefCounted, requested_actor_ids: Array) -> Dictionary:
	return _fire(combat,requested_actor_ids,{})

func fire_combat_training(combat: RefCounted, requests: Array) -> Dictionary:
	error=""
	if _training.is_empty():return fail("This weapon owner has no combat-training firing requests")
	var ids:=[];var poses:={}
	for request in requests:
		if not request is Dictionary or request.size()!=3 or not request.get("actor_id") is int or not request.get("target_actor_id") is int:return fail("Invalid combat-training firing request")
		var id: int=request.actor_id
		if id<0 or id>=_guns.size() or poses.has(id) or not request.get("pose") is Transform3D or not request.pose.is_finite():return fail("Invalid combat-training firing pose")
		if not request.target_actor_id in _training.target_memberships[id]:return fail("Combat-training request names a target outside its membership")
		ids.append(id);poses[id]=request.pose
	return _fire(combat,ids,poses)

func _fire(combat: RefCounted, requested_actor_ids: Array, poses: Dictionary) -> Dictionary:
	error=""
	if _guns.is_empty() or not combat is Combat: return fail("NPC firing requires configured weapons and matching combat actors")
	var scene: Dictionary = combat.snapshot()
	for key in _identity:
		if scene.get(key)!=_identity[key]: return fail("NPC firing actors belong to another source profile")
	if not scene.get("actors") is Array or scene.actors.size()!=_guns.size():return fail("NPC firing population differs from its weapon pools")
	for id in _guns.size():
		if scene.actors[id].get("actor_id")!=id or scene.actors[id].get("actor_kind")!=_definitions[id].actor_kind:return fail("NPC firing membership differs from its weapon declaration")
	var seen := {}
	for id in requested_actor_ids:
		if not id is int or id<0 or id>=_guns.size() or seen.has(id): return fail("Invalid or duplicate NPC firing request")
		seen[id]=true
	var staged := []
	var results := []
	# Source NPC array order determines events, independently of request order.
	for id in _guns.size():
		var gun: RefCounted = _guns[id].fork_state()
		staged.append(gun)
		if not seen.has(id): continue
		var actor: Dictionary = scene.actors[id]
		var allowed: bool = actor.active and actor.firing_allowed and actor.vitals.hull>0
		var outcome := {"fired":false,"reason":"permission"}
		if allowed:
			var pose: Variant = poses.get(id,actor.get("pose"))
			if not pose is Transform3D or not pose.is_finite(): return fail("Active NPC firing requires its explicit finite source pose")
			# This constructor supplies zero local muzzle and spread. NPCs do not
			# use the player's catalogue mounts or its additional Z displacement.
			outcome=gun.fire(pose.origin,pose.basis.z,true)
			if outcome.is_empty(): return fail(gun.error)
		results.append({"actor_id":id,"outcome":outcome})
		if not _actor_audio[id].is_empty():
			var cues := []
			if outcome.fired:
				var cue := Audio.cue(_actor_audio[id],poses.get(id,actor.pose).origin)
				if not cue.is_empty():cues.append(cue)
			results[-1].audio_events=cues
	_guns=staged
	return {"actors":results}

func advance(delta_ms: Variant) -> Dictionary:
	error=""
	if _guns.is_empty() or not Vitals.integer(delta_ms): return fail("NPC projectiles require nonnegative integer milliseconds")
	var staged := []
	var results := []
	for id in _guns.size():
		var gun: RefCounted = _guns[id].fork_state()
		var result: Dictionary = gun.advance(delta_ms)
		if result.is_empty(): return fail(gun.error)
		staged.append(gun)
		results.append({"actor_id":id,"update":result})
	_guns=staged
	return {"actors":results}

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._identity=_identity.duplicate()
	copy._definition=_definition.duplicate(true)
	copy._audio=_audio.duplicate()
	copy._definitions=_definitions.duplicate(true);copy._actor_audio=_actor_audio.duplicate(true);copy._training=_training.duplicate(true)
	for gun in _guns: copy._guns.append(gun.fork_state())
	return copy

func evaluate_player_update(player: RefCounted, pose: Variant, shooter_states: Variant, special_flight: Variant, delta_ms: Variant) -> Dictionary:
	error=""
	if not _training.is_empty():return fail("Combat-training weapons require their complete mixed target pass")
	if _guns.is_empty() or not player is Player or not Vitals.integer(delta_ms) or not special_flight is bool:
		return fail("NPC player updates require configured owners, time and flight state")
	if not shooter_states is Array or shooter_states.size()!=_guns.size(): return fail("NPC player update requires every shooter's current state in actor order")
	for state in shooter_states:
		if not state is Dictionary or state.size()!=2 or not state.get("present") is bool or not state.get("hostile") is bool: return fail("Invalid NPC shooter state")
	var next: RefCounted=fork_for_frame()
	var staged_player: RefCounted=player.fork_for_frame()
	var operation := PlayerContacts.new()
	var events := []
	for id in _guns.size():
		var state: Dictionary=shooter_states[id]
		var contact := operation.evaluate(next._guns[id],staged_player,pose,state.present,state.hostile,special_flight)
		if contact.is_empty(): return fail(operation.error)
		var motion: Dictionary=contact.projectiles.advance(delta_ms)
		if motion.is_empty(): return fail(contact.projectiles.error)
		next._guns[id]=contact.projectiles;staged_player=contact.player
		events.append({"actor_id":id,"contacts":contact.contacts,"last_contact_actor":contact.last_contact_actor,"motion":motion})
	return {"weapons":next,"player":staged_player,"actors":events}

func evaluate_combat_training_update(player: RefCounted, pose: Variant, combat: RefCounted, special_flight: Variant, delta_ms: Variant) -> Dictionary:
	error=""
	if _training.is_empty() or not player is Player or not combat is Combat or not Vitals.integer(delta_ms) or not special_flight is bool:return fail("Mixed contacts require the verified training weapon, player and combat owners")
	var player_state: Dictionary=player.snapshot();var scene: Dictionary=combat.snapshot()
	for key in _identity:
		if player_state.get(key)!=_identity[key] or scene.get(key)!=_identity[key]:return fail("Mixed contact owners belong to another encounter")
	if not scene.get("actors") is Array or scene.actors.size()!=_guns.size():return fail("Mixed contacts require the complete NPC population")
	for id in _guns.size():
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:
			if scene.actors[id].get(key)!=_definitions[id][key]:return fail("Mixed contact population changed")
	var shooters: Array=combat.shooter_states()
	var next:=fork_for_frame();var staged_player: RefCounted=player.fork_for_frame();var staged_combat: RefCounted=combat.fork_for_frame()
	var player_contacts:=PlayerContacts.new();var npc_contacts:=NPCContacts.new();var events:=[]
	for id in _guns.size():
		var contact:=player_contacts.evaluate(next._guns[id],staged_player,pose,shooters[id].present,shooters[id].hostile,special_flight)
		if contact.is_empty():return fail(player_contacts.error)
		var targets: Array=_training.target_memberships[id].slice(1).map(func(value):return int(value))
		var npc:=npc_contacts.evaluate(contact.projectiles,staged_combat,targets)
		if npc.is_empty():return fail(npc_contacts.error)
		# Retained impact geometry visits every target before this gun moves or
		# clears a slot. A player contact can therefore also hit an overlapping NPC.
		var motion: Dictionary=npc.projectiles.advance(delta_ms)
		if motion.is_empty():return fail(npc.projectiles.error)
		next._guns[id]=npc.projectiles;staged_player=contact.player;staged_combat=npc.combat
		var last: Variant={"group":"npc","index":npc.last_contact_actor_id} if npc.last_contact_actor_id!=null else contact.last_contact_actor
		events.append({"actor_id":id,"contacts":contact.contacts,"npc_contacts":npc.contacts,"last_contact_actor":last,"motion":motion})
	return {"weapons":next,"player":staged_player,"combat":staged_combat,"actors":events}

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
