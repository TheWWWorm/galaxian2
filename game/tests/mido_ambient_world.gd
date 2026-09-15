extends "res://tests/mido_ambient_construction.gd"
## Full scenery and shared player/weapon/NPC phases, using an earned equipment
## fixture and explicit prior release/exchange/arrival. Not an application trip.
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const REPUTATION={"axes":[30,-6],"override":-1}
var content: RefCounted
var physical: RefCounted
var visual: RefCounted
var worlds:=0
var player_contacts:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Mido ambient world: %d checks; %d worlds; %d player contacts; %d failures"%[checks,worlds,player_contacts,failures])
	quit(1 if failures else 0)

func verify_population(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted) -> void:
	if Travel.journey(bindings.mido_travel,11).is_empty():
		check(not Player.new().configure_local_travel(bindings,catalogues,equipment,null,11),"Earlier pack enabled the next player's flight")
		return
	if content==null:
		content=Library.new();physical=Bodies.new();visual=Effects.new()
		if not content.open(OS.get_cmdline_user_args()[0]) or not physical.configure(content,bindings) or not visual.configure(content,bindings):check(false,content.error+physical.error+visual.error);return
	var player:=Player.new()
	if not player.configure_local_travel(bindings,catalogues,equipment,null,11):check(false,player.error);return
	check(player.snapshot().campaign_cursor==11 and player.cache_snapshot().campaign_cursor==11 and player.loadout().station_id==79,"Kernstal player lost its visit or location")
	check(player.set_permissions(true,true),player.error)
	var before_equipment: Dictionary=equipment.snapshot()
	var original: Dictionary=construction.snapshot()
	var field:=Scenery.new()
	if not field.configure_local_departure(bindings,catalogues,equipment,player.cache_snapshot(),CONDITIONS,int(original.population.unix_seconds),true,physical,visual,0.5,11):check(false,field.error);return
	var world: Dictionary=field.world_initialization_owner().snapshot()
	check(world.campaign_cursor==11 and world.station_id==79 and world.npc_construction==original,"Shared scenery changed the independent mixed construction")
	var random:=Random.new();random.restore(original.random_state)
	var armed:=[];var travel:=-1
	for actor in original.actors:
		var effects: Dictionary=world.weapon_effects[actor.actor_id]
		if actor.population_group=="freighter":
			check(effects=={"actor_id":actor.actor_id,"unarmed":true},"Freighter allocated an ordinary gun or impact pool");continue
		armed.append(actor.actor_id)
		if actor.population_group=="travel":travel=actor.actor_id
		for part in [effects.discarded_default,effects.primary]:
			var expected:=[]
			for index in 4:expected.append(random.next_int(2)==0)
			check(part.flipped==expected,"Mixed weapon effects changed source RNG order")
	check(world.random_state==random.snapshot() and field.snapshot().random_state==world.random_state,"Mixed world consumed unexpected post-construction draws")
	var encounter:=Encounter.new()
	if not encounter.configure_ambient_traffic(bindings,catalogues,content,player,field,0,0.5,equipment,REPUTATION):check(false,encounter.error);return
	var input: Dictionary=encounter.snapshot()
	check(input.projectile_visuals.models.size()==armed.size()+1 and input.impact_visuals.weapons.size()==armed.size()+1,"Unarmed traffic acquired projectile or impact visuals")
	for id in armed:check(input.weapons.actors[id].projectiles.weapon.interval_ms==578,"Cursor11 borrowed the preceding traffic fire interval")
	var pose:=Transform3D(Basis.IDENTITY,Vector3(0,0,-2000000))
	var stream: Dictionary=world.random_state
	for index in 100:
		var result:=step(encounter,player,field,pose,100,stream)
		if result.is_empty():return
		encounter=result.encounter;player=result.player;field=result.scenery;stream=result.random_state
	if travel>=0:check(encounter.snapshot().combat.actors[travel].spawn_generation==0,"Travel ship launched at the strict ten-second boundary")
	var result:=step(encounter,player,field,pose,1,stream)
	if result.is_empty():return
	encounter=result.encounter;player=result.player;field=result.scenery;stream=result.random_state
	if travel>=0:check(encounter.snapshot().combat.actors[travel].spawn_generation==1 and encounter.snapshot().combat.actors[travel].active,"Shared world logic failed to launch the retained travel slot")
	if not armed.is_empty():
		var id: int=armed[0]
		# Explicit nonlethal provocation and muzzle placement isolate actual
		# NPC-to-player contacts from steering/aim accuracy in this component.
		var before: Dictionary=encounter.snapshot()
		var attacking: RefCounted=encounter.fork_for_frame()
		if not attacking._combat.begin_contact_pass(stream,true):check(false,attacking._combat.error);return
		var hit: Dictionary=attacking._combat.normal_hit(id,int(attacking._combat.snapshot().actors[id].max_hull/2)+1)
		if hit.is_empty() or not attacking._combat.refresh_hostility(id):check(false,attacking._combat.error);return
		var fired: Dictionary=attacking._weapons.fire_combat_training(attacking._combat,[{"actor_id":id,"target_actor_id":-1,"pose":pose}])
		if fired.is_empty():check(false,attacking._weapons.error);return
		check(fired.actors[0].outcome.fired,"Prepared ambient gun did not fire")
		var prior_player: Dictionary=player.snapshot()
		var contact: Dictionary=attacking.evaluate_weapons(player,pose,0,field,attacking._combat.contact_random_state(),true)
		if contact.is_empty():check(false,attacking.error);return
		var event: Dictionary=contact.encounter.snapshot().weapon_events.filter(func(row):return row.actor_id==id)[0]
		check(event.contacts.size()==1 and event.contacts[0].damage.accepted,"Ambient projectile failed the actual player contact pass")
		check(contact.player.snapshot().vitals!=prior_player.vitals and player.snapshot()==prior_player,"Player contact did not stage its damaged pools independently")
		check(encounter.snapshot()==before,"Tentative mixed contact mutated committed actors")
		player_contacts+=1
	check(equipment.snapshot()==before_equipment and construction.snapshot()==original,"Mixed world changed station equipment or original construction")
	check(encounter.evaluate_world_logic(-1,stream).is_empty(),"Invalid world time was accepted")
	worlds+=1

func step(encounter: RefCounted,player: RefCounted,field: RefCounted,pose: Transform3D,dt: int,random: Dictionary) -> Dictionary:
	var before: Dictionary=encounter.snapshot()
	var logic: Dictionary=encounter.evaluate_world_logic(dt,random)
	if logic.is_empty():check(false,encounter.error);return {}
	var result: Dictionary=logic.encounter.evaluate_weapons(player,pose,dt,field,logic.random_state,true)
	if result.is_empty():check(false,logic.encounter.error);return {}
	var moved: Dictionary=result.encounter.evaluate_world(result.player,pose,dt,result.get("random_state",logic.random_state))
	if moved.is_empty():check(false,result.encounter.error);return {}
	check(encounter.snapshot()==before,"Prospective world phases changed their parent")
	return {"encounter":moved.encounter,"player":result.player,"scenery":result.scenery,"random_state":moved.random_state}
