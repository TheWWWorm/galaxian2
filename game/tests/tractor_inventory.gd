extends "res://tests/campaign_visit_save.gd"
## Detached retention vectors applied to forks of an earned station inventory.
## They do not earn recovery, rewrite the source save or create a campaign fixture.
const FlightHold=preload("res://src/simulation/flight_cargo.gd")
const RecoveryDefs=preload("res://src/content/tractor_recovery_definitions.gd")
const DepartureConstruction=preload("res://src/simulation/first_flight_construction.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const WreckChecks=preload("res://tests/full_hold_destruction.gd")
const FlightSession=preload("res://src/presentation/first_flight_session.gd")

func verify_save(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var file:=SaveFile.new();var archive:=Archive.new()
	var record:=file.load_document(OS.get_environment("GOF2_SOURCE_SAVE"),bindings,cat,library)
	if record.is_empty():check(false,file.error);return
	var station:=archive.restore(bindings,cat,library,record)
	if station==null:check(false,archive.error);return
	var original: Dictionary=station.snapshot();var fast:=-1
	for item in cat.tables.items:
		if item.properties.get(1)==1:fast=int(item.id);break
	if fast<0:check(false,"No source fast-stack item");return
	var cases:=[
		{"entries":[{"item_id":fast,"quantity":6},{"item_id":fast,"quantity":7}],"used":5},
		{"entries":[{"item_id":116,"quantity":1,"mission":true}],"used":1},
		{"entries":[{"item_id":117,"quantity":1,"mission":true}],"used":1},
		{"entries":[{"item_id":fast,"quantity":original.cargo.capacity+1}],"used":2},
	]
	if load("res://src/content/post_sahi_definitions.gd").available(bindings):
		# Isolated archive vector for the source Sahi crystal marker. This does
		# not advance the earned input or claim a completed Sahi save journey.
		cases.append({"entries":[{"item_id":131,"quantity":1,"mission":true}],"used":1})
	for vector in cases:
		var inventory: RefCounted=station.equipment_owner()
		var hold: Dictionary=inventory.snapshot().cargo.duplicate(true)
		hold.entries=vector.entries.duplicate(true);hold.used=vector.used;hold.free_space=hold.capacity-hold.used
		if not RecoveryDefs.available(bindings):
			var prior: Dictionary=inventory.snapshot()
			var courier: bool=vector.entries.size()==1 and vector.entries[0].get("mission",false) and vector.entries[0].item_id==int(bindings.early_contracts.courier.cargo_item_id)
			var retained: bool=inventory.retain_flight_cargo(hold)
			check(retained==courier and (inventory.snapshot().cargo==hold if courier else inventory.snapshot()==prior),"An older pack changed its existing courier or recovery capability boundary")
			continue
		if not inventory.retain_flight_cargo(hold):check(false,inventory.error);return
		var stale: bool=hold.used!=inventory._used(hold.entries)
		check(inventory.cargo_cache_valid() and inventory.snapshot().cargo==hold and inventory.snapshot().cargo_cache_stale==stale,"Equipment lost the ordered hold or its source used-space cache")
		if hold.entries.size()==2:
			# Distinct retained prices are a detached component vector. Recovery
			# must preserve row order when both stacks have the same item ID.
			var priced: RefCounted=inventory.fork()
			var prices:=[{"item_id":fast,"unit_price":101},{"item_id":fast,"unit_price":202}]
			priced._state.prices.cargo=prices.duplicate(true)
			var more:=hold.duplicate(true);more.entries[0].quantity+=1;more.entries[1].quantity+=1
			check(priced.retain_flight_cargo(more) and priced.snapshot().prices.cargo==prices and inventory.snapshot().cargo==hold,"Recovery reassigned ordered duplicate prices or changed its parent inventory")
		var flight:=FlightHold.new()
		check(flight.configure_equipment(bindings,cat,inventory) and flight.snapshot()==hold,"Flight normalized a retained recovery hold: "+flight.error)
		var branch: RefCounted=station.fork();branch._retain_equipment(inventory)
		var data: Dictionary=archive.capture(branch,bindings)
		var restored: RefCounted=archive.restore(bindings,cat,library,data)
		if restored==null:check(false,archive.error);return
		check(archive.capture(restored,bindings)==data and restored.snapshot().cargo==hold,"Station archive normalized or lost a source-valid recovery hold")
		check(not restored.prepare_departure(bindings,cat).is_empty(),"Cached used space was replaced by the list sum during departure: "+restored.error)
		var construction:=DepartureConstruction.new()
		check(construction.prepare_free(bindings,cat,restored,4096,1789100000),construction.error)
		if failures:return
		var launched:=FlightHold.new()
		check(launched.configure_departure(bindings,cat,construction) and launched.snapshot()==hold,"Reconstructed flight lost the retained recovery hold: "+launched.error)
		if not restored.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,restored.error);return
		var opened: Dictionary=restored.snapshot()
		check(opened.cargo==hold and opened.cargo_cache_stale==stale,"Initial hangar setup refreshed the original cached used space")
		check(opened.contracts.credits==original.contracts.credits and opened.mission==original.mission and opened.progress==original.progress and opened.contracts.passengers==original.contracts.passengers,"Hangar entry changed career state while quoting the recovery hold")
		if vector.entries[0].get("mission",false):
			check(not restored.equipment_action("sell",vector.entries[0].item_id,bindings,cat) and restored.snapshot()==opened,"The recovered source-protected item could be sold")
		else:
			if not restored.equipment_action("sell",fast,bindings,cat):check(false,restored.error);return
			var updated: Dictionary=restored.snapshot();var sum:=0
			for row in updated.cargo.entries:sum+=int(row.quantity)
			check(updated.cargo.used==sum and updated.cargo.free_space==updated.cargo.capacity-sum and not updated.cargo_cache_stale,"An explicit inventory commit failed to refresh used space")
		if not restored.close_equipment():check(false,restored.error);return
		var committed: Dictionary=archive.capture(restored,bindings)
		var reloaded: RefCounted=archive.restore(bindings,cat,library,committed)
		check(reloaded!=null and reloaded.snapshot()==restored.snapshot(),"A completed inventory operation could not save/load its exact retained result: "+archive.error)
		var forged:=data.duplicate(true);forged.inventory.cargo_cache_stale=not stale
		check(archive.restore(bindings,cat,library,forged)==null,"A forged inventory cache marker was accepted")
		forged=data.duplicate(true);forged.station.cargo_cache_stale=not stale
		check(archive.restore(bindings,cat,library,forged)==null,"Station and inventory cache markers could disagree")
		check(station.snapshot()==original and archive.capture(station,bindings)==record,"Detached retention checks changed the actual earned input")
	check(station.snapshot()==original,"Recovery checks mutated the original station")
	if RecoveryDefs.available(bindings):
		var fitted:=verify_device_stock(bindings,cat,library,station)
		if fitted==null or failures:return
		verify_world_recovery(bindings,cat,library,fitted)
		if not failures:verify_world_recovery(bindings,cat,library,fitted,true)
	else:
		var unsupported:=record.duplicate(true)
		unsupported.station.progress.cargo_recovered=0;unsupported.career.progress.cargo_recovered=0
		check(archive.restore(bindings,cat,library,unsupported)==null,"An older content pack accepted an unsupported recovery counter")

func verify_device_stock(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> RefCounted:
	# The actual earned ship owns its original scanner in cargo. Make room by
	# exchanging the real armor, never by editing slots or granting equipment.
	var original: Dictionary=station.snapshot()
	var branch: RefCounted=station.fork()
	if not branch.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,branch.error);return null
	var opened: Dictionary=branch.snapshot()
	var scanners: Array=opened.equipment.market_rows.filter(func(row):return row.item_id==81 and row.owned==1 and not row.mission)
	check(scanners.size()==1 and 81 not in opened.loadout.equipment_ids,"The actual paid save lost its owned, unmounted scanner")
	var armor:=-1
	for i in opened.loadout.slots.size():
		var slot: Variant=opened.loadout.slots[i]
		if slot!=null and slot.category==3 and cat.tables.items[slot.item_id].arrays[2][5]==10:armor=i;break
	if armor<0 or failures:check(false,"The actual ship has no armor slot to exchange");return null
	var armor_id: int=opened.loadout.slots[armor].item_id
	if not branch.equipment_action("unmount",armor_id,bindings,cat,armor) or not branch.equipment_action("mount",81,bindings,cat):check(false,branch.error);return null
	var fitted: Dictionary=branch.snapshot()
	check(81 in fitted.loadout.equipment_ids and armor_id not in fitted.loadout.equipment_ids and fitted.loadout.slots[armor].item_id==81,"The ordinary fitting transaction did not exchange the real devices")
	check(fitted.contracts==opened.contracts and fitted.mission==opened.mission and fitted.progress==opened.progress,"Installing the owned scanner changed credits, passengers or earned progress")
	check(fitted.cargo.used==opened.cargo.used and fitted.equipment.transactions==opened.equipment.transactions+2,"The real scanner exchange lost cargo or transaction ownership")
	if not branch.close_equipment():check(false,branch.error);return null
	var archive:=Archive.new()
	var record: Dictionary=archive.capture(branch,bindings)
	var restored: RefCounted=archive.restore(bindings,cat,library,record)
	if restored==null:check(false,archive.error);return null
	check(restored.snapshot()==branch.snapshot() and not restored.prepare_departure(bindings,cat).is_empty(),"The legitimately fitted scanner could not round-trip and prepare flight")
	var reversal: RefCounted=restored.fork()
	if not reversal.open_equipment(bindings,cat,library,[1789100000,1789100000,1789100000]):check(false,reversal.error);return null
	if not reversal.equipment_action("unmount",81,bindings,cat,armor) or not reversal.equipment_action("mount",armor_id,bindings,cat) or not reversal.close_equipment():check(false,reversal.error);return null
	check(reversal.snapshot().loadout==original.loadout and reversal.snapshot().cargo==original.cargo,"Removing the scanner failed to restore the actual owned inventory")
	check(station.snapshot()==original,"The fitted branch changed the retained paid save")
	print("Earned scanner fitting: original cargo, armor exchange, passenger retention, save/load and departure passed")
	return restored

func verify_world_recovery(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted,freighter:=false) -> void:
	var bodies:=FlightSession.Bodies.new();var effects:=FlightSession.Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	var construction:=DepartureConstruction.new()
	if not construction.prepare_free(bindings,cat,station.fork(),4096,1789100000,true,bodies,effects):check(false,construction.error);return
	var encounter:=Encounter.new()
	if not encounter.configure_free(bindings,cat,library,construction):check(false,encounter.error);return
	var career: RefCounted=construction.contract_owner()
	if not encounter.bind_contract_session(career,bindings):check(false,encounter.error);return
	var state: Dictionary=construction.snapshot();var random: Dictionary=state.random_state
	if not freighter:verify_scenery_recovery(bindings,cat,library,encounter,construction,career,station)
	if failures:return
	var selected:=-1
	for actor in encounter.combat_snapshot().actors:
		if not actor.active or actor.actor_kind not in [0,1,2,3]:continue
		if actor.population_group not in (["freighter"] if freighter else ["patrol","travel"]):continue
		var death: RefCounted=encounter.npc_destruction_owner(actor.actor_id)
		if death!=null and death.snapshot().cargo.eligible:selected=actor.actor_id;break
	if selected<0:check(false,"The retained departure has no active generated faction cargo fixture");return
	# A synthetic lethal hit drives the real generated population and retained
	# controller. Recovery vectors remain detached; this earns no career progress.
	if not encounter._combat.begin_contact_pass(random,false):check(false,encounter._combat.error);return
	var hit: Dictionary=encounter._combat.normal_hit(selected,100000)
	if not hit.get("destroyed_now",false):check(false,"The generated cargo actor did not enter its lethal path");return
	random=encounter._combat.contact_random_state()
	for tick in (300 if freighter else 30):
		var next: Dictionary=encounter.evaluate_world(construction.player_owner(),state.player_pose,150,random)
		if next.is_empty():check(false,encounter.error);return
		encounter=next.encounter;random=next.random_state
		if encounter.npc_destruction_owner(selected).snapshot().phase==("wreck" if freighter else "explosion"):break
	if encounter.npc_destruction_owner(selected).snapshot().phase!=("wreck" if freighter else "explosion"):check(false,"The generated cargo actor never completed its real breakup");return
	verify_hud_recovery(bindings,cat,library,encounter,selected,construction,career,station)
	if failures:return
	var fixture:=WreckChecks.new()
	fixture.verify_recovery_encounter(bindings,cat,encounter,selected,construction.player_owner(),random)
	if freighter:
		checks+=fixture.checks;failures+=fixture.failures;fixture.free()
		return
	# Reach the other real lifetime branch without changing a clock or flag.
	for tick in 31:
		var next: Dictionary=encounter.evaluate_world(construction.player_owner(),state.player_pose,150,random)
		if next.is_empty():check(false,encounter.error);fixture.free();return
		encounter=next.encounter;random=next.random_state
		if not encounter.npc_destruction_owner(selected).snapshot().effect.active:break
	var stopped: Dictionary=encounter.evaluate_world(construction.player_owner(),state.player_pose,0,random)
	if stopped.is_empty():check(false,encounter.error);fixture.free();return
	encounter=stopped.encounter;random=stopped.random_state
	check(encounter.npc_destruction_owner(selected).snapshot().retire_on_transfer,"The actual inactive-effect zero-time update failed to arm pickup retirement")
	fixture.verify_recovery_encounter(bindings,cat,encounter,selected,construction.player_owner(),random)
	checks+=fixture.checks;failures+=fixture.failures;fixture.free()

func verify_scenery_recovery(bindings: RefCounted,cat: RefCounted,library: RefCounted,encounter: RefCounted,construction: RefCounted,career: RefCounted,station: RefCounted) -> void:
	var scenery: RefCounted=construction.scenery_owner().fork_for_frame()
	var initial: Dictionary=scenery.snapshot();var world_before: Dictionary=encounter.snapshot()
	var index:=-1
	for row in initial.objects:
		if row.source_size_value!=7:index=row.index;break
	if index<0:check(false,"The actual field has no ordinary ore asteroid");return
	# Independent component RNG vector: roll19, then quantity3. The native
	# destruction path still creates the item and model; no player gains cargo.
	scenery._bodies=scenery._bodies.fork_for_frame();scenery._random_state={"state":25214903899}
	if not scenery._bodies.normal_hit(index,2147483647).get("destroyed_now",false) or not scenery.update(100,Vector3.ZERO):check(false,scenery.error);return
	var drop: Dictionary=scenery.snapshot();var actor: Dictionary=scenery.recovery_observation(index)
	if actor.is_empty():check(false,scenery.error);return
	check(actor.cargo_entries[0].quantity==3 and actor.cargo_model_exists and actor.statistics_exempt and actor.target_group=="scenery","The native drop lost its scenery recovery contract")
	verify_scenery_hud(bindings,cat,library,construction,encounter,scenery,index)
	if failures:return
	var camera:=Transform3D(Basis.IDENTITY,actor.cargo_pose.origin+Vector3(0,0,1300))
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"pose":camera,"autopilot":false}
	var loadout: Dictionary=construction.equipment_owner().snapshot().loadout.duplicate(true);loadout.equipment_ids=[69,81]
	var tractor:=Encounter.Recovery.new();var hold:=FlightHold.new()
	if not tractor.configure(bindings,cat,loadout,library) or not hold.configure_equipment(bindings,cat,construction.equipment_owner()):check(false,tractor.error+hold.error);return
	hold._equipment_ids=loadout.equipment_ids.duplicate()
	if not hold.bind_recovery(tractor) or not tractor.queue_acquired_wreck(actor):check(false,hold.error+tractor.error);return
	var held: Dictionary=hold.snapshot();var requested: Dictionary=tractor.snapshot()
	var npc:=actor.duplicate(true);npc.erase("target_group")
	check(not tractor.advance(0,player,npc,held) and tractor.snapshot()==requested,"An NPC with the same numeric index replaced the retained scenery target")
	var started: Dictionary=encounter.evaluate_cargo_recovery(tractor,hold,0,player,scenery)
	if started.is_empty():check(false,encounter.error);return
	check(started.frame.phase=="started" and started.scenery.snapshot()==drop and started.cargo.snapshot()==held,"Scenery recovery skipped its first player-phase delay")
	check(started.tractor.target_group()=="scenery","The current tractor forgot the selected population")
	var pulling: Dictionary=started.encounter.evaluate_cargo_recovery(started.tractor,started.cargo,100,player,started.scenery)
	if pulling.is_empty():check(false,started.encounter.error);return
	var moved: Dictionary=pulling.scenery.snapshot();var displacement:=Vector3(0,0,1000)
	check(pulling.frame.phase=="pulling" and moved.objects[index].position==drop.objects[index].position+displacement and moved.destruction[index].lifecycle.cargo.pose.origin==actor.cargo_pose.origin+displacement,"The scenery physical model and junk did not share the source tractor displacement")
	check(moved.bodies==drop.bodies and moved.destruction[index].effect==drop.destruction[index].effect and moved.random_state==drop.random_state and moved.destroyed_count==drop.destroyed_count,"A scenery pull moved statistics, collision bounds, breakup pose, RNG or destruction accounting")
	var resumed: RefCounted=pulling.scenery.fork_for_frame()
	check(resumed.update(100,Vector3.ZERO) and resumed.snapshot().bodies.objects[index].position==drop.bodies.objects[index].position,"A pulled scenery lifecycle incorrectly required physical and statistics positions to match")
	var failed: RefCounted=pulling.encounter.fork_for_frame();failed._combat=pulling.encounter._combat.fork_for_frame()
	failed._combat._recovery_totals=failed.recovery_totals();failed._combat._recovery_totals.accepted_quantity=2147483647
	var failed_before: Dictionary=failed.snapshot();var device_before: Dictionary=pulling.tractor.snapshot()
	check(failed.evaluate_cargo_recovery(pulling.tractor,pulling.cargo,0,player,pulling.scenery).is_empty() and failed.snapshot()==failed_before and pulling.scenery.snapshot()==moved and pulling.cargo.snapshot()==held and pulling.tractor.snapshot()==device_before,"A late scenery accounting failure committed cargo, physical state or a transfer serial")
	var foreign: RefCounted=pulling.scenery.fork_for_frame();foreign._presentation_identity=RefCounted.new()
	check(pulling.encounter.evaluate_cargo_recovery(pulling.tractor,pulling.cargo,0,player,foreign).is_empty() and pulling.tractor.snapshot()==device_before,"Matching content hashes admitted another scenery world's target")
	var pickup: Dictionary=pulling.encounter.evaluate_cargo_recovery(pulling.tractor,pulling.cargo,0,player,pulling.scenery)
	if pickup.is_empty():check(false,pulling.encounter.error);return
	var collected: Dictionary=pickup.scenery.snapshot();var life: Dictionary=collected.destruction[index].lifecycle
	check(pickup.frame.phase=="pickup" and pickup.frame.transfer.accepted_quantity==3 and not life.cargo_model_exists and not life.drop_allowed and life.cargo.quantity==0 and not collected.bodies.objects[index].active,"Scenery pickup failed to commit its item, model removal, eligibility and statistics retirement together")
	check(collected.bodies.objects[index].position==drop.bodies.objects[index].position and collected.destruction[index].effect==moved.destruction[index].effect,"Scenery pickup rewrote its frozen statistics or captured breakup")
	check(pickup.encounter.combat_snapshot().actors==encounter.combat_snapshot().actors and pickup.encounter.recovery_totals().accepted_quantity==3,"Scenery pickup changed an identically indexed NPC or lost the shared recovery counter")
	check(hold.snapshot()==held and tractor.snapshot()==requested,"Scenery recovery mutated its parent hold or queued device")
	# The accepted branch rejects replay; the independent parent hold remains a
	# valid alternative branch, so do not mistake rollback for a duplicate pickup.
	check(not pickup.cargo.retain_recovery(pickup.tractor),"The same scenery transfer serial was accepted twice")
	var repeated: RefCounted=pickup.tractor.fork_for_frame()
	if not repeated.queue_acquired_wreck(actor):check(false,repeated.error);return
	check(pickup.encounter.evaluate_cargo_recovery(repeated,pickup.cargo,0,player,pickup.scenery).is_empty(),"A stale request recreated consumed scenery cargo")
	verify_recovery_career(bindings,cat,library,station,career,pickup)
	if failures:return
	# The ordinary effect clock can retire statistics without consuming junk.
	var retired: RefCounted=scenery.fork_for_frame()
	for tick in 120:
		if not retired.update(100,Vector3.ZERO):check(false,retired.error);return
	var old: Dictionary=retired.recovery_observation(index)
	check(not old.active and old.cargo_model_exists and old.cargo_eligible,"Effect expiry hid the retained scenery drop")
	var late_tractor:=Encounter.Recovery.new();var late_hold:=FlightHold.new()
	if not late_tractor.configure(bindings,cat,loadout) or not late_hold.configure_equipment(bindings,cat,construction.equipment_owner()):check(false,late_tractor.error+late_hold.error);return
	late_hold._equipment_ids=loadout.equipment_ids.duplicate()
	if not late_hold.bind_recovery(late_tractor) or not late_tractor.queue_acquired_wreck(old):check(false,late_hold.error+late_tractor.error);return
	player.pose=Transform3D(Basis.IDENTITY,old.cargo_pose.origin)
	var late_start: Dictionary=encounter.evaluate_cargo_recovery(late_tractor,late_hold,0,player,retired)
	if late_start.is_empty():check(false,encounter.error);return
	var late_pickup: Dictionary=late_start.encounter.evaluate_cargo_recovery(late_start.tractor,late_start.cargo,0,player,retired)
	check(not late_pickup.is_empty() and late_pickup.frame.transfer.accepted_quantity==3,"Inactive scenery statistics cancelled a valid retained pickup")
	var full: RefCounted=late_start.cargo.fork_for_frame();var full_before: Dictionary=full.snapshot()
	if not full.add_entries([{"item_id":0,"quantity":full_before.capacity-full_before.used}]):check(false,full.error);return
	full_before=full.snapshot()
	var rejected: Dictionary=late_start.encounter.evaluate_cargo_recovery(late_start.tractor,full,0,player,retired)
	if rejected.is_empty():check(false,late_start.encounter.error);return
	var remainder: Dictionary=rejected.scenery.snapshot().destruction[index].lifecycle
	check(rejected.frame.phase=="pickup" and rejected.frame.transfer.quantity==1 and rejected.frame.transfer.accepted_quantity==0 and rejected.cargo.snapshot()==full_before and remainder.cargo.quantity==2 and not remainder.cargo_model_exists and not remainder.drop_allowed and rejected.encounter.recovery_totals().accepted_quantity==0,"A full hold changed the scenery remainder, re-offered the model or credited unaccepted cargo")
	check(scenery.snapshot()==drop and construction.scenery_owner().snapshot()==initial and encounter.snapshot()==world_before,"Detached scenery recovery changed its source world or construction")

