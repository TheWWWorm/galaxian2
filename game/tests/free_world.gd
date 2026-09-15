extends "res://tests/free_lifecycle.gd"
## Actual earned equipment, ordinary field and shared player/weapon owners.
## Component contexts and contact positions are explicit; no career is advanced.
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const Field=preload("res://src/simulation/scenery_field.gd")
const FieldPopulation=preload("res://src/simulation/scenery_population.gd")
const Primary=preload("res://src/simulation/primary_weapons.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const PlayerContacts=preload("res://src/simulation/ordinary_player_contacts.gd")
var contacted_factions:={}

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Ordinary world/player: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	if not FreeFlight.available(bindings):
		check(not Scenery.new().configure_free(bindings,cat,null,FreePopulation.CONTEXT,CONDITIONS,2),"Earlier lifecycle inferred a supported player departure")
		check(not Player.new().configure_free(bindings,cat,null,null),"Earlier lifecycle inferred ordinary player state")
		return
	var scenario:=Scenario.new();var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,scenario.error);return
	check(not Scenery.new().configure_free(bindings,cat,equipment,FreePopulation.CONTEXT,CONDITIONS,2),"Ordinary scenery accepted unreleased training equipment")
	if not Scenario.prepare_alioth_component(equipment,bindings,cat):check(false,equipment.error);return
	var retained: Dictionary=equipment.snapshot()
	var bodies:=Bodies.new();var effects:=Effects.new();var mounts:=Mounts.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not mounts.open(library,cat):check(false,bodies.error+effects.error+mounts.error);return
	for seed in [2,22]:
		var scenery:=Scenery.new()
		if not scenery.configure_free(bindings,cat,equipment,FreePopulation.CONTEXT,CONDITIONS,seed,true,bodies,effects):check(false,scenery.error);return
		var scene: Dictionary=scenery.snapshot();var population:=FieldPopulation.new()
		if not population.configure(bindings):check(false,population.error);return
		var selected:=population.for_departure(98,CONDITIONS,18)
		check(scene.station_id==98 and scene.system_id==19 and scene.center==selected.center and scene.objects.size()==selected.count,"Ordinary field lost its actual station count or source center")
		check(scene.bodies.objects.size()==scene.objects.size() and scene.destruction.size()==scene.objects.size(),"Ordinary field omitted collision or destruction owners")
		var field:=Field.new();var random:=Random.new();random.seed_from(seed)
		if not field.configure(bindings,cat,98,false,false,18):check(false,field.error);return
		var expected:=field.generate(selected.center,random.snapshot())
		check(scene.objects==expected.objects,"World composition changed source scenery construction")
		var world:=World.new()
		if not world.configure_free_traffic(bindings,cat,equipment,FreePopulation.CONTEXT,seed,CONDITIONS):check(false,world.error);return
		var assembled:=world.generate(expected.random_state)
		check(scene.world_initialization==assembled and scene.random_state==assembled.random_state,"Scenery, ordinary actors and weapon effects consumed an out-of-order stream")
		var construction: RefCounted=scenery.world_initialization_owner().npc_construction_owner()
		var player:=Player.new()
		if not player.configure_free(bindings,cat,equipment,construction):check(false,player.error);return
		var ship: Dictionary=player.snapshot()
		check(ship.campaign_cursor==18 and ship.vitals.hull==95 and ship.max_hull==95 and ship.vitals.armor==ship.capacities.armor and ship.vitals.shield==ship.capacities.shield,"Ordinary departure did not restore source equipped pools")
		check(ship.gamma==100.0 and player.loadout().station_id==98 and player.loadout().equipment_ids==retained.loadout.equipment_ids and ship.free_context==construction.snapshot().free_context,"Ordinary player lost gamma, equipment or factory context")
		verify_free_cache(bindings,cat,equipment,construction,player)
		verify_free_player_contacts(bindings,cat,equipment,construction,player)
		verify_free_primary(bindings,cat,mounts,equipment,construction,player)
		verify_free_frame(library,bindings,cat,equipment,construction,player,scene.random_state)
		check(scenery.snapshot()==scene and player.snapshot()==ship and equipment.snapshot()==retained,"Prospective ordinary frames changed retained world, player or station state")
		if failures:return
	for faction in [0,1,8]:check(contacted_factions.has(faction),"Missing source faction player-contact case: "+str(faction))
	for key in ["station_id","system_id","special_arrival","void_encounter","station_response"]:
		var bad:=FreePopulation.CONTEXT.duplicate();bad[key]=95 if key=="station_id" else (15 if key=="system_id" else true)
		check(not Scenery.new().configure_free(bindings,cat,equipment,bad,CONDITIONS,2),"Unsupported ordinary location/override accepted: "+key)
	var saved_id: String=bindings.binding_id;bindings.binding_id="f".repeat(64)
	check(not Scenery.new().configure_free(bindings,cat,equipment,FreePopulation.CONTEXT,CONDITIONS,2),"Foreign equipment identity entered ordinary scenery")
	bindings.binding_id=saved_id
	check(equipment.snapshot()==retained,"Rejected ordinary initialization changed owned equipment")

