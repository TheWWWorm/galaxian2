extends SceneTree
## Component verification with explicit synthetic departure and activity fixtures.
## This does not exercise a live second-trip mission, AI or activation scheduler.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/full_hold_pirate_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Guns=preload("res://src/simulation/opening_npc_weapons.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
var failures:=0
var checks:=0

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Pass explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Full-hold pirate: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	check(bindings.source_architecture=="x86_64","This verification requires Mac content")
	var flight:=Construction.new();var actor:=Actor.new();var combat:=Combat.new();var guns:=Guns.new()
	if bindings.full_hold_pirate.is_empty():
		check(not actor.configure_full_hold(bindings,cat,flight,.5) and not combat.configure_full_hold(bindings,cat,flight,.5) and not guns.configure_full_hold(bindings,cat,flight),"Legacy pack invented pirate combat")
		var player:=Player.new();check(player.configure_departure(bindings,cat,4),player.error)
		check(not player.supports_weapon_hit({}),"Legacy second departure accepted an undeclared NPC weapon")
		return
	var data: Dictionary=bindings.full_hold_pirate
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(data,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_flight,bindings.opening_actors,bindings.opening_handoff).is_empty(),"Pirate declaration rejected")
	for key in Definitions.VALUES:
		var bad:=data.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed pirate field accepted: "+key)
	for key in data.primary_weapon:
		var bad:=data.duplicate(true);bad.primary_weapon[key]=null
		check(not Definitions.parameters(bad),"Changed pirate gun field accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_flight,bindings.opening_actors,bindings.opening_handoff).is_empty(),"Changed pirate source extent accepted: "+key)
	for kills in 4:
		var packet:=packet_fixture(bindings,cat,kills)
		if not flight.prepare(bindings,cat,packet,4096,1789100000):check(false,flight.error);return
		var before:=flight.snapshot();var rank:=int(kills>0)
		for fixture in GOLDEN:
			if fixture[0]!=rank:continue
			if not actor.configure_full_hold(bindings,cat,flight,fixture[1]):check(false,actor.error);return
			var state:=actor.snapshot()
			check(state.factory_hull==fixture[2] and state.max_hull==fixture[2] and state.vitals.hull==fixture[2] and state.hull_percent==100,"Second pirate hull differs from independent binary32 fixture")
			check(state.actor_id==0 and state.actor_kind==8 and state.hull_catalogue_id==2 and state.hull_resource==bindings.resolve_ship_model(2),"Second pirate membership or model changed")
			check(state.position==Vector3(0,0,-200000) and state.pose==Transform3D(Basis.IDENTITY,state.position) and state.actor_mode==5 and not state.active and state.hostile and state.targeting_blocked,"Second pirate construction flags or pose changed")
			check(state.spatial_half_extent==50000 and state.half_extent==(650 if fixture[1]==1.5 else 1000) and state.vitals.armor==0 and state.vitals.shield==0 and state.damage_allowed and state.firing_allowed and state.collision_enabled,"Second pirate reused unsupported combat pools or bounds")
			check(not actor.collision_context().eligible and not actor.normal_hit(1).accepted and actor.snapshot().vitals.hull==fixture[2],"Inactive pirate accepted damage or collision")
		check(flight.snapshot()==before and packet==before.departure,"Combat preparation changed world, cargo, route or earned progress")
	verify_weapons(bindings,cat,flight)
	verify_refusals(bindings,cat,flight,combat,guns,actor)
	verify_reader(args[1],lib,header)

func verify_weapons(bindings: RefCounted, cat: RefCounted, flight: RefCounted):
	var combat:=Combat.new();var guns:=Guns.new()
	if not combat.configure_full_hold(bindings,cat,flight,.5) or not guns.configure_full_hold(bindings,cat,flight):check(false,combat.error+guns.error);return
	var before:=combat.snapshot();var state:=guns.snapshot()
	check(before.actors.size()==1 and before.campaign_cursor==4 and not before.activated and before.phase==-1,"Detached pirate activated itself")
	check(state.actors.size()==1 and state.definition.damage==1 and state.definition.interval_ms==592 and state.actors[0].projectiles.slots.size()==4,"Pirate reused Opening gun damage, interval or population")
	check(combat.shooter_states()==[{"present":true,"hostile":true}] and combat.refresh_hostility(0) and combat.snapshot()==before,"Inactive pirate lost source hostility or statistics ownership")
	check(not combat.update(before,3,{}) and not combat.configure_escape(bindings) and combat.snapshot()==before,"Opening radio or escape activated the second pirate")
	check(not combat._actors[0].apply_activation(bindings.opening_actors.npc_initialization.activation),"Opening activation applied to the second-trip body")
	guns.advance(1)
	check(not guns.fire(combat,[0]).actors[0].outcome.fired,"Inactive pirate fired")
	# Synthetic owner input tests combat/projectile composition. Source activation
	# ordering, model flags and live mission transitions are verified separately.
	combat._actors[0].set_permissions(true,true,true)
	combat.set_pose(0,Transform3D.IDENTITY)
	var shot: Dictionary=guns.fire(combat,[0]).actors[0].outcome
	check(shot.fired and shot.projectile.position==Vector3.ZERO and shot.projectile.velocity==Vector3(0,0,16) and shot.projectile.remaining_ms==3000,"Pirate forward muzzle, speed or lifetime differs from source")
	var player: RefCounted=flight.player_owner();player.set_permissions(true,true)
	var old_player: Dictionary=player.snapshot();var old_guns:=guns.snapshot()
	var hit:=guns.evaluate_player_update(player,Transform3D.IDENTITY,combat.shooter_states(),false,0)
	if hit.is_empty():check(false,guns.error);return
	check(hit.actors[0].contacts.size()==1 and hit.player.snapshot().vitals.hull==old_player.vitals.hull-1 and hit.weapons.snapshot().actors[0].projectiles.slots[0]==null,"Pirate contact did not apply exactly one hull damage and deferred cleanup")
	check(player.snapshot()==old_player and guns.snapshot()==old_guns,"Evaluated contact mutated its input owners")
	var opening:=Combat.new();var opening_guns:=Guns.new()
	check(opening.configure(bindings,cat,.5) and opening_guns.configure(bindings,cat),opening.error+opening_guns.error)
	check(guns.fire(opening,[0]).is_empty() and opening_guns.fire(combat,[0]).is_empty() and guns.snapshot()==old_guns,"Weapons accepted another encounter's actor membership")
	check(not player.supports_weapon_hit(opening_guns.snapshot().actors[0].projectiles.weapon),"Second-trip player accepted Opening damage")
	var opening_player:=Player.new();opening_player.configure(bindings,cat)
	check(not opening_player.supports_weapon_hit(state.actors[0].projectiles.weapon),"Opening player accepted second-trip damage")
	var motion:=guns.advance(592)
	check(motion.actors[0].update.moved[0].position==Vector3(0,0,9472) and not guns.fire(combat,[0]).actors[0].outcome.fired,"Pirate moved incorrectly or fired at interval equality")
	guns.advance(1);check(guns.fire(combat,[0]).actors[0].outcome.fired,"Pirate failed beyond its strict interval")
	for i in 2:guns.advance(593);check(guns.fire(combat,[0]).actors[0].outcome.fired,"Available pirate projectile slot refused")
	guns.advance(593);check(guns.fire(combat,[0]).actors[0].outcome.reason=="capacity","Pirate exceeded four live slots")
	var saved:=guns.snapshot()
	for ids in [[0,0],[-1],[1],[false],[0.0]]:
		check(guns.fire(combat,ids).is_empty() and guns.snapshot()==saved,"Invalid fire request changed pirate pool")
	var fork: RefCounted=guns.fork_for_frame();fork.advance(1)
	check(guns.snapshot()==saved and fork.snapshot()!=saved,"Pirate projectile fork aliases its source")
	var split: RefCounted=combat.fork_for_frame();split.normal_hit(0,1)
	check(combat.snapshot().actors[0].vitals.hull==50 and split.snapshot().actors[0].vitals.hull==49 and split.snapshot().actors[0].hull_percent==98,"Pirate damage/max hull or combat fork changed")
	combat.normal_hit(0,50)
	check(not guns.fire(combat,[0]).actors[0].outcome.fired and not combat.collision_context(0).eligible,"Exhausted pirate hull remained eligible")

func verify_refusals(bindings: RefCounted, cat: RefCounted, flight: RefCounted, combat: RefCounted, guns: RefCounted, actor: RefCounted):
	for invalid in [-1,11,NAN,INF,true,"0.5"]:
		check(not actor.configure_full_hold(bindings,cat,flight,invalid) and actor.snapshot().is_empty(),"Invalid pirate difficulty retained a body")
	var original: Dictionary=flight._state.duplicate(true)
	for field in ["binding_id","campaign_cursor","activated"]:
		flight._state=original.duplicate(true);flight._state[field]=null
		check(not combat.configure_full_hold(bindings,cat,flight,.5) and combat.snapshot().is_empty() and not guns.configure_full_hold(bindings,cat,flight) and guns.snapshot().is_empty(),"Mismatched flight retained pirate owners: "+field)
	flight._state=original
	check(not actor.configure_full_hold(bindings,cat,RefCounted.new(),.5) and not guns.configure_full_hold(bindings,cat,null),"Unowned pirate construction accepted")
	var cap: Dictionary=bindings.full_hold_pirate;bindings.full_hold_pirate={}
	check(not combat.configure_full_hold(bindings,cat,flight,.5) and not guns.configure_full_hold(bindings,cat,flight),"Absent declaration invented pirate combat")
	bindings.full_hold_pirate=cap

func packet_fixture(bindings: RefCounted, cat: RefCounted, kills: int) -> Dictionary:
	var loadout:=Loadout.new();var player:=Player.new()
	if not loadout.configure_station(bindings,cat,bindings.base_content_id) or not player.configure_departure(bindings,cat,4):check(false,loadout.error+player.error);return {}
	var seed:=loadout.snapshot();var current:=player.snapshot();var rules: Dictionary=bindings.full_hold_departure
	var reset:=Cache.departure_cache(bindings.opening_actors.player_initialization.flight_cache,rules,seed,current.max_hull,current.capacities,true)
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":4,
		"source_state":2,"world_type":3,"audio_selector":1,"confirmation_required":true,"confirmation_text_id":386,
		"loadout":seed,"reset_cache":reset,"player_cache":player.cache_snapshot(),"player":current,
		"progress":{"campaign_cursor":4,"rank":int(kills>0),"rank_score":4+3*kills,"player_kills":kills,"pirate_kills":kills,"other_score":0},
		"mission":{"kind":154,"station_id":78,"reward":0,"bonus":0,"source_parameter":25},"cargo_used":0,"source_ship_configuration":8}