func verify_scenery_hud(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted,encounter: RefCounted,scenery: RefCounted,index: int) -> void:
	var frame: RefCounted=load("res://src/simulation/first_flight_frame.gd").new()
	if not frame.configure(bindings,cat,library,construction,"E",1.0,Vector2i(800,600)):check(false,frame.error);return
	# Keep the real frame, world and inventory owners around an explicit detached
	# tractor loadout. The separate application check earns the device and fitting.
	var equipped: RefCounted=load("res://src/simulation/first_flight_construction.gd").new()
	equipped._state=construction.snapshot();equipped._scenery=construction.scenery_owner()
	equipped._camera=construction.camera_owner();equipped._player=construction.player_owner()
	equipped._state.departure.loadout.equipment_ids=[69,81]
	var loadout: Dictionary=equipped._state.departure.loadout
	var frame_art: Dictionary=frame.TargetFrame.source_geometry(library,bindings)
	var strip: Dictionary=frame.ScanAnimation.source_geometry(library,bindings,bindings.mining_targeting)
	if not frame._targeting.configure(bindings,cat,equipped,frame.TargetFrame.logical_radii(frame_art.quarter_size,false),strip.frames):check(false,frame._targeting.error);return
	frame._tractor=Encounter.Recovery.new()
	if not frame._tractor.configure(bindings,cat,loadout,library):check(false,frame._tractor.error);return
	frame._cargo._equipment_ids=loadout.equipment_ids.duplicate()
	if not frame._cargo.bind_recovery(frame._tractor):check(false,frame._cargo.error);return
	frame._encounter=encounter.fork_for_frame();frame._scenery=scenery.fork_for_frame()
	var drop: Dictionary=scenery.recovery_observation(index)
	var camera:=Transform3D(Basis.IDENTITY,drop.cargo_pose.origin+Vector3(0,0,1300))
	frame._pose=camera
	var aim:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"point":Vector3(400,300,0),"viewport_size":Vector2i(800,600)}
	var held: Dictionary=frame._cargo.snapshot();var initial: Dictionary=scenery.snapshot()
	for tick in 38:
		if not frame._advance_scenery_hud(100,true,camera,aim):check(false,frame.error);return
	check(frame._tractor.snapshot().request_actor_id==-1 and frame._targeting.snapshot().elapsed_ms==3800,"The flight queued scenery cargo at the strict scanner boundary")
	var suspended: RefCounted=frame.fork_for_frame()
	if not suspended._autopilot.observe_manual(camera,Vector2.ZERO) or not suspended._autopilot.start(camera):check(false,suspended._autopilot.error);return
	if not suspended._advance_scenery_hud(100,true,camera,aim):check(false,suspended.error);return
	check(suspended._tractor.snapshot().request_actor_id==-1 and suspended._targeting.snapshot().elapsed_ms==3800,"Actual station guidance queued scenery cargo or lost its acquisition time")
	if not frame._advance_scenery_hud(1,true,camera,aim):check(false,frame.error);return
	var request: Dictionary=frame._tractor.snapshot()
	check(request.request_actor_id==index and request.request_group=="scenery" and request.candidate_actor_id==-1 and not request.active and frame._cargo.snapshot()==held,"Scenery HUD changed the NPC candidate, moved cargo or failed to queue its own population")
	if not frame._advance_tractor(0):check(false,frame.error);return
	check(frame._tractor_frame.phase=="started" and frame._cargo.snapshot()==held and frame._scenery.snapshot()==initial,"Scenery acquisition skipped the first player-phase delay")
	if not frame._advance_scenery_hud(100,true,camera,aim):check(false,frame.error);return
	check(frame._targeting.snapshot().recovery_object_index==-1 and frame._tractor.snapshot().request_actor_id==index,"An active request was overwritten by a second scenery acquisition")
	if not frame._advance_tractor(100) or not frame._advance_tractor(0):check(false,frame.error);return
	check(frame._tractor_frame.phase=="pickup" and frame._tractor_frame.transfer.accepted_quantity==3 and frame._equipment.snapshot().cargo==frame._cargo.snapshot(),"Connected scenery HUD/player phases failed to retain the actual accepted cargo")
	check(frame._encounter.combat_snapshot().actors==encounter.combat_snapshot().actors and scenery.snapshot()==initial,"Scenery HUD recovery changed the NPC population or the retained parent field")