func verify_free_cache(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,construction: RefCounted,player: RefCounted) -> void:
	check(not Player.new().configure_free(bindings,cat,load("res://src/simulation/station_equipment.gd").new(),construction),"Uninitialized equipment entered ordinary player state")
	var cache: Dictionary=player.cache_snapshot()
	check(cache.campaign_cursor==18 and cache.station_id==98 and cache.values.hull==95,"Ordinary pool cache lost its identity or source capacity")
	cache.values.hull=42;cache.values.armor=3;cache.values.shield=0;cache.values.gamma=17
	var restored:=Player.new()
	if not restored.configure_free(bindings,cat,equipment,construction,cache):check(false,restored.error);return
	check(restored.snapshot().vitals=={"hull":42,"armor":3,"shield":0.0} and restored.snapshot().gamma==100.0 and restored.snapshot().max_hull==95,"Ordinary restoration lost damaged pools or refreshed gamma incorrectly")
	for key in ["binding_id","station_id","campaign_cursor","equipment_ids"]:
		var bad:=cache.duplicate(true)
		bad[key]="f".repeat(64) if key=="binding_id" else (95 if key=="station_id" else (16 if key=="campaign_cursor" else []))
		check(not Player.new().configure_free(bindings,cat,equipment,construction,bad),"Foreign ordinary player cache accepted: "+key)

func verify_free_player_contacts(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,construction: RefCounted,player: RefCounted) -> void:
	var weapons:=Weapons.new();var context: Dictionary=construction.snapshot().free_context
	if not weapons.configure_ambient(bindings,cat,construction,context.rank,context.difficulty):check(false,weapons.error);return
	var pose:=Transform3D(Basis.IDENTITY,Vector3(0,0,150000))
	for row in weapons.snapshot().actors:
		if row.projectiles.is_empty():continue
		var faction: int=construction.snapshot().actors[row.actor_id].actor_kind
		contacted_factions[faction]=true
		var weapon: Dictionary=row.projectiles.weapon
		for hostile in [false,true]:
			var shots:=shot(weapon,pose.origin);var contacts:=PlayerContacts.new()
			if shots==null:return
			var before: Dictionary=player.snapshot();var bullets: Dictionary=shots.snapshot()
			var result:=contacts.evaluate(shots,player,pose,true,hostile,false)
			if result.is_empty():check(false,contacts.error);return
			check(result.contacts.size()==1 and result.player.snapshot().contact,"Ordinary faction gun did not contact the actual player")
			var direct: RefCounted=player.fork_for_frame();var hit: Dictionary=direct.weapon_hit(weapon,true,hostile,false)
			check(not hit.is_empty() and result.player.snapshot().vitals==direct.snapshot().vitals,"Ordered player contact changed source hit policy")
			check(player.snapshot()==before and shots.snapshot()==bullets,"Prospective player contact changed retained owners")
		var bad:=weapon.duplicate(true);bad.campaign_cursor=16
		check(not player.supports_weapon_hit(bad),"Ordinary player accepted another encounter's gun")