func verify_reader(pack: String, lib: RefCounted, header: Dictionary):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-pirate-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","changed","extent","flight_absent","hull_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_pirate")
			"wrong_type":changed.full_hold_pirate=false
			"changed":changed.full_hold_pirate.primary_weapon.damage=3
			"extent":changed.full_hold_pirate.provenance.factory_hull.offset+=1
			"flight_absent":changed.full_hold_flight={}
			"hull_absent":changed.opening_actors.npc_initialization.hull={}
			"empty":
				changed.full_hold_pirate={}
				if changed.has("full_hold_control"):changed.full_hold_control={}
				if changed.has("full_hold_destruction"):changed.full_hold_destruction={};changed.full_hold_appearance={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		if scenario=="empty":check(accepted and reader.full_hold_pirate.is_empty() and not reader.full_hold_flight.is_empty(),"Optional pirate capability cannot be absent")
		else:check(not accepted and reader.binding_id.is_empty() and reader.source_architecture.is_empty() and reader.full_hold_pirate.is_empty(),"Failed reopen exposed stale pirate or architecture state")
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
# Independent Python binary32 fixture values, recorded outside engine source.
const GOLDEN=[[0,0,18],[0,0.1,21],[0,0.5,36],[0,1.5,72],[0,2.5,108],[0,4.5,180],[0,10,378],[1,0,25],[1,0.1,30],[1,0.5,50],[1,1.5,100],[1,2.5,150],[1,4.5,250],[1,10,525]]