func verify_hud_recovery(bindings: RefCounted,cat: RefCounted,library: RefCounted,encounter: RefCounted,selected: int,construction: RefCounted,career: RefCounted,station: RefCounted) -> void:
	# Real generated population and destruction, with a detached device/camera
	# vector. This tests the bridge, not an earned purchase or playable save.
	var recovery:=Encounter.Recovery.new()
	var loadout: Dictionary=construction.equipment_owner().snapshot().loadout.duplicate(true)
	loadout.equipment_ids=[69,81]
	if not recovery.configure(bindings,cat,loadout,library):check(false,recovery.error);return
	var cargo:=FlightHold.new()
	if not cargo.configure_equipment(bindings,cat,construction.equipment_owner()):check(false,cargo.error);return
	# Match the detached device vector without rewriting the source equipment,
	# construction or save. Production still verifies the exact equipped list.
	cargo._equipment_ids=loadout.equipment_ids.duplicate()
	if not cargo.bind_recovery(recovery):check(false,cargo.error);return
	var projection=load("res://src/presentation/target_projection.gd").new()
	if not projection.configure(bindings.flight_projection,Vector2i(900,800)):check(false,projection.error);return
	var actor: Dictionary=encounter.combat_snapshot().actors[selected]
	var camera:=Transform3D(Basis.IDENTITY,actor.pose.origin+Vector3(0,0,1300))
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"enabled":true,"guidance_active":false,"alternate_operation_active":false,"mining_approach_active":false,
		"alternate_approach_active":false,"autopilot":false,"other_target_selected":false,
		"ordinary_scan_enabled":true,"ordinary_scan_blocked":false,"aim_pixels":Vector2(450,400),"viewport_size":Vector2i(900,800)}
	var original: Dictionary=encounter.snapshot();var held: Dictionary=cargo.snapshot()
	var device_before: Dictionary=recovery.snapshot()
	for tick in 18:
		var next: RefCounted=encounter.acquire_cargo_target(recovery,100,projection,camera,context).get("tractor")
		if next==null:check(false,encounter.error);return
		if tick==0:check(recovery.snapshot()==device_before,"HUD preparation mutated the retained parent device")
		recovery=next
	check(recovery.snapshot().candidate_actor_id==selected and recovery.snapshot().elapsed_ms==1800 and recovery.snapshot().request_actor_id==-1,
		"The actual projected wreck did not retain its strict acquisition clock")
	var lost_context:=context.duplicate();lost_context.aim_pixels=Vector2(9000,8000)
	var lost: RefCounted=encounter.acquire_cargo_target(recovery,1,projection,camera,lost_context).get("tractor")
	if lost==null:check(false,encounter.error);return
	check(lost.snapshot().elapsed_ms==0 and lost.snapshot().candidate_actor_id==-1 and lost.snapshot().request_actor_id==-1,
		"Losing the actual wreck did not clear its unearned acquisition clock")
	var paused_context:=context.duplicate();paused_context.enabled=false
	var hidden: RefCounted=encounter.acquire_cargo_target(recovery,100,projection,camera,paused_context).get("tractor")
	if hidden==null:check(false,encounter.error);return
	check(hidden.snapshot().elapsed_ms==1800 and hidden.snapshot().request_actor_id==-1,
		"Hidden HUD advanced a pending recovery request")
	var blocked_context:=context.duplicate();blocked_context.autopilot=true
	var blocked: RefCounted=encounter.acquire_cargo_target(recovery,100,projection,camera,blocked_context).get("tractor")
	if blocked==null:check(false,encounter.error);return
	check(blocked.snapshot().elapsed_ms==1800 and blocked.snapshot().request_actor_id==-1,
		"Autopilot advanced timed wreck acquisition")
	var acquired: RefCounted=encounter.acquire_cargo_target(recovery,1,projection,camera,context).get("tractor")
	if acquired==null:check(false,encounter.error);return
	check(acquired.snapshot().request_actor_id==selected and not acquired.snapshot().active,"HUD acquisition moved the wreck before the next player phase")
	check(encounter.snapshot()==original and cargo.snapshot()==held,"Acquiring a target changed the world, cargo or accounting")
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"pose":camera,"autopilot":false}
	var started: Dictionary=encounter.evaluate_cargo_recovery(acquired,cargo,0,player)
	if started.is_empty():check(false,encounter.error);return
	check(started.frame.phase=="started" and started.frame.actor_changes.is_empty() and started.cargo.snapshot()==held,
		"The first player phase moved or collected the acquired wreck")
	var pulling: Dictionary=started.encounter.evaluate_cargo_recovery(started.tractor,started.cargo,100,player)
	if pulling.is_empty():check(false,started.encounter.error);return
	check(pulling.frame.phase=="pulling" and pulling.frame.events==[{"kind":"sound","source_id":0}],"The next player phase lost its real pull and loop event")
	var pickup: Dictionary=pulling.encounter.evaluate_cargo_recovery(pulling.tractor,pulling.cargo,0,player)
	if pickup.is_empty():check(false,pulling.encounter.error);return
	check(pickup.frame.phase=="pickup" and pickup.frame.transfer.accepted_quantity>0,"The acquired native wreck failed to transfer cargo")
	verify_recovery_career(bindings,cat,library,station,career,pickup)
	if failures:return
	check(encounter.snapshot()==original and cargo.snapshot()==held,"A detached recovery changed the retained input world or hold")
	var before: Dictionary=recovery.snapshot();var wrong:=context.duplicate();wrong.binding_id="0".repeat(64)
	check(encounter.acquire_cargo_target(recovery,100,projection,camera,wrong).is_empty() and recovery.snapshot()==before,
		"A foreign HUD context partially advanced the retained tractor")
	var invalid_projection=projection.get_script().new()
	check(encounter.acquire_cargo_target(recovery,100,invalid_projection,camera,context).is_empty() and recovery.snapshot()==before,
		"An unconfigured projection changed the retained acquisition")
	verify_hud_frame(bindings,cat,library,construction,encounter,recovery,cargo,camera,context)