func verify_free_primary(bindings: RefCounted,cat: RefCounted,mounts: RefCounted,equipment: RefCounted,construction: RefCounted,player: RefCounted) -> void:
	var primaries:=Primary.new();var group:=ordinary_group(bindings,cat,equipment,construction)
	if group==null:return
	if not primaries.configure(bindings,cat,mounts,player.loadout()):check(false,primaries.error);return
	var id:=0;var before: Dictionary=group.snapshot();var center: Vector3=group.collision_context(id).center
	# An explicit firing pose puts the installed gun at the generated target.
	var mount: Dictionary=primaries.snapshot().guns[0].mount
	var pose:=Transform3D(Basis.IDENTITY,center-mount.position)
	if primaries.advance(10000).is_empty():check(false,primaries.error);return
	var volley:=primaries.fire(pose,true,group.contact_random_state())
	if volley.is_empty() or not volley.weapons[0].result.fired:check(false,primaries.error+"Installed primary failed to fire");return
	var bullets: Dictionary=primaries.snapshot()
	var result:=primaries.evaluate_npc_update(group,[id],0)
	if result.is_empty():check(false,primaries.error);return
	check(result.weapons[0].contacts.size()==1 and result.combat.snapshot().actors[id].vitals.hull<before.actors[id].vitals.hull,"Installed player primary failed an ordinary NPC contact")
	check(group.snapshot()==before and primaries.snapshot()==bullets,"Prospective player volley changed retained owners")
	var bad: Dictionary=player.loadout();bad.station_id=56
	check(not Primary.new().configure(bindings,cat,mounts,bad),"Primary setup enabled the unsupported pending story location")

func verify_free_frame(library: RefCounted,bindings: RefCounted,cat: RefCounted,equipment: RefCounted,construction: RefCounted,player: RefCounted,random: Dictionary) -> void:
	var control:=Controller.new();var weapons:=Weapons.new();var resources:=SmallResources.new();var freight:=FreightResources.new()
	var context: Dictionary=construction.snapshot().free_context
	if not resources.configure_free(library,bindings,construction) or not freight.configure_free(library,bindings,construction) or not control.configure_ambient(bindings,cat,construction,context.rank,context.difficulty,equipment,REPUTATION) or not control.set_destruction(bindings,resources,freight) or not weapons.configure_ambient(bindings,cat,construction,context.rank,context.difficulty):check(false,resources.error+freight.error+control.error+weapons.error);return
	var retained: Dictionary=control.snapshot();var retained_guns: Dictionary=weapons.snapshot()
	var group: RefCounted=control.combat_owner()
	if not group.begin_contact_pass(random,true) or group.normal_hit(0,int(group.snapshot().actors[0].max_hull/2)+1,false).is_empty():check(false,group.error);return
	random=group.contact_random_state()
	var ship: RefCounted=player.fork_for_frame();var staged: RefCounted=control.fork_for_frame();var guns: RefCounted=weapons.fork_for_frame()
	var fired:=false;var contacted:=false
	for frame in 20:
		var actor_pose: Transform3D=group.snapshot().actors[0].body_pose
		var pose:=Transform3D(Basis.IDENTITY,actor_pose.origin+actor_pose.basis.z*2000)
		# Once guidance fires, a separate explicit position fixture exercises the
		# complete NPC weapon -> player -> control commit order with that shot.
		for bullet in guns.snapshot().actors[0].projectiles.slots:
			if bullet!=null and bullet.remaining_ms>0:pose.origin=bullet.position;fired=true;break
		if not group.begin_contact_pass(random,true):check(false,group.error);return
		var contacts: Dictionary=guns.evaluate_combat_training_update(ship,pose,group,false,100)
		if contacts.is_empty():check(false,guns.error);return
		ship=contacts.player;guns=contacts.weapons;group=contacts.combat
		for event in contacts.actors:
			if not event.contacts.is_empty():contacted=true
		var target:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":player.loadout().ship_id,"pose":pose,"active":true,"hull":int(ship.snapshot().vitals.hull),"special_flight":false,"targeting_blocked":false,"alternate_position":null}
		var result: Dictionary=staged.evaluate(group,guns,100,target,group.contact_random_state())
		if result.is_empty():check(false,staged.error);return
		staged=result.controller;guns=result.weapons;group=result.combat;random=result.random_state
		if contacted:break
	check(fired and contacted and ship.snapshot().vitals!=player.snapshot().vitals,"Ordinary guidance/fire/contact did not damage the actual equipped player")
	check(control.snapshot()==retained and weapons.snapshot()==retained_guns,"Staged world/player frame mutated retained controller or weapons")
