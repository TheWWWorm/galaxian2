extends "res://tests/contract_acceptance.gd"
## Explicit offers, acquisition inputs and damage exercise the shared transport
## owners after the inherited native opening visits. No cursor13 encounter,
## player-controlled journey, station docking or shop purchase is claimed here.
const StationLocation=preload("res://src/simulation/arrival_location.gd")
const Navigation=preload("res://src/simulation/local_map.gd")
var navigation_verified:=false

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:
		var lib:=Library.new();var bindings:=Bindings.new()
		if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest):check(false,lib.error+bindings.error)
		elif Definitions.navigation_available(bindings.mido_travel,13):verify(args)
		else:
			check(Definitions.navigation_stations(bindings.mido_travel,13,79).is_empty() and Definitions.route(bindings.mido_travel,13,79,75).is_empty(),"Earlier declarations enabled ordinary contract navigation")
			check(Definitions.player_entry(bindings.mido_travel,79,13).is_empty(),"Earlier declarations constructed a later player")
			navigation_verified=true
	check(navigation_verified,"Contract navigation was not verified")
	print("Contract navigation: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func after_contract_intro(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	var original: RefCounted=station.fork()
	super.after_contract_intro(bindings,cat,library,station)
	verify_transport(bindings,cat,library,original,1)
	var passenger:=cabin_fixture(bindings,cat,original)
	if passenger!=null:verify_transport(bindings,cat,library,passenger,0)
	navigation_verified=true

func verify_transport(bindings: RefCounted,cat: RefCounted,library: RefCounted,source: RefCounted,kind: int) -> void:
	var station: RefCounted=source.fork()
	var before: Dictionary=station.snapshot()
	if not station.open_contracts(bindings,cat):check(false,station.error);return
	var offer:=offer_for(bindings,cat,before,kind)
	if offer==null or not station.register_contract_offer(0,offer) or not station.accept_contract(0):check(false,station.error);return
	var inventory: RefCounted=station.equipment_owner()
	var contract: RefCounted=station._contracts.fork()
	var accepted: Dictionary=contract.snapshot()
	var initial: Dictionary=inventory.snapshot()
	var cargo:=Cargo.new()
	if not cargo.configure_equipment(bindings,cat,inventory):check(false,cargo.error);return
	check(cargo.snapshot()==initial.cargo and cargo.field_identity()==null,"Cargo transfer changed rows or invented a mining field")
	var retained: Dictionary=cargo.snapshot()
	for row in [{"item_id":116,"quantity":1,"mission":false},{"item_id":0,"quantity":1,"mission":true},{"item_id":116,"quantity":1,"mission":1},{"item_id":116,"quantity":1,"mission":true,"extra":0}]:
		check(not cargo.add_entries([row]) and cargo.snapshot()==retained,"Invalid mission marker changed the retained hold")
	var merged: RefCounted=cargo.fork_for_frame()
	check(merged.add_entries([{"item_id":116,"quantity":1}]) and cargo.snapshot()==retained,"Prospective cargo acquisition changed the live hold")
	if kind==1:check(merged.snapshot().entries[-1].mission and merged.snapshot().entries[-1].quantity==15,"Merging unmarked cargo removed an existing mission marker")
	else:
		check(merged.add_entries([{"item_id":116,"quantity":1,"mission":true}]) and not merged.snapshot().entries[-1].has("mission"),"Merging marked cargo protected an existing ordinary row")
	var player:=Player.new()
	if not player.configure_local_travel(bindings,cat,inventory,null,13):check(false,player.error);return
	check(player.snapshot().vitals.hull==95 and player.snapshot().vitals.armor==40,"Ordinary station departure changed the source pool reset")
	# Explicit supported NPC hit, not a simulated combat encounter.
	var weapon:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"launch_mode":"ordinary","item_id":25,"category":0,"kind":0,"damage":3,"campaign_cursor":13,"nonplayer_source":true}
	check(player.set_permissions(true,true) and not player.weapon_hit(weapon,true,true,false).is_empty(),player.error)
	var pools: Dictionary=player.snapshot().vitals
	check(pools.armor<40,"The explicit damage fixture did not damage the player")
	var visited:=[]
	for destination in [75,77,78,79,76]:
		var origin:=int(inventory.snapshot().loadout.station_id)
		var navigation:=Navigation.new()
		var location:=StationLocation.new()
		var context:=location.resolve_local_travel(bindings,cat,inventory,player.cache_snapshot())
		if context.is_empty():check(false,location.error);return
		var map_context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":13,"location":context,"mission":before.mission,"local_travel":{"phase":"flight"}}
		if not navigation.configure(library,bindings,cat,map_context):check(false,navigation.error);return
		var rows: Array=navigation.snapshot().rows
		check(rows.size()==5 and rows.filter(func(row):return row.supported).size()==4 and rows.filter(func(row):return row.current).size()==1,"Ordinary map lost a local destination or selected the current station")
		check(navigation.select_station(destination) and navigation.request_confirmation() and navigation.destination()==destination,"The shared map did not confirm the selected planet")
		var owner:=Travel.new()
		var entry:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":13,"departure":{"mission":before.mission,"player_cache":player.cache_snapshot()}}
		if not owner.configure_flight(bindings,cat,inventory,entry):check(false,owner.error);return
		check(owner.target_position(origin)==null and owner.target_position(0)==null,"Navigation selected the current or foreign-system planet")
		for id in [75,76,77,78,79]:
			if id!=origin:check(owner.target_position(id) is Vector3,"A source local planet has no acquisition position")
		check(owner.prepare_arrival().is_empty(),"Navigation prepared arrival before acquiring and departing")
		var duration:=int(owner.snapshot().acquisition_duration_ms)
		var limit:=int(bindings.frame_clock.max_frame_milliseconds)
		var elapsed:=0
		while elapsed<duration:
			var step:=mini(limit,duration-elapsed)
			if not owner.sample_acquisition(step,destination,destination,true):check(false,owner.error);return
			elapsed+=step
		check(owner.snapshot().phase=="flight" and owner.snapshot().acquired_station_id==-1,"The source strict acquisition threshold changed")
		var paused: Dictionary=owner.snapshot()
		check(owner.sample_acquisition(1,destination,destination,true,true) and owner.snapshot()==paused,"Paused acquisition progressed")
		check(owner.sample_acquisition(1,destination,destination,true) and owner.snapshot().phase=="launch","Acquired autopilot target did not start its departure")
		elapsed=0
		while elapsed<3000:
			var step:=mini(limit,3000-elapsed)
			if not owner.advance_launch(step):check(false,owner.error);return
			elapsed+=step
		check(owner.prepare_arrival().is_empty(),"The source strict departure threshold changed")
		paused=owner.snapshot()
		check(owner.advance_launch(1,true) and owner.snapshot()==paused,"Paused departure progressed")
		check(owner.advance_launch(1),owner.error)
		var packet: Dictionary=owner.prepare_arrival()
		check(packet.from_station_id==origin and packet.station_id==destination and packet.campaign_cursor==13,"Navigation changed the chosen target or campaign")
		var prior: Dictionary=inventory.snapshot()
		var invalid: Dictionary=packet.duplicate(true);invalid.station_id=0
		check(not inventory.relocate_local_arrival(bindings,cat,invalid) and inventory.snapshot()==prior,"A rejected foreign arrival moved inventory")
		var arriving: RefCounted=inventory.fork()
		if not arriving.relocate_local_arrival(bindings,cat,packet):check(false,arriving.error);return
		var cache:=Cache.capture_local_arrival(bindings.mido_travel,prior.loadout,arriving.snapshot().loadout,player.snapshot())
		check(not cache.is_empty() and cache.values.armor==pools.armor and cache.values.hull==pools.hull,"Planet travel repaired damage or lost the surviving player")
		var restored:=Player.new()
		if not restored.configure_local_travel(bindings,cat,arriving,cache,13):check(false,restored.error);return
		check(restored.snapshot().vitals==pools and inventory.snapshot()==prior,"Arrival lost live vitals or mutated the departing owner")
		check(arriving.snapshot().cargo==initial.cargo and arriving.snapshot().prices==initial.prices and contract.snapshot()==accepted,"Navigation settled a contract, unloaded passengers or repriced cargo")
		if not cargo.configure_equipment(bindings,cat,arriving):check(false,cargo.error);return
		check(cargo.snapshot()==retained,"An arrival changed the marked flight cargo")
		inventory=arriving;player=restored;visited.append(origin)
	check(visited==[79,75,77,78,79] and player.cache_snapshot().station_id==76,"The retained native route omitted a Mido destination")
	# Station-result detection is an explicit docking-context fixture until its
	# flight scene is connected. Transport itself did not call this operation.
	check(contract.poll_station(inventory) and contract.snapshot().credits==accepted.credits and contract.snapshot().completed_side_missions==0,"Result opening paid before acknowledgement")
	var delivered: RefCounted=contract.acknowledge_delivery_result(inventory)
	check(delivered!=null and contract.snapshot().completed_side_missions==1 and contract.snapshot().campaign_cursor==13,"The transported delivery failed acknowledged settlement")
	if delivered!=null:check(delivered.snapshot().cargo==before.cargo,"Delivery changed the starter's ordinary cargo")
	check(station.snapshot().completed_side_missions==0 and station.snapshot().mission==before.mission,"Component travel bypassed the actual pending story")