## Actual pickup owners feed the real retained career. Only detached branches
## are altered for failure vectors; no synthetic state becomes an earned fixture.
func verify_recovery_career(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted,career: RefCounted,pickup: Dictionary) -> void:
	var original: Dictionary=career.snapshot();var world: Dictionary=pickup.encounter.snapshot()
	var station_before: Dictionary=station.snapshot();var quantity: int=pickup.frame.transfer.accepted_quantity
	var retained: Dictionary=pickup.encounter.evaluate_contract_session(career,false,false)
	if retained.is_empty():check(false,pickup.encounter.error);return
	var earned: Dictionary=retained.session.snapshot()
	check(earned.progress.get("cargo_recovered",0)==int(original.progress.get("cargo_recovered",0))+quantity,
		"The live career lost the quantity accepted by its actual recovery transaction")
	check(earned.credits==original.credits and earned.completed_side_missions==original.completed_side_missions and earned.mission==original.mission and earned.passengers==original.passengers,
		"A cargo pickup paid a contract or changed its retained passengers")
	var repeated: Dictionary=pickup.encounter.evaluate_contract_session(retained.session,false,false)
	check(not repeated.is_empty() and repeated.session.snapshot()==earned,"Repeated career polling counted the same recovered cargo twice")
	var blocked: RefCounted=career.fork();blocked._state.progress.cargo_recovered=2147483647
	var blocked_before: Dictionary=blocked.snapshot()
	check(pickup.encounter.evaluate_contract_session(blocked,false,false).is_empty() and blocked.snapshot()==blocked_before and pickup.encounter.snapshot()==world,
		"Career overflow partly committed a pickup, faction change or reward")
	var stale: RefCounted=pickup.encounter.fork_for_frame();stale._combat=pickup.encounter._combat.fork_for_frame()
	stale._combat._recovery_totals=stale.recovery_totals();stale._combat._recovery_totals.accepted_quantity-=1
	var stale_before: Dictionary=stale.snapshot()
	check(stale.evaluate_contract_session(retained.session,false,false).is_empty() and stale.error.contains("recovery quantity") and stale.snapshot()==stale_before and retained.session.snapshot()==earned,
		"A regressed recovery observation changed the retained career")
	var foreign: RefCounted=pickup.encounter._control.fork_for_frame();foreign._flight_identity=RefCounted.new()
	check(retained.session.evaluate_flight(foreign,false,false).is_empty() and retained.session.snapshot()==earned,
		"An unrelated native flight could retain another world's recovery")
	var finished: RefCounted=pickup.encounter.finish_contract_session(retained.session)
	var unpolled: RefCounted=pickup.encounter.finish_contract_session(career)
	if finished==null or unpolled==null:check(false,pickup.encounter.error);return
	check(finished.snapshot()==unpolled.snapshot() and finished.snapshot().progress==earned.progress and not finished.snapshot().has("flight"),
		"Docking missed an unpolled pickup, duplicated it or retained the old flight ledger")
	check(pickup.encounter.finish_contract_session(finished)==null,"The released flight could be finished twice")
	# Apply those exact finished owners to an archive boundary vector, without
	# inventing a docking flight or replacing the real input station/save.
	var branch: RefCounted=station.fork();var inventory: RefCounted=station.equipment_owner()
	if not inventory.retain_flight_cargo(pickup.cargo.snapshot()):check(false,inventory.error);return
	branch._retain_equipment(inventory);branch._contracts=finished
	branch._state.progress=finished.snapshot().progress.duplicate(true)
	var archive:=Archive.new();var data: Dictionary=archive.capture(branch,bindings)
	var restored: RefCounted=archive.restore(bindings,cat,library,data)
	if restored==null:check(false,archive.error);return
	check(archive.capture(restored,bindings)==data and restored.snapshot().progress==earned.progress and restored.snapshot().cargo==pickup.cargo.snapshot(),
		"Saving and reloading lost the accepted recovery quantity or its cargo")
	verify_files(bindings,cat,library,station,branch,archive.capture(station,bindings),data)
	if failures:return
	for value in [-1,2147483648,1.0,true,"1"]:
		var forged:=data.duplicate(true)
		forged.station.progress.cargo_recovered=value;forged.career.progress.cargo_recovered=value
		check(archive.restore(bindings,cat,library,forged)==null,"A malformed recovery career counter was accepted: "+var_to_str(value))
	var mismatch:=data.duplicate(true);mismatch.station.progress.cargo_recovered+=1
	check(archive.restore(bindings,cat,library,mismatch)==null,"The station and career could disagree on recovered cargo")
	check(career.snapshot()==original and station.snapshot()==station_before and pickup.encounter.snapshot()==world,
		"Recovery retention changed its source career, station or pickup branch")

