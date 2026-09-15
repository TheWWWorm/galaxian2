extends "res://tests/contract_acceptance.gd"
## Native departure/destination construction and complete ordered weapon/NPC
## passes. Offers, lounge seeds and acquisition inputs remain disclosed fixtures;
## the application frame and station result UI are separate integration work.
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const ContractEncounter=preload("res://src/simulation/full_hold_encounter.gd")
const LocalTransit=preload("res://src/simulation/local_travel.gd")
var worlds_verified:=0
var _world_bodies: RefCounted
var _world_effects: RefCounted
var fired_shots:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	check(worlds_verified>0,"No ordinary contract world was verified")
	print("Ordinary contract worlds: %d checks; %d worlds; %d primary shots; %d failures"%[checks,worlds_verified,fired_shots,failures])
	quit(1 if failures else 0)

func after_contract_intro(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	if not ContractWorld.available(bindings):
		check(station.prepare_contract_departure(bindings,cat).is_empty(),"Older content enabled ordinary contract worlds")
		worlds_verified=1;return
	_world_bodies=Bodies.new();_world_effects=Effects.new()
	if not _world_bodies.configure(library,bindings) or not _world_effects.configure(library,bindings):check(false,_world_bodies.error+_world_effects.error);return
	for kind_index in [-1,1,2,3,4]:
		var current: RefCounted=station.fork()
		if not current.open_contracts(bindings,cat):check(false,current.error);return
		if kind_index==4:
			var found:=false
			for seed_value in 128:
				current=station.fork()
				var random:=Random.new();random.seed_from(seed_value)
				var history: Array=[];history.resize(15);history.fill(false)
				if not current.open_contracts(bindings,cat) or not current.populate_contracts(bindings,cat,library,random.snapshot(),history):check(false,current.error);return
				for contact in current.snapshot().contracts.population.contacts:
					if contact.offer.is_empty() or contact.offer.mission.kind!=12:continue
					if not current.accept_contract(contact.contact_id):check(false,current.error);return
					found=true;break
				if found:break
			if not found:check(false,"The fixture could not find an actual generated Challenge");return
		elif kind_index>=0:
			var state: Dictionary=current.snapshot()
			var context:={"campaign_cursor":13,"station_id":79,"rank":state.progress.rank,"reputation":state.progress.reputation.duplicate(true),"client_faction":3}
			var offer:=Offer.new()
			if not offer.configure(bindings,cat,context,{"kind_index":kind_index,"difficulty_index":0,"destination_station_id":75,"cargo_description_index":0}):check(false,offer.error);return
			if not current.register_contract_offer(0,offer) or not current.accept_contract(0):check(false,current.error);return
		var before: Dictionary=current.snapshot()
		var packet: Dictionary=current.prepare_contract_departure(bindings,cat)
		if packet.is_empty():check(false,current.error);return
		var owner:=Construction.new()
		var session: RefCounted=current.contract_owner()
		if not owner.prepare(bindings,cat,packet,4096,1789100000,true,_world_bodies,_world_effects,current.equipment_owner(),session):check(false,owner.error);return
		check(current.snapshot()==before and session.snapshot()==before.contracts,"World preparation mutated the retained station or side slot")
		check(owner.snapshot().departure.cargo==before.cargo and owner.snapshot().departure.mission==before.mission and owner.snapshot().departure.progress==before.contracts.progress,"Departure changed inventory or awarded progress")
		verify_world(bindings,cat,library,owner)
		if failures:return
		# All five Mido locations, including the active target and the return to
		# its origin. Acquisition is an explicit input to the shared travel owner.
		for station_id in [75,77,78,76,79]:
			var entry: Dictionary=owner.snapshot()
			var travel:=LocalTransit.new()
			if not travel.configure_flight(bindings,cat,owner.equipment_owner(),entry):check(false,travel.error);return
			for tick in 50:
				if travel.snapshot().phase!="flight":break
				if not travel.sample_acquisition(150,station_id,station_id,true):check(false,travel.error);return
			for tick in 100:
				if travel.snapshot().phase=="arrival_required":break
				if not travel.advance_launch(150):check(false,travel.error);return
			var objective:={}
			for key in ["base_content_id","binding_id","campaign_cursor"]:objective[key]=entry[key]
			for key in ["mission","progress","station_response_flags"]:objective[key]=entry.departure[key].duplicate(true)
			var prior_contracts: Dictionary=owner.contract_owner().snapshot()
			var expected_contracts:=prior_contracts.duplicate(true)
			# Transport rebases the current station and its already-cached local
			# offers. The accepted job retains its original contact independently.
			if station_id!=int(prior_contracts.station_id):
				expected_contracts.station_id=station_id;expected_contracts.offers={};expected_contracts.erase("population")
				var cached: Dictionary=owner.contract_owner().location_owner().location(station_id)
				if not cached.is_empty():expected_contracts.offers=cached.offers;expected_contracts.population=cached.population
			var arrived:=Construction.new()
			if not arrived.prepare_local_arrival(bindings,cat,travel,owner.player_owner(),owner.equipment_owner(),4096,1789100000,true,_world_bodies,_world_effects,objective,owner.contract_owner()):check(false,arrived.error);return
			check(arrived.snapshot().location.station_id==station_id and arrived.snapshot().departure.cargo==entry.departure.cargo,"Local arrival lost its actual destination or cargo")
			check(arrived.contract_owner().snapshot()==expected_contracts,"Transport changed the pending contract, original client or expected station cache")
			check(owner.contract_owner().snapshot()==prior_contracts,"Destination preparation mutated the departing contract owner")
			owner=arrived
			verify_world(bindings,cat,library,owner)
			if failures:return
		# Invalid packets must leave an already prepared construction intact.
		var retained: Dictionary=owner.snapshot()
		var broken:=packet.duplicate(true);broken.contracts.credits+=1
		check(not owner.prepare(bindings,cat,broken,4096,1789100000,true,_world_bodies,_world_effects,current.equipment_owner(),session) and owner.snapshot()==retained,"A mismatched contract packet replaced a good world")

func verify_world(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted) -> void:
	var entry: Dictionary=construction.snapshot()
	var world: Dictionary=entry.scenery.world_initialization
	var context: Dictionary=construction.contract_owner().flight_context(int(entry.location.station_id))
	check(world.contract_context==context,"World population did not use its retained accepted contract")
	var mission: Dictionary=context.mission
	var generated: Dictionary=world.npc_construction
	if mission.is_empty():check(generated.has("population") and generated.actors.size()>0,"An empty active mission lost ordinary mixed traffic")
	else:
		check(generated.contract_encounter.mission==mission,"World replaced the active contract with an authored journey")
		if mission.kind==0:check(generated.actors.is_empty(),"Courier destination invented contract actors")
		if mission.kind==7:check(generated.actors.size()==17 and generated.actors.all(func(actor):return actor.population_group=="debris"),"Junk destination lost original debris")
	var random:=Random.new()
	if not random.restore(generated.random_state):check(false,random.error);return
	check(world.weapon_effects.size()==generated.actors.size(),"World omitted an actor's weapon allocation entry")
	for id in generated.actors.size():
		var actor: Dictionary=generated.actors[id]
		var effect: Dictionary=world.weapon_effects[id]
		if actor.population_group in ["debris","freighter"]:
			check(effect=={"actor_id":id,"unarmed":true},"Unarmed actor consumed impact allocation draws");continue
		var item: int=25 if actor.actor_kind==3 else 19 if actor.actor_kind==8 else 0 if actor.actor_kind==0 else 3 if actor.actor_kind==1 else 7
		for key in ["discarded_default","primary"]:
			var flips:=[]
			for slot in 4:flips.append(random.next_int(2)==0)
			check(effect[key].item_id==(0 if key=="discarded_default" else item) and effect[key].flipped==flips,"Weapon assignment order or post-construction RNG changed")
	check(random.snapshot()==world.random_state and entry.camera_input_random_state==world.random_state,"World/camera boundary lost the shared RNG")
	for draw in 4:random.next_int(2000 if draw<2 else 2)
	check(random.snapshot()==entry.random_state,"Ordinary camera did not follow weapon allocation")
	var encounter:=ContractEncounter.new()
	if not encounter.configure_contract_world(bindings,cat,library,construction):check(false,encounter.error);return
	var player: RefCounted=construction.player_owner()
	var field: RefCounted=construction.scenery_owner()
	var state: Dictionary=entry.random_state.duplicate(true)
	# A stationary player and continuously held primary input are explicit
	# component inputs. Run beyond entry and traffic-clock intervals so the
	# shared contact, projectile, guidance and actor owners execute together.
	if not player.set_permissions(true,true):check(false,player.error);return
	var shots:=0
	for tick in 80:
		var logic: Dictionary=encounter.evaluate_world_logic(150,state)
		if logic.is_empty():check(false,encounter.error);return
		encounter=logic.encounter;state=logic.random_state
		if player.advance_recharge(150).is_empty() or player.advance_repair(150).is_empty():check(false,player.error);return
		var contact: Dictionary=encounter.evaluate_weapons(player,entry.player_pose,150,field,state)
		if contact.is_empty():check(false,encounter.error);return
		encounter=contact.encounter;player=contact.player;field=contact.scenery
		if contact.has("random_state"):state=contact.random_state
		var fired: Dictionary=encounter.evaluate_primary_fire(player,entry.player_pose,true,true,state)
		if fired.is_empty():check(false,encounter.error);return
		encounter=fired.encounter;state=fired.random_state
		for gun in encounter.snapshot().primary_fire.get("weapons",[]):
			if gun.result.get("fired",false):shots+=1
		var actors: Dictionary=encounter.evaluate_world(player,entry.player_pose,150,state)
		if actors.is_empty():check(false,encounter.error);return
		encounter=actors.encounter;state=actors.random_state
	check(shots>0,"The complete ordinary world did not emit a player projectile")
	check(encounter.snapshot().world_elapsed_ms==12000 and construction.snapshot()==entry,"Ordinary combat mutated its prepared source world")
	fired_shots+=shots
	worlds_verified+=1
