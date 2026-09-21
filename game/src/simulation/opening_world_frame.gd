extends RefCounted
## Fresh opening world with optional ordinary player-flight ownership. The native
## encounter stops at the unsupported postcombat or player-death transition.
const ControlGroup = preload("res://src/simulation/opening_npc_control.gd")
const Weapons = preload("res://src/simulation/opening_npc_weapons.gd")
const Timeline = preload("res://src/simulation/opening_detail_timeline.gd")
const Scenery = preload("res://src/simulation/opening_scenery.gd")
const PlayerState = preload("res://src/simulation/opening_player_state.gd")
const PlayerMotion = preload("res://src/simulation/opening_player_motion.gd")
const Impacts = preload("res://src/simulation/ordinary_impact_state.gd")
const ProjectileVisuals = preload("res://src/simulation/projectile_visual_state.gd")
const PlayerFlight = preload("res://src/simulation/opening_player_flight.gd")
const Primaries = preload("res://src/simulation/primary_weapons.gd")
const Mounts = preload("res://src/content/weapon_mounts.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Inventory = preload("res://src/simulation/opening_target_inventory.gd")
const Scanner = preload("res://src/simulation/opening_npc_scanner.gd")
const Aim = preload("res://src/simulation/opening_aim.gd")
const DamageParticles=preload("res://src/simulation/opening_damage_particles.gd")
const EngineAudio=preload("res://src/simulation/opening_engine_audio.gd")
var error := ""
var _identity := {}
var _controller: RefCounted
var _weapons: RefCounted
var _player_hull := 0
var _player_state: RefCounted
var _events := []
var _elapsed_ms := 0
var _random_state := {}
var _scenery_identity: RefCounted
var _player_contacts := false
var _weapon_events := []
var _player_recharge := false
var _player_repair := false
var _player_motion: RefCounted
var _player_motion_event := {}
var _projectile_visuals: RefCounted
var _impacts: RefCounted
var _flight: RefCounted
var _primaries: RefCounted
var _inventory: RefCounted
var _primary_contacts := []
var _primary_fire := {}
var _aim: RefCounted
var _scanner: RefCounted
var _damage_particles: RefCounted
var _engine_audio: RefCounted

func configure_engine_audio(bindings: RefCounted,catalogues: RefCounted,scene: Dictionary) -> bool:
	error=""
	if _controller==null or _player_state==null or _elapsed_ms!=0 or _engine_audio!=null or bindings==null or bindings.binding_id!=_identity.get("binding_id"):return reject("Player engine must join its fresh world once")
	var engine:=EngineAudio.new()
	if not engine.configure(bindings,catalogues,scene):return reject(engine.error)
	_engine_audio=engine;return true

func configure(bindings: RefCounted, catalogues: RefCounted, scenery: RefCounted, difficulty: Variant, death_resources: RefCounted = null) -> bool:
	clear()
	if bindings==null or catalogues==null or not scenery is Scenery: return reject("Opening frame requires its initialized world")
	var world: Dictionary=scenery.snapshot().get("world_initialization",{})
	if world.is_empty() or world.get("base_content_id")!=bindings.base_content_id or world.get("binding_id")!=bindings.binding_id:
		return reject("Opening frame requires matching world initialization")
	if scenery.snapshot().random_state!=world.random_state:
		return reject("Opening frame cannot reset an already advanced world stream")
	var controller := ControlGroup.new();var weapons := Weapons.new()
	if not controller.configure(bindings,catalogues,difficulty): return reject(controller.error)
	if not weapons.configure(bindings,catalogues): return reject(weapons.error)
	for id in 3:
		if not controller.set_initial_route(id,scenery.initial_npc_route(id)): return reject(controller.error)
	if death_resources!=null and not controller.set_initial_destruction(death_resources,world.get("npc_construction",{})): return reject(controller.error)
	var player: RefCounted
	if not bindings.opening_actors.get("player_initialization",{}).is_empty():
		player=PlayerState.new()
		if not player.configure(bindings,catalogues): return reject(player.error)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_player_hull=int(bindings.opening_actors.player_current_hull_override)
	_controller=controller;_weapons=weapons
	_player_state=player
	if not bindings.opening_staging.get("player_motion",{}).is_empty():
		_player_motion=PlayerMotion.new()
		if not _player_motion.configure(bindings): return reject(_player_motion.error)
	_player_recharge=player!=null and not bindings.opening_actors.player_initialization.get("recharge",{}).is_empty()
	_player_repair=player!=null and not bindings.opening_actors.player_initialization.get("repair",{}).is_empty()
	_player_contacts=player!=null and not bindings.weapon_parameters.get("player_hit_policy",{}).is_empty() and not bindings.opening_actors.npc_initialization.get("hostility",{}).is_empty()
	_elapsed_ms=int(bindings.opening_clock.initial_elapsed_ms)
	_random_state=world.random_state.duplicate(true)
	_scenery_identity=scenery.presentation_identity()
	return true

func configure_player_flight(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, scenery: RefCounted, sensitivity: float) -> bool:
	error=""
	if _controller==null or _elapsed_ms!=0 or _flight!=null or _projectile_visuals!=null or scenery==null or library==null or bindings==null or _identity.get("binding_id")!=bindings.binding_id:
		return reject("Player flight must join its fresh opening before time advances")
	if scenery.snapshot().get("random_state")!=_random_state or scenery.presentation_identity()!=_scenery_identity:
		return reject("Player flight belongs to another initialized world")
	var flight := PlayerFlight.new();var primaries := Primaries.new();var mounts := Mounts.new()
	var loadout := Loadout.new();var inventory := Inventory.new()
	if not flight.configure(bindings,catalogues,sensitivity): return reject(flight.error)
	if not mounts.open(library,catalogues): return reject(mounts.error)
	if not loadout.configure(bindings,catalogues,bindings.base_content_id): return reject(loadout.error)
	if not primaries.configure(bindings,catalogues,mounts,loadout.snapshot()): return reject(primaries.error)
	if not inventory.configure(bindings,catalogues,scenery.snapshot()): return reject(inventory.error)
	if scenery.snapshot().get("bodies",{}).is_empty() or _player_state==null or _player_motion==null:
		return reject("Player flight requires the complete fresh body and movement owners")
	_flight=flight;_primaries=primaries;_inventory=inventory
	return true

func configure_projectile_visuals(bindings: RefCounted, library: RefCounted) -> bool:
	error=""
	if _controller==null or _elapsed_ms!=0 or _projectile_visuals!=null:return reject("Projectile visuals must join the fresh weapon population once")
	var visuals:=ProjectileVisuals.new()
	if not visuals.configure(bindings,library,snapshot()):return reject(visuals.error)
	var impacts: RefCounted
	if not bindings.opening_staging.get("projectile_impacts",{}).is_empty():
		if not _player_contacts:return reject("Impact presentation requires verified opening contact passes")
		impacts=Impacts.new()
		if not impacts.configure(bindings,library,snapshot()):return reject(impacts.error)
	_projectile_visuals=visuals;_impacts=impacts
	return true

func projectile_visual_owner() -> RefCounted:return _projectile_visuals
func impact_visual_owner() -> RefCounted:return _impacts
func damage_particle_owner() -> RefCounted:return _damage_particles

func configure_damage_particles(bindings: RefCounted,combat: Dictionary,seed_seconds: Variant) -> bool:
	error=""
	if _controller==null or _elapsed_ms!=0 or _damage_particles!=null or bindings==null or bindings.binding_id!=_identity.get("binding_id"):return reject("Damage effects must join their fresh world once")
	var particles:=DamageParticles.new()
	if not particles.configure(bindings,combat,seed_seconds):return reject(particles.error)
	_damage_particles=particles;return true

func configure_player_aim(bindings: RefCounted) -> bool:
	error=""
	if _flight==null or _elapsed_ms!=0 or _aim!=null or bindings==null or bindings.binding_id!=_identity.get("binding_id"):
		return reject("Player aim must join its fresh interactive opening once")
	var aim := Aim.new()
	if not aim.configure(bindings):return reject(aim.error)
	_aim=aim
	return true

func configure_npc_scanner(bindings: RefCounted, catalogues: RefCounted, radii: Vector2, frames: int) -> bool:
	error=""
	if _aim==null or _elapsed_ms!=0 or _scanner!=null or bindings==null or bindings.binding_id!=_identity.get("binding_id"):return reject("NPC scanner must join its fresh player aim once")
	var scanner := Scanner.new()
	if not scanner.configure(bindings,catalogues,radii,frames):return reject(scanner.error)
	_scanner=scanner
	return true

func evaluate(timeline: RefCounted, scenery: RefCounted, delta_ms: Variant, present_radio: Variant, detail: Variant = 1.0, commands := Vector2.ZERO, fire_primary := false, hud_viewport := Vector2i.ZERO, fade_active := true) -> Dictionary:
	error=""
	if _controller==null or not timeline is Timeline or not scenery is Scenery: return fail("Configure opening frame owners before updating")
	var previous: Dictionary=timeline.snapshot();var field: Dictionary=scenery.clock_snapshot()
	for key in _identity:
		if previous.get("scene",{}).get(key)!=_identity[key] or field.get(key)!=_identity[key]: return fail("Opening frame owners belong to another content identity")
	if previous.get("elapsed_ms")!=_elapsed_ms or field.get("random_state")!=_random_state or scenery.presentation_identity()!=_scenery_identity:
		return fail("Opening frame requires its retained timeline and world stream")
	if _projectile_visuals!=null and _projectile_visuals.snapshot().elapsed_ms!=_elapsed_ms:return fail("Projectile animation clock differs from its world")
	if not commands.is_finite() or absf(commands.x)>1.0 or absf(commands.y)>1.0: return fail("Player commands must be normalized finite axes")
	if _flight==null and (commands!=Vector2.ZERO or fire_primary): return fail("This opening has no connected player input")
	if previous.camera.shot.phase>=4 and _flight==null: return fail("The live encounter requires connected player flight and weapons")
	if _flight!=null and _player_state.snapshot().vitals.hull<=0: return fail("The player death transition is not yet supported")
	if _flight!=null and previous.radio.finished[_flight.boundary_event()] and not previous.has("escape"): return fail("The postcombat mission transition is not yet supported")
	if _impacts!=null and _impacts.snapshot().elapsed_ms!=_elapsed_ms:return fail("Impact clock differs from its world")
	if _damage_particles!=null and _damage_particles.snapshot().elapsed_ms!=_elapsed_ms:return fail("Damage particle clock differs from its world")
	if previous.get("escape",{}).get("boundary","")!="":return fail("The following arrival scene is not yet connected")
	var previous_weapons:=snapshot() if _impacts!=null else {}
	var next: RefCounted=fork_for_frame()
	var clock: RefCounted=timeline.fork_for_frame();var world: RefCounted=scenery.fork_for_frame()
	if next._projectile_visuals!=null and not next._projectile_visuals.advance(delta_ms):return fail(next._projectile_visuals.error)
	if next._impacts!=null and not next._impacts.advance(delta_ms):return fail(next._impacts.error)
	# The ordinary player pass precedes world weapons. Its shield pulse therefore
	# reaches the current frame's hit accounting, including fractional truncation.
	if next._player_recharge and next._player_state.advance_recharge(delta_ms).is_empty(): return fail(next._player_state.error)
	if next._player_repair and next._player_state.advance_repair(delta_ms).is_empty(): return fail(next._player_state.error)
	var contact_pose: Transform3D=previous.scene.player_pose
	if next._engine_audio!=null and not next._engine_audio.before_motion(int(previous.camera.shot.phase)):return fail(next._engine_audio.error)
	if previous.camera.shot.phase==4 and next._flight!=null:
		next._player_motion_event=next._flight.motion(previous.scene,previous.camera.shot.phase,delta_ms)
		if next._player_motion_event.is_empty(): return fail(next._flight.error)
		contact_pose=next._player_motion_event.pose
	elif int(previous.camera.shot.phase)>4 and next._player_motion!=null:
		next._player_motion_event=next._player_motion.evaluate_escape(previous.scene,previous.get("escape",{}),delta_ms)
		if next._player_motion_event.is_empty():return fail(next._player_motion.error)
		contact_pose=next._player_motion_event.pose
	elif next._player_motion!=null:
		next._player_motion_event=next._player_motion.evaluate(previous.scene,previous.camera.shot.phase,delta_ms)
		if next._player_motion_event.is_empty(): return fail(next._player_motion.error)
		contact_pose=next._player_motion_event.pose
	if next._engine_audio!=null and not next._engine_audio.follow_player(contact_pose,int(next._player_state.snapshot().vitals.hull),int(delta_ms)):return fail(next._engine_audio.error)
	if next._aim!=null:
		var preceding_camera: Transform3D=previous.camera.view.get("pose",Transform3D.IDENTITY)
		if not next._aim.advance(contact_pose,preceding_camera,hud_viewport):return fail(next._aim.error)
	if next._primaries!=null:
		var primary: Dictionary=world.evaluate_primary_contacts(next._primaries,clock.combat_owner(),next._inventory,delta_ms)
		if primary.is_empty(): return fail(world.error)
		if not clock.adopt_contact_pass(primary.combat): return fail(clock.error)
		world=primary.scenery;next._primaries=primary.primaries;next._primary_contacts=primary.weapons
	# Player movement precedes existing-slot contacts; shooter disposition is
	# retained from the preceding NPC pass. Scripted relocation happens later.
	if next._player_contacts:
		var combat: RefCounted=clock.combat_owner()
		var shooters: Array=combat.shooter_states()
		if shooters.is_empty(): return fail(combat.error)
		var weapon_pass: Dictionary=next._weapons.evaluate_player_update(next._player_state,contact_pose,shooters,false,delta_ms)
		if weapon_pass.is_empty(): return fail(next._weapons.error)
		next._weapons=weapon_pass.weapons;next._player_state=weapon_pass.player;next._weapon_events=weapon_pass.actors
	elif next._weapons.advance(delta_ms).is_empty(): return fail(next._weapons.error)
	if next._impacts!=null and not next._impacts.apply_contacts(previous_weapons,next._primary_contacts,next._weapon_events):return fail(next._impacts.error)
	# Source particle managers run inside the early weapon/world pass. Player
	# logical motion is current; NPC roots and emission flags are retained.
	if next._damage_particles!=null and not next._damage_particles.advance(contact_pose,delta_ms):return fail(next._damage_particles.error)
	if not clock.begin_frame(delta_ms,false,detail,next._player_motion_event,{"random_state":field.random_state,"fade_active":fade_active}): return fail(clock.error)
	var scene: Dictionary=clock.snapshot()
	if next._engine_audio!=null and not next._engine_audio.apply_controller(scene.get("escape",{}),scene.scene.player_pose):return fail(next._engine_audio.error)
	if next._damage_particles!=null and not next._damage_particles.apply_controller(scene.get("escape",{})):return fail(next._damage_particles.error)
	if not scene.get("escape",{}).get("frame",{}).get("world_change",{}).is_empty():
		if not world.apply_escape_environment(scene.escape):return fail(world.error)
	# Fresh player stats are active, with the authored hull override. The player
	# constructor's special-flight flag is clear; cinematic control remains held
	# until phase four clears target suppression. This is not a general player body.
	var player := _identity.duplicate()
	player.merge({"pose":scene.scene.player_pose,"hull":_player_hull,"active":true,"special_flight":false,"targeting_blocked":int(scene.camera.shot.phase)!=4})
	if next._player_state!=null:
		var body: Dictionary=next._player_state.snapshot()
		player.hull=body.vitals.hull;player.active=body.active
	# Source application input follows the controller and ordinary camera. A
	# newly released frame can fire and prepare steering, but moved cinematically.
	next._primary_fire={}
	if next._flight!=null and int(scene.camera.shot.phase)==4 and player.hull>0:
		if fire_primary:
			next._primary_fire=next._primaries.fire(scene.scene.player_pose,player.active and player.hull>0)
			if next._primary_fire.is_empty(): return fail(next._primaries.error)
		if not next._flight.sample_commands(commands,delta_ms): return fail(next._flight.error)
		if next._engine_audio!=null and not next._engine_audio.sample_commands(commands):return fail(next._engine_audio.error)
	var camera_random: Dictionary=field.random_state
	if int(scene.camera.shot.phase)>4:camera_random=scene.escape.random_state
	var actors: Dictionary=next._controller.evaluate(clock.combat_owner(),next._weapons,delta_ms,player,camera_random)
	if actors.is_empty(): return fail(next._controller.error)
	if next._damage_particles!=null and not next._damage_particles.finish_npc_pass(clock.combat_owner().snapshot(),actors.combat.snapshot(),actors.actors,delta_ms,detail):return fail(next._damage_particles.error)
	if not clock.adopt_combat_pass(actors.combat): return fail(clock.error)
	var immediate: Variant=scene.scene.camera_position_parameter if scene.scene.formation_revealed and not previous.scene.formation_revealed else null
	# NPCs consume the shared stream before ordinary scenery lifecycle updates.
	if not world.update(delta_ms,previous.detail_reference,detail,immediate,actors.random_state): return fail(world.error)
	# Presentation radio observes this frame's actors. New completion flags affect
	# the next logic pass, never a second activation or camera pass in this one.
	if not clock.finish_frame(present_radio): return fail(clock.error)
	if next._aim!=null:
		var npc_contact := false
		for weapon in next._primary_contacts:
			for contact in weapon.contacts:
				if contact.target.group=="npc":npc_contact=true
		if not next._aim.sample_feedback(npc_contact,delta_ms,int(scene.camera.shot.phase)==4 and player.hull>0):return fail(next._aim.error)
	if next._scanner!=null and not next._scanner.advance(clock.combat_owner().snapshot(),scene.scene.player_pose,scene.camera.view.get("pose",Transform3D.IDENTITY),next._aim.snapshot(),delta_ms,int(scene.camera.shot.phase)==4 and player.hull>0):return fail(next._scanner.error)
	next._controller=actors.controller;next._weapons=actors.weapons;next._events=actors.actors
	next._elapsed_ms=clock.snapshot().elapsed_ms;next._random_state=world.random_state()
	return {"world_frame":next,"timeline":clock,"scenery":world}

func snapshot() -> Dictionary:
	if _controller==null: return {}
	var result := _identity.duplicate()
	result.controller=_controller.snapshot();result.weapons=_weapons.snapshot();result.actor_events=_events.duplicate(true)
	if _projectile_visuals!=null:result.projectile_visuals=_projectile_visuals.snapshot()
	if _impacts!=null:result.impact_visuals=_impacts.snapshot()
	if _aim!=null:result.player_aim=_aim.snapshot()
	if _scanner!=null:result.npc_scanner=_scanner.snapshot()
	if _damage_particles!=null:result.damage_particles=_damage_particles.snapshot()
	if _engine_audio!=null:result.player_engine=_engine_audio.snapshot()
	result.elapsed_ms=_elapsed_ms;result.random_state=_random_state.duplicate(true)
	result.player={} if _player_state==null else _player_state.snapshot()
	result.player_cache={} if _player_state==null else _player_state.cache_snapshot()
	result.weapon_events=_weapon_events.duplicate(true)
	if _player_motion!=null: result.player_motion=_player_motion_event.duplicate(true)
	if _flight!=null:
		result.player_flight=_flight.snapshot();result.primaries=_primaries.snapshot()
		result.primary_contacts=_primary_contacts.duplicate(true);result.primary_fire=_primary_fire.duplicate(true)
	return result

func npc_destruction_owner(actor_id: int) -> RefCounted:
	return null if _controller==null else _controller.destruction_owner(actor_id)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._player_hull=_player_hull
	if _controller!=null: copy._controller=_controller.fork_for_frame()
	if _weapons!=null: copy._weapons=_weapons.fork_for_frame()
	if _player_state!=null: copy._player_state=_player_state.fork_for_frame()
	copy._events=_events.duplicate(true)
	copy._player_contacts=_player_contacts;copy._weapon_events=_weapon_events.duplicate(true)
	copy._player_recharge=_player_recharge
	copy._player_repair=_player_repair
	copy._player_motion=_player_motion;copy._player_motion_event=_player_motion_event.duplicate(true)
	if _projectile_visuals!=null:copy._projectile_visuals=_projectile_visuals.fork_for_frame()
	if _impacts!=null:copy._impacts=_impacts.fork_for_frame()
	if _aim!=null:copy._aim=_aim.fork_for_frame()
	if _scanner!=null:copy._scanner=_scanner.fork_for_frame()
	if _damage_particles!=null:copy._damage_particles=_damage_particles.fork_for_frame()
	if _engine_audio!=null:copy._engine_audio=_engine_audio.fork_for_frame()
	if _flight!=null: copy._flight=_flight.fork_for_frame()
	if _primaries!=null: copy._primaries=_primaries.fork_state()
	copy._inventory=_inventory
	copy._primary_contacts=_primary_contacts.duplicate(true);copy._primary_fire=_primary_fire.duplicate(true)
	copy._elapsed_ms=_elapsed_ms;copy._random_state=_random_state.duplicate(true);copy._scenery_identity=_scenery_identity
	return copy

func clear() -> void:
	error="";_identity={};_controller=null;_weapons=null;_player_hull=0;_events=[]
	_player_state=null
	_player_contacts=false;_weapon_events=[]
	_player_recharge=false
	_player_repair=false
	_player_motion=null;_player_motion_event={}
	_projectile_visuals=null;_impacts=null
	_aim=null;_scanner=null
	_damage_particles=null
	_engine_audio=null
	_flight=null;_primaries=null;_inventory=null;_primary_contacts=[];_primary_fire={}
	_elapsed_ms=0;_random_state={};_scenery_identity=null

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