func verify_hud_frame(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted,encounter: RefCounted,recovery: RefCounted,cargo: RefCounted,camera: Transform3D,context: Dictionary) -> void:
	var frame=load("res://src/simulation/first_flight_frame.gd").new()
	if not frame.configure(bindings,cat,library,construction,"E",1.0,context.viewport_size):check(false,frame.error);return
	# Use the actual prepared flight owners around the detached wreck/device
	# vector. This does not enable fitting or write an earned gameplay fixture.
	frame._encounter=encounter.fork_for_frame();frame._tractor=recovery.fork_for_frame()
	frame._cargo=cargo.fork_for_frame();frame._pose=camera
	# The normal fitting transaction supplied the scanner to this flight.
	check(frame._scanner._equipment==int(recovery.snapshot().scanner_id),"The flight lost its legitimately fitted scanner")
	if failures:return
	var aim: Dictionary=frame._aim.snapshot()
	aim.point=Vector3(context.aim_pixels.x,context.aim_pixels.y,0)
	# The small-ship fixture has a later living competitor. This generated
	# freighter occupies the last eligible group, so it tests acquisition alone.
	var target: int=recovery.snapshot().candidate_actor_id
	if encounter.combat_snapshot().actors[target].population_group!="freighter":verify_competing_hud(frame,aim)
	if failures:return
	var held: Dictionary=cargo.snapshot();var device_before: Dictionary=recovery.snapshot()
	if not frame._advance_npc_hud(1,true,camera,aim):check(false,frame.error);return
	check(frame._tractor.snapshot().request_actor_id>=0 and not frame._tractor.snapshot().active and frame._cargo.snapshot()==held,
		"The real flight HUD failed to queue recovery without collecting cargo")
	check(frame._scanner.snapshot().elapsed_ms==0,"Cargo scanning advanced an unrelated ordinary scanner clock")
	if not frame._advance_tractor(0):check(false,frame.error);return
	var first: Dictionary=frame._tractor_frame.duplicate(true)
	check(first.phase=="started" and frame._cargo.snapshot()==held,"The flight player phase skipped the source start delay")
	if not frame._advance_npc_hud(0,true,camera,aim):check(false,frame.error);return
	check(frame._tractor_frame==first,"HUD acquisition overwrote the player's presentation sample")
	if not frame._advance_tractor(100):check(false,frame.error);return
	var pull: Dictionary=frame._tractor_frame.duplicate(true)
	if not frame._advance_npc_hud(0,true,camera,aim):check(false,frame.error);return
	check(frame._tractor_frame==pull and pull.events==[{"kind":"sound","source_id":0}],"The HUD lost the actual pull's loop-audio event")
	if not frame._advance_tractor(0):check(false,frame.error);return
	check(frame._tractor_frame.phase=="pickup" and frame._tractor_frame.transfer.accepted_quantity>0,
		"The connected flight phases did not retain recovered cargo")
	check(frame._equipment.snapshot().cargo==frame._cargo.snapshot(),"Flight equipment did not retain the recovered hold")
	check(cargo.snapshot()==held and recovery.snapshot()==device_before,"The flight phase test mutated its input device or cargo")

