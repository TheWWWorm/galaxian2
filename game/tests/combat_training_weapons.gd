extends "res://tests/combat_training_control.gd"
## Actual application equipment, then detached weapon/contact verification.
## Overlapping actor poses and near-lethal pools are deliberate boundary fixtures.
const TrainingWeaponRules=preload("res://src/content/combat_training_weapon_definitions.gd")
const TrainingGuns=preload("res://src/simulation/opening_npc_weapons.gd")
const TrainingPlayer=preload("res://src/simulation/opening_player_state.gd")
const TrainingPrimary=preload("res://src/simulation/primary_weapons.gd")
const TrainingMounts=preload("res://src/content/weapon_mounts.gd")
const TrainingShots=preload("res://src/simulation/ordinary_projectiles.gd")
const TrainingResolver=preload("res://src/simulation/weapon_loadout.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:await verify(args)
	if is_instance_valid(host):host.free()
	print("Combat-training weapons: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_second_return(args: PackedStringArray):
	await super.after_second_return(args)
	var before: Dictionary=host.session.snapshot()
	var equipment: RefCounted=host.session._world.equipment_owner()
	verify_training_weapons(args,equipment)
	check(host.session.snapshot()==before and not host.request_departure(),"Detached weapons changed station progress or exposed an unfinished flight")

func verify_training_weapons(args: PackedStringArray, equipment: RefCounted):
	var cat:=Catalogues.new()
	if not cat.open(lib):check(false,cat.error);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	var rules: Dictionary=bindings.combat_training_weapons
	if header.reader=="resource-registration-v119":check(TrainingWeaponRules.parameters(rules),"Current pack omitted combat-training weapons")
	if not TrainingWeaponRules.parameters(rules):
		check(not TrainingPlayer.new().configure_combat_training(bindings,cat,equipment),"Older pack invented equipped training player")
		check(not TrainingGuns.new().configure_combat_training(bindings,cat,TrainingWorld.new(),0,.5),"Older pack invented mixed NPC weapons")
		var resolver:=TrainingResolver.new();check(resolver.configure(bindings,cat,bindings.base_content_id),resolver.error)
		check(resolver.resolve(22,[22,90,81,55]).launch_mode=="unsupported","Older pack invented upgraded primary firing")
		return
	check(TrainingWeaponRules.validate(rules,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training,bindings.combat_training_control,bindings.station_equipment,bindings.opening_actors,bindings.weapon_parameters).is_empty(),"Training weapon source context rejected")
	for key in TrainingWeaponRules.VALUES:
		var bad:=rules.duplicate(true);bad[key]=null
		check(not TrainingWeaponRules.parameters(bad),"Changed weapon declaration accepted: "+key)
	for key in TrainingWeaponRules.SPANS:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not TrainingWeaponRules.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training,bindings.combat_training_control,bindings.station_equipment,bindings.opening_actors,bindings.weapon_parameters).is_empty(),"Disconnected weapon source span accepted: "+key)
	var gear_before: Dictionary=equipment.snapshot()
	var world:=TrainingWorld.new()
	check(world.configure_combat_training(bindings,cat,equipment,Vector3(10,10,10000),{"companions_empty":true,"location_match":false,"special_placement":false}),world.error)
	check(not world.generate({"state":int(TRAINING_GOLDEN[0].input_state)}).is_empty(),world.error)
	var retained:=world.snapshot()
	var player:=TrainingPlayer.new()
	check(not player.configure_combat_training(bindings,cat,EmptyEquipment.new()),"Empty equipment initialized player pools")
	var no_armor: RefCounted=equipment.fork();check(no_armor.transact("unmount",55),no_armor.error)
	check(not player.configure_combat_training(bindings,cat,no_armor),"Cargo armor initialized training player")
	check(player.configure_combat_training(bindings,cat,equipment),player.error)
	if player.snapshot().is_empty():return
	var stats:=player.snapshot();var loadout:=player.loadout()
	check(stats.campaign_cursor==7 and stats.ship_id==0 and stats.equipment_ids==[22,90,81,55],"Player construction replaced installed tutorial equipment")
	check(stats.capacities.armor_item_id==55 and stats.vitals.armor==cat.tables.items[55].properties[20] and stats.vitals.shield==stats.capacities.shield,"Equipped armor or shield did not reach fresh pools")
	check(stats.vitals.hull==stats.max_hull and stats.gamma==100.0 and player.cache_snapshot().campaign_cursor==7,"Departure failed to clear cached player pools")
	loadout.slots.clear();check(not player.loadout().slots.is_empty(),"Detached loadout mutated the player owner")
	var mounts:=TrainingMounts.new();check(mounts.open(lib,cat),mounts.error)
	verify_upgraded_primary(cat,mounts,player)
	var alternative: RefCounted=equipment.fork()
	check(alternative.transact("unmount",22) and alternative.transact("mount",0),alternative.error)
	var other_player:=TrainingPlayer.new();check(other_player.configure_combat_training(bindings,cat,alternative),other_player.error)
	var ordinary:=TrainingPrimary.new();check(ordinary.configure(bindings,cat,mounts,other_player.loadout()),ordinary.error)
	check(ordinary.snapshot().guns[0].projectiles.weapon.item_id==0 and not ordinary.snapshot().guns[0].projectiles.weapon.has("dispersion"),"Starter primary inherited upgraded spread")
	var guns:=TrainingGuns.new()
	for rank in [0,1]:
		for difficulty in [0.0,.5,10.0]:
			check(guns.configure_combat_training(bindings,cat,world,rank,difficulty),guns.error)
			for row in guns.snapshot().actors:
				var weapon: Dictionary=row.projectiles.weapon
				check(weapon.damage==3 and weapon.interval_ms==586 and weapon.lifetime_ms==3000 and weapon.speed_units_per_millisecond==16.0 and row.projectiles.slots.size()==4,"Training NPC inherited catalogue damage or cursor4 override")
				check(weapon.campaign_cursor==7 and weapon.nonplayer_source and weapon.collision_bounds.mode=="target","NPC gun lost context, attribution or bounds")
	for rank in [-1,2,0.0,true]:check(not guns.configure_combat_training(bindings,cat,world,rank,.5),"Unsupported rank configured training weapons")
	check(guns.configure_combat_training(bindings,cat,world,0,.5),guns.error)
	check(guns.snapshot().actors[3].projectiles.weapon.kind==0 and guns.snapshot().actors[3].definition.catalogue_kind==2 and guns.snapshot().actors[3].audio.source_id==53,"Gunant inherited the catalogue gun type or pirate sound")
	for id in 3:check(guns.snapshot().actors[id].projectiles.weapon.kind==1 and guns.snapshot().actors[id].audio.source_id==61,"Pirate weapon identity or sound changed")
	verify_mixed_training_contacts(cat,world,equipment,mounts)
	verify_training_fire_poses(cat,world,guns)
	check(world.snapshot()==retained and equipment.snapshot()==gear_before,"Detached weapons changed world construction or station ownership")

