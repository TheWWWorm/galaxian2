extends "res://tests/contract_acceptance.gd"
## Explicit accepted offers and RNG/placement fixtures verify construction.
## This does not run cursor13 actor control, docking or result presentation.
const NPCConstruction=preload("res://src/simulation/opening_npc_construction.gd")
const SceneryPopulation=preload("res://src/simulation/scenery_population.gd")
var encounter_verified:=false
var _vectors:=[]
var _verified_vectors:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:
		var lib:=Library.new();var bindings:=Bindings.new()
		if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest):check(false,lib.error+bindings.error)
		elif Terms.encounter_parameters(bindings.early_contracts):
			var file:=FileAccess.open(OS.get_environment("GOF2_CONTRACT_VECTORS"),FileAccess.READ)
			if file==null or file.get_length()>4*1024*1024:check(false,"Supply the independent encounter vectors")
			else:
				var data: Variant=JSON.parse_string(file.get_as_text())
				if not data is Array or data.size()!=140:check(false,"The encounter vectors are incomplete")
				else:_vectors=data;verify(args)
		else:
			check(not NPCConstruction.new().configure_contract(bindings,null,null,null,Vector3.ZERO,Vector3.ZERO),"An earlier pack enabled contract actors")
			encounter_verified=true
	check(encounter_verified,"Contract construction was not verified")
	print("Contract encounters: %d checks; %d failures; %d independent vectors"%[checks,failures,_verified_vectors])
	quit(1 if failures else 0)