func verify_competing_hud(frame: RefCounted,aim: Dictionary) -> void:
	var combat: Dictionary=frame._encounter.combat_snapshot()
	var target: int=frame._tractor.snapshot().candidate_actor_id
	var wreck: Vector3=combat.actors[target].pose.origin
	var retained: Dictionary=frame._scanner.snapshot()
	# Align the camera through two actual bodies, without moving either one.
	# A later living ship would scan in isolation, but cannot steal the wreck's
	# earlier source-order acquisition when both lie in the same HUD window.
	for actor in combat.actors:
		if actor.actor_id<=target or not actor.active or actor.actor_mode in [3,4]:continue
		var offset: Vector3=actor.pose.origin-wreck
		if offset.length_squared()<1.0:continue
		var direction:=offset.normalized()
		if absf(direction.dot(Vector3.UP))>.99:continue
		var camera:=Transform3D(Basis.looking_at(direction,Vector3.UP),wreck-direction*1300.0)
		var ordinary: RefCounted=frame._scanner.fork_for_frame()
		if not ordinary.advance(combat,camera,camera,aim,1,true):check(false,ordinary.error);return
		if ordinary.snapshot().elapsed_ms==0:continue
		var shared: RefCounted=frame.fork_for_frame();shared._pose=camera
		if not shared._advance_npc_hud(1,true,camera,aim):check(false,shared.error);return
		if shared._tractor.snapshot().request_actor_id!=target:continue
		check(shared._scanner.snapshot().elapsed_ms==0 and ordinary.snapshot().elapsed_ms>0,
			"The shared HUD advanced both cargo and living-ship acquisition")
		check(frame._scanner.snapshot()==retained,"A competing-target probe changed its retained scanner")
		return
	check(false,"The real ordered population did not exercise competing ship/cargo acquisition for wreck %d"%target)