func verify_upgraded_primary(cat: RefCounted, mounts: RefCounted, player: RefCounted):
	var primary:=TrainingPrimary.new();check(primary.configure(bindings,cat,mounts,player.loadout()),primary.error)
	if primary.snapshot().is_empty():return
	var weapon: Dictionary=primary.snapshot().guns[0].projectiles.weapon
	check(weapon.item_id==22 and weapon.kind==2 and weapon.damage==2 and weapon.interval_ms==220 and weapon.lifetime_ms==1000 and weapon.speed_units_per_millisecond==18.0 and weapon.projectile_capacity==25,"Upgraded gun did not retain its catalogue and kind-specific parameters")
	var initial:=primary.snapshot();var seed:=training_seed(1)
	check(not primary.fire(Transform3D.IDENTITY,true,seed).weapons[0].result.fired and primary.snapshot()==initial,"Upgraded gun fired at interval equality")
	check(not primary.advance(1).is_empty(),primary.error)
	var ready:=primary.snapshot()
	check(primary.fire(Transform3D.IDENTITY,true).is_empty() and primary.snapshot()==ready,"Dispersed shot guessed a random state")
	check(primary.fire(Transform3D.IDENTITY,true,{"state":-1}).is_empty() and primary.snapshot()==ready,"Invalid spread state committed a shot")
	var denied:=primary.fire(Transform3D.IDENTITY,false,seed)
	check(denied.random_state==seed and not denied.weapons[0].result.fired and primary.snapshot()==ready,"Denied shot consumed randomness")
	var fired:=primary.fire(Transform3D.IDENTITY,true,seed)
	check(not fired.is_empty(),primary.error)
	if fired.is_empty():return
	var shot: Dictionary=fired.weapons[0].result.projectile
	check(fired.random_state.state==115427488297881 and shot.velocity==Vector3(0,-0.18180888891220093,17.999080657958984),"Upgraded primary changed its three source-precision dispersion draws")
	var mount: Vector3=ready.guns[0].mount.position
	check(shot.position==mount+Vector3(0,0,100) and primary.snapshot().guns[0].projectiles.available_slots==24,"Upgraded primary used constructor muzzle offset or emitted multiple shots")
	check(fired.weapons[0].audio_events.size()==1 and fired.weapons[0].audio_events[0].source_id==66 and primary.snapshot().loadout.slots[0].quantity==1,"Upgraded primary changed source sound selection or consumed equipment")
	var waiting:=primary.fire(Transform3D.IDENTITY,true,fired.random_state)
	check(waiting.random_state==fired.random_state and not waiting.weapons[0].result.fired,"Waiting shot consumed spread draws")
	var moved:=primary.advance(1001)
	check(moved.weapons[0].result.expired==[shot.id] and primary.snapshot().guns[0].projectiles.slots[0].remaining_ms==-1,"Upgraded shot did not retain its complete expiry step")
	check(primary.advance(0).weapons[0].result.cleared==[shot.id],"Expired upgraded shot did not clean up at zero delta")
	var malformed:=weapon.duplicate(true);malformed.dispersion.steps=3
	check(not TrainingShots.new().configure(malformed),"Unsupported upgraded dispersion accepted")
	malformed=weapon.duplicate(true);malformed.projectile_capacity=20
	check(not TrainingShots.new().configure(malformed),"Upgraded primary inherited the kind-zero pool")

