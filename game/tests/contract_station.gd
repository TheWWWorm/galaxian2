extends "res://tests/contract_frame.gd"
## One earned opening followed by a generated Courier and actual frame guidance
## and docking. Stock/time/career inputs for earlier hidden populations remain
## explicit fixtures, not an application opening RNG trace.
const LoungeLifecycle=preload("res://src/content/lounge_lifecycle_definitions.gd")
const LocationCache=preload("res://src/simulation/lounge_cache.gd")
var station_verified:=false
var _accepted_station: RefCounted

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	check(station_verified,"Station contracts did not retain their actual arrival and acknowledged delivery")
	print("Contract station: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func after_contract_intro(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	if not LoungeLifecycle.available(bindings):
		check(not Contracts.new().rebase_station(station.equipment_owner()),"Older content enabled retained station contracts")
		station_verified=true;return
	_world_bodies=Bodies.new();_world_effects=Effects.new()
	if not _world_bodies.configure(library,bindings) or not _world_effects.configure(library,bindings):check(false,_world_bodies.error+_world_effects.error);return
	# Search independent declared seeds, not one live career. The selected fixture
	# has an affordable generated Courier whose actual destination is Deuter IV.
	for seed_value in 128:
		var current: RefCounted=station.fork()
		if not current.open_contracts(bindings,cat) or not prepare_lounge_fixture(bindings,cat,library,current,seed_value):check(false,current.error);return
		for contact in current.snapshot().contracts.population.contacts:
			if contact.offer.is_empty() or contact.offer.mission.kind!=0 or contact.offer.mission.station_id!=75 or not current.contract_preview(contact.contact_id).can_accept:continue
			if not current.accept_contract(contact.contact_id):check(false,current.error);return
			_accepted_station=current
			print("Contract station generated Courier fixture: seed %d, contact %d"%[seed_value,contact.contact_id])
			break
		if _accepted_station!=null:break
	if _accepted_station==null:check(false,"No supported generated Courier fixture was found");return
	var construction:=Construction.new()
	if not construction.prepare(bindings,cat,_accepted_station.prepare_contract_departure(bindings,cat),4096,1789100000,true,_world_bodies,_world_effects,_accepted_station.equipment_owner(),_accepted_station.contract_owner()):check(false,construction.error);return
	var untouched: Dictionary=_accepted_station.snapshot()
	var undocked:=LiveFrame.new()
	if not undocked.configure(bindings,cat,library,construction,"D",1.0):check(false,undocked.error);return
	check(not StationEntry.new().configure_return(bindings,cat,library,undocked),"An undocked flight opened station services")
	verify_pending_travel(bindings,cat,library,construction)
	check(_accepted_station.snapshot()==untouched,"The new visit mutated the retained departure")

func prepare_lounge_fixture(bindings: RefCounted,cat: RefCounted,library: RefCounted,current: RefCounted,seed_value: int) -> bool:
	var random:=Random.new();random.seed_from(seed_value)
	if not bindings.early_contracts.has("station_generation"):
		var history: Array=[];history.resize(15);history.fill(false)
		return current.populate_contracts(bindings,cat,library,random.snapshot(),history)
	var cache:=LocationCache.new()
	if not cache.configure(bindings):check(false,cache.error);return false
	var settings:={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,"energy_availability_percent":0,"missile_availability_percent":0}
	# These explicit location/career fixtures test original quotation retention.
	# The inherited station still supplies the actual earned current inventory.
	var context:={"campaign_cursor":1,"station_id":78,"rank":0,"reputation":{"axes":[30,0],"override":-1}}
	for visit in [[78,1],[78,6],[79,11],[76,12],[79,13]]:
		context.station_id=visit[0];context.campaign_cursor=visit[1]
		if not cache.select_location(bindings,cat,library,context,settings,random.snapshot(),1789423200+seed_value+visit[1]):check(false,cache.error);return false
		random.restore(cache.snapshot().random)
	if not current.retain_contract_locations(cache):return false
	check(current.snapshot().contracts.population.context.campaign_cursor==11,"First usable lounge discarded its earlier quotation context")
	var before: Dictionary=current.snapshot()
	check(not current.retain_contract_locations(cache) and current.snapshot()==before,"Reattaching locations reset a retained lounge")
	return true

func after_contract_docking(bindings: RefCounted,cat: RefCounted,library: RefCounted,flight: RefCounted) -> void:
	var original: Dictionary=flight.snapshot()
	var packet: Dictionary=flight.prepare_station()
	var station:=StationEntry.new()
	if not station.configure_return(bindings,cat,library,flight):check(false,station.error);return
	var arrived: Dictionary=station.snapshot()
	check(arrived.campaign_cursor==13 and arrived.phase=="contracts_required" and not arrived.dialogue.visible,"The station replayed the lounge introduction or advanced the story")
	check(arrived.loadout.station_id==75 and arrived.contracts.station_id==75 and arrived.contracts.offers.is_empty(),"The destination kept the departure lounge's contacts")
	check(arrived.contracts.accepted_contact==packet.contracts.accepted_contact and arrived.contracts.mission==packet.contracts.mission,"Station rebase detached the unfinished contract from its original client")
	check(arrived.player_cache==packet.player_cache and arrived.cargo==packet.cargo and arrived.progress==packet.progress,"Station entry changed current vitals, cargo or progress")
	check(arrived.contracts.credits==0 and arrived.completed_side_missions==0,"Docking paid or completed an unacknowledged delivery")
	verify_cached_return(bindings,cat,library,station)
	if failures:return
	check(not station.acknowledge_contract_result(1) and station.snapshot()==arrived,"Close completed a result before polling")
	if not station.poll_contract_result():check(false,station.error);return
	var pending: Dictionary=station.snapshot()
	var result: Dictionary=pending.contracts.pending_result
	check(not result.is_empty() and result.kind==0 and result.station_id==75,"The actual destination did not produce the Courier result")
	check(pending.completed_side_missions==0 and pending.contracts.credits==0 and pending.cargo==arrived.cargo,"Opening the result paid, counted or unloaded it early")
	check(pending.progress==pending.contracts.progress and pending.mission==arrived.mission,"The delivery result split reputation ownership or changed the story")
	check(station.poll_contract_result() and station.snapshot()==pending,"Repeated polling duplicated the delivery result or standing change")
	check(station.prepare_contract_departure(bindings,cat).is_empty(),"An open delivery result allowed departure")
	check(not station.acknowledge_contract_result(result.serial+1) and station.snapshot()==pending,"A stale Close acknowledged a different result")
	if not station.acknowledge_contract_result(result.serial):check(false,station.error);return
	var closed: Dictionary=station.snapshot()
	check(closed.contracts.credits==result.reward_credits and closed.completed_side_missions==1 and closed.contracts.completed_side_missions==1,"Close lost the earned payment or completion count")
	check(closed.contracts.mission.is_empty() and closed.contracts.accepted_contact.is_empty() and closed.cargo.used==arrived.cargo.used-int(arrived.contracts.mission.quantity),"Close retained delivered cargo or the completed job")
	check(closed.progress==closed.contracts.progress and closed.progress.other_score==arrived.progress.other_score+2 and closed.mission==arrived.mission and closed.campaign_cursor==13,"Delivery changed the four-contract story requirement or career score")
	check(not station.acknowledge_contract_result(result.serial) and station.snapshot()==closed,"A duplicate Close paid twice")
	check(station.poll_contract_result() and station.snapshot()==closed,"Polling recreated a settled delivery")
	var next_packet: Dictionary=station.prepare_contract_departure(bindings,cat)
	check(not next_packet.is_empty(),"The settled destination could not prepare departure: "+station.error)
	if next_packet.is_empty():return
	var next:=Construction.new()
	check(next.prepare(bindings,cat,next_packet,4096,1789100000,true,_world_bodies,_world_effects,station.equipment_owner(),station.contract_owner()),next.error)
	check(flight.snapshot()==original,"Station settlement mutated its retained flight")
	verify_cached_return(bindings,cat,library,station)
	station_verified=failures==0

func verify_cached_return(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	# Explicit inventory relocation fixtures isolate cache retention across all
	# locations. The live flight/docking path above supplies the actual delivery.
	var owner: RefCounted=station.contract_owner()
	var equipment: RefCounted=station.equipment_owner()
	var initial: Dictionary=owner.snapshot()
	var expected_order: Array=initial.lounges.locations.map(func(row):return row.station_id)
	var random:=Random.new();random.seed_from(8192)
	for id in [75,77,79,76,78,79]:
		var retained:={}
		for entry in owner.snapshot().lounges.locations:
			if entry.station_id==id:retained=entry
		# Relocate with the same validated local arrival descriptor used by travel.
		if equipment.snapshot().loadout.station_id!=id:
			var visit:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":13,
				"from_station_id":equipment.snapshot().loadout.station_id,"station_id":id,"system_id":15,
				"source_state":int(bindings.mido_travel.travel.source_state),"world_type":int(bindings.mido_travel.travel.world_type),
				"audio_selector":int(bindings.mido_travel.travel.audio_selector)}
			if not equipment.relocate_local_arrival(bindings,cat,visit):check(false,equipment.error);return
		if not owner.rebase_station(equipment):check(false,owner.error);return
		var current: Dictionary=owner.snapshot()
		if current.has("population"):
			check(current.population==retained.population and current.offers==retained.offers,"A cached return repriced or revived its consumed contact")
		else:
			if not owner.populate(bindings,cat,library,random.snapshot(),current.lounges.history):check(false,owner.error);return
			check(random.restore(owner.snapshot().population.random),random.error)
			expected_order.append(id)
			if expected_order.size()>3:expected_order.pop_front()
		check(owner.snapshot().progress==initial.progress and owner.snapshot().credits==initial.credits and owner.snapshot().completed_side_missions==initial.completed_side_missions,"Contact replacement changed the retained career")
		check(owner.snapshot().mission==initial.mission and owner.snapshot().accepted_contact==initial.accepted_contact,"Contact eviction replaced the accepted job or its original client")
	check(owner.snapshot().lounges.locations.map(func(row):return row.station_id)==expected_order,"Station rebasing retained the wrong contact cache")
	if not initial.mission.is_empty():
		# The original client has been evicted, and the new origin lounge reuses
		# local contact IDs. Settlement still uses the independently retained job.
		check(owner.poll_station(station.equipment_owner()),owner.error)
		var result: Dictionary=owner.snapshot().pending_result
		check(not result.is_empty() and result.reward_credits==initial.mission.reward+initial.mission.bonus,"Evicting the client changed or lost the accepted delivery payment")