func after_contract_intro(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	var original: RefCounted=station.fork()
	super.after_contract_intro(bindings,cat,library,station)
	for difficulty in [0,1]:
		for game in [0.5,1.0]:
			for kind_index in [1,2,3]:
				# The larger courier offer may exceed the retained starter hold.
				# Its empty flight population is the same already-covered branch.
				if kind_index==1 and difficulty==1:continue
				var next: RefCounted=original.fork()
				if not next.open_contracts(bindings,cat,game):check(false,next.error);return
				var before: Dictionary=next.snapshot()
				var context:={"campaign_cursor":13,"station_id":79,"rank":before.progress.rank,"reputation":before.progress.reputation.duplicate(true),"client_faction":3}
				var offer:=Offer.new()
				if not offer.configure(bindings,cat,context,{"kind_index":kind_index,"difficulty_index":difficulty,"destination_station_id":75,"cargo_description_index":0}):check(false,offer.error);return
				if not next.register_contract_offer(0,offer) or not next.accept_contract(0):check(false,next.error);return
				var equipment: RefCounted=next.equipment_owner()
				var contract: RefCounted=next._contracts.fork()
				check(not NPCConstruction.new().configure_contract(bindings,cat,equipment,contract,Vector3.ZERO,Vector3.ZERO),"A destination contract spawned at its departure station")
				# Explicit arrival event for this construction component; shared
				# navigation has separate acquisition/transport coverage.
				var arrival:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":13,"from_station_id":79,"station_id":75,"system_id":15,"source_state":2,"world_type":3,"audio_selector":1}
				if not equipment.relocate_local_arrival(bindings,cat,arrival):check(false,equipment.error);return
				verify_population_vectors(bindings,cat,equipment,contract)
	# Rival names and factions come from real generated contacts. Seeds here
	# are explicit component inputs, not the earlier hidden lounge history.
	for difficulty in [1,2]:
		var found:=false
		for seed_value in 128:
			var next: RefCounted=original.fork()
			var random:=Random.new();random.seed_from(seed_value)
			var history: Array=[];history.resize(15);history.fill(false)
			if not next.open_contracts(bindings,cat) or not next.populate_contracts(bindings,cat,library,random.snapshot(),history):check(false,next.error);return
			for contact in next.snapshot().contracts.population.contacts:
				if contact.offer.is_empty() or contact.offer.mission.kind!=12 or contact.offer.mission.difficulty!=difficulty:continue
				if not next.accept_contract(contact.contact_id):check(false,next.error);return
				verify_population_vectors(bindings,cat,next.equipment_owner(),next._contracts)
				found=true;break
			if found:break
		check(found,"A generated rival for the requested difficulty was not exercised")
	var scenery:=SceneryPopulation.new()
	if not scenery.configure(bindings):check(false,scenery.error);return
	for id in [75,76,77,78,79]:
		var center: Dictionary=scenery.for_departure(id,{"companions_empty":true,"location_match":false,"special_placement":false},13)
		check(not center.is_empty() and center.station_id==id and center.center is Vector3,"A Mido location lost its ordinary scenery centre")
	encounter_verified=true

func verify_population_vectors(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,contracts: RefCounted) -> void:
	var context: Dictionary=contracts.flight_context(int(equipment.snapshot().loadout.station_id))
	var before: Dictionary=contracts.snapshot();var inventory: Dictionary=equipment.snapshot()
	var matching: Array=_vectors.filter(func(row):return int(row.kind)==context.mission.kind and int(row.difficulty)==context.mission.difficulty and float(row.game)==context.difficulty and int(row.faction)==context.client_faction)
	check(matching.size()==5,"The accepted contract has no independent vector set")
	for vector in matching:
		var owner:=NPCConstruction.new()
		if not owner.configure_contract(bindings,cat,equipment,contracts,vec(vector.player),vec(vector.field)):check(false,owner.error);return
		check(owner.generate({"state":-1}).is_empty() and owner.snapshot().actors.is_empty(),"Invalid RNG partially generated an encounter")
		var random:=Random.new();random.seed_from(int(vector.seed))
		var state:=owner.generate(random.snapshot())
		if state.is_empty():check(false,owner.error);return
		check(state.campaign_cursor==13 and state.station_id==equipment.snapshot().loadout.station_id and state.actors.size()==vector.actors.size(),"The encounter changed its context or source population")
		check(state.random_state.state==int(vector.random_state),"Encounter changed the independent final RNG for "+str([vector.kind,vector.difficulty,vector.game,vector.seed]))
		var layout: Dictionary=state.contract_encounter
		check(layout.path==vector.path.map(vec) and layout.debris_center==vec(vector.center) and layout.unused_enemy_faction==int(vector.enemy),"The mission path, debris centre or dispatch draw changed")
		for id in state.actors.size():
			var actor: Dictionary=state.actors[id];var expected: Dictionary=vector.actors[id]
			check(actor.body_pose.origin==vec(expected.position) and actor.statistics_pose==actor.body_pose,"Actor placement differs from the source RNG trace")
			if int(vector.kind)==7:
				check(actor.resource_id==int(expected.mesh) and actor.actor_kind==-1 and actor.type_id==16917 and actor.hull==1 and actor.half_extent==1000 and actor.mode==0,"Junk changed its source model, bounds or initial state")
				check(actor.hostile and not actor.friendly and actor.cargo.is_empty() and actor.fragments.is_empty() and owner.route(id)==null,"Junk borrowed a ship route, cargo or breakup")
				continue
			check(actor.hull_catalogue_id==int(expected.hull) and actor.factory_position==vec(expected.factory_position) and actor.fragments.size()==int(expected.fragments),"Small-ship constructor changed hull, factory origin or fragments")
			check(actor.route.waypoints==expected.route.map(vec) and actor.cargo==expected.cargo.map(cargo_row),"The shared route or cargo sampler changed")
			var route: RefCounted=owner.route(id)
			check(route!=null and route.snapshot()==actor.route,"The live route differs from its constructed record")
			if int(vector.kind)==12 and id==0:
				check(actor.name==context.contact_name and actor.friendly and actor.current_hull_override==9999999 and actor.base_speed==3.0 and actor.speed==3.0,"The generated rival lost its original identity or overrides")
				check(actor.discarded_route.waypoints==expected.discarded_route.map(vec) and actor.discarded_cargo==expected.discarded_cargo.map(cargo_row) and not actor.route.loop,"Rival replacement skipped its discarded construction draws")
				for point in actor.route.waypoints:check(not route.advance(point).is_empty(),route.error)
				check(route.snapshot().completed and owner.route(id).snapshot().index==0,"Advancing the detached rival path changed the retained route")
			else:check(actor.actor_kind==8 and actor.mode==5 and not actor.active and actor.targeting_blocked,"Pirates activated before their source encounter trigger")
		check(owner.generate(random.snapshot()).is_empty() and owner.snapshot()==state,"The committed encounter rerolled its population")
		after_encounter_population(bindings,cat,owner,vector,equipment,contracts)
		check(contracts.snapshot()==before and equipment.snapshot()==inventory,"Encounter construction changed the contract reward, career or inventory")
		_verified_vectors+=1

func after_encounter_population(_bindings: RefCounted,_cat: RefCounted,_owner: RefCounted,_vector: Dictionary,_equipment: RefCounted,_contracts: RefCounted) -> void:pass

func vec(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])
func cargo_row(values: Array) -> Dictionary:return {"item_id":int(values[0]),"quantity":int(values[1])}