func training_armed_group(cat: RefCounted, world: RefCounted) -> RefCounted:
	var live:=LiveTraining.new();check(live.configure(bindings,cat,world,0,.5),live.error)
	var operation:=live.advance(0,training_player(Vector3(10000,7000,160000)))
	check(not operation.is_empty(),live.error)
	var combat: RefCounted=live.combat_owner()
	for id in 4:
		check(combat.snapshot().actors[id].active,"Training fixture failed to activate a real actor")
		check(combat.set_pose(id,Transform3D(Basis.IDENTITY,Vector3(0,0,1000))),combat.error)
	return combat

func verify_mixed_training_contacts(cat: RefCounted, world: RefCounted, equipment: RefCounted, mounts: RefCounted):
	var combat:=training_armed_group(cat,world);var guns:=TrainingGuns.new();var player:=TrainingPlayer.new()
	check(guns.configure_combat_training(bindings,cat,world,0,.5),guns.error)
	check(player.configure_combat_training(bindings,cat,equipment),player.error)
	var player_pose:=Transform3D(Basis.IDENTITY,Vector3(0,0,1000))
	check(not guns.advance(1).is_empty(),guns.error)
	var fired:=guns.fire(combat,[3,2,1,0]);check(not fired.is_empty(),guns.error)
	if fired.is_empty():return
	for id in 4:check(fired.actors[id].actor_id==id and fired.actors[id].outcome.fired,"Mixed gun fire lost stable actor order")
	var before_guns:=guns.snapshot();var before_combat: Dictionary=combat.snapshot();var before_player:=player.snapshot()
	var passed:=guns.evaluate_combat_training_update(player,player_pose,combat,false,0)
	check(not passed.is_empty(),guns.error)
	if passed.is_empty():return
	check(guns.snapshot()==before_guns and combat.snapshot()==before_combat and player.snapshot()==before_player,"Mixed contact preparation mutated an input owner")
	for id in 4:
		var event: Dictionary=passed.actors[id]
		check(event.actor_id==id and event.contacts.size()==1 and event.motion.cleared==[1] and event.motion.moved.is_empty(),"Mixed contacts moved or cleared a shot between targets")
		var expected: Array=[0,1,2] if id==3 else [3]
		check(event.npc_contacts.map(func(row):return row.actor_id)==expected,"Mixed NPC target membership changed")
		check(event.last_contact_actor=={"group":"npc","index":expected[-1]},"Later NPC contact did not replace the null player actor")
		for contact in event.npc_contacts:check(contact.damage.before.hull-contact.damage.after.hull==3,"NPC damage acquired player-only scaling")
	check(before_player.vitals.armor==40 and before_player.vitals.shield==0.0 and passed.player.snapshot().vitals.armor==31 and passed.player.snapshot().vitals.hull==before_player.vitals.hull,"Player did not receive three hostile shots and zero friendly damage through its installed armor")
	check(passed.combat.snapshot().actors[3].vitals.hull==9999990,"Gunant was invulnerable or skipped pirate contacts")
	for id in 3:check(passed.combat.snapshot().actors[id].vitals.hull==45 and not passed.combat.snapshot().actors[id].nonplayer_kill,"Nonlethal Gunant hit was marked as a kill")
	var invalid: RefCounted=combat.fork_for_frame();invalid._actors[2]._state.position=Vector3(NAN,0,0)
	check(guns.evaluate_combat_training_update(player,player_pose,invalid,false,1).is_empty() and guns.snapshot()==before_guns and player.snapshot()==before_player,"Late NPC geometry failure leaked earlier player contacts")
	for bad_delta in [-1,true,1.5]:check(guns.evaluate_combat_training_update(player,player_pose,combat,false,bad_delta).is_empty() and guns.snapshot()==before_guns,"Invalid mixed delta committed a frame")
	check(guns.evaluate_player_update(player,player_pose,combat.shooter_states(),false,1).is_empty() and guns.snapshot()==before_guns,"Training weapons accepted an incomplete player-only pass")
	# Three near-lethal pirates overlap the same Gunant projectile. They must
	# all receive nonplayer attribution, with no campaign/reward side effects.
	var lethal:=TrainingGuns.new();check(lethal.configure_combat_training(bindings,cat,world,0,.5),lethal.error)
	for id in 3:check(not combat.normal_hit(id,47,false).is_empty(),combat.error)
	lethal.advance(1);check(lethal.fire(combat,[3]).actors[0].outcome.fired,lethal.error)
	var killed:=lethal.evaluate_combat_training_update(player,player_pose,combat,false,1)
	check(not killed.is_empty(),lethal.error)
	if killed.is_empty():return
	for id in 3:check(killed.combat.snapshot().actors[id].vitals.hull==0 and killed.combat.snapshot().actors[id].nonplayer_kill and killed.combat.snapshot().actors[id].actor_mode==1,"NPC lethal hit invented retirement or credited the player")
	var live:=LiveTraining.new();check(live.configure(bindings,cat,world,0,.5),live.error);var previous:=live.snapshot()
	check(live.advance(1,training_player(Vector3.ZERO),killed.combat).is_empty() and live.snapshot()==previous,"Unconnected cargo-aware death was silently completed")
	# The actual equipped player gun traverses all four NPCs in source order.
	combat=training_armed_group(cat,world)
	var primary:=TrainingPrimary.new();check(primary.configure(bindings,cat,mounts,player.loadout()),primary.error)
	primary.advance(1);var volley:=primary.fire(Transform3D.IDENTITY,true,training_seed(1))
	var center: Vector3=volley.weapons[0].result.projectile.position
	for id in 4:check(combat.set_pose(id,Transform3D(Basis.IDENTITY,center)),combat.error)
	check(not combat.normal_hit(0,46,false).is_empty(),combat.error)
	var hit:=primary.evaluate_npc_update(combat,[0,1,2,3],0)
	check(not hit.is_empty(),primary.error)
	if hit.is_empty():return
	check(hit.weapons[0].contacts.map(func(row):return row.actor_id)==[0,1,2,3] and hit.weapons[0].motion.cleared==[1],"Player gun failed to visit all NPCs before cleanup")
	check(hit.combat.snapshot().actors[0].vitals.hull==0 and not hit.combat.snapshot().actors[0].nonplayer_kill and hit.combat.snapshot().actors[3].vitals.hull==9999997,"Player gun acquired NPC attribution or protected friendly hull")

func verify_training_fire_poses(cat: RefCounted, world: RefCounted, guns: RefCounted):
	var combat:=training_armed_group(cat,world)
	check(not guns.advance(1).is_empty(),guns.error)
	var pose:=Transform3D(Basis(Vector3.UP,.25),Vector3(400,500,600))
	var requests: Array=[{"actor_id":3,"target_actor_id":0,"pose":pose}]
	var result: Dictionary=guns.fire_combat_training(combat,requests)
	check(not result.is_empty(),guns.error)
	if result.is_empty():return
	check(result.actors[0].outcome.fired and result.actors[0].outcome.projectile.position==pose.origin and result.actors[0].audio_events[0].position==pose.origin,"Training firing used the post-motion body instead of its retained request pose")
	var saved: Dictionary=guns.snapshot()
	requests[0].target_actor_id=3
	check(guns.fire_combat_training(combat,requests).is_empty() and guns.snapshot()==saved,"Gunant fired at himself through a forged request")
	requests[0].target_actor_id=0;requests.append(requests[0].duplicate())
	check(guns.fire_combat_training(combat,requests).is_empty() and guns.snapshot()==saved,"Duplicate retained firing request partially committed")
