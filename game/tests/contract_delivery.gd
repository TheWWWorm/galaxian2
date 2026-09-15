extends "res://tests/contract_acceptance.gd"
## Destination locations and cabin installations below are explicit, detached
## component fixtures. They test settlement, not yet-connected contract flights.
const Delivery=preload("res://src/content/delivery_result_definitions.gd")
var delivery_verified:=false

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:
		var lib:=Library.new();var bindings:=Bindings.new()
		if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest):check(false,lib.error+bindings.error)
		elif Terms.delivery_parameters(bindings.early_contracts):verify(args)
		else:
			var owner:=Contracts.new()
			check(not owner.poll_station(null) and owner.acknowledge_delivery_result(null)==null and owner.active_mission_for(76).is_empty(),"Older content fabricated delivery settlement")
			delivery_verified=true
	check(delivery_verified,"Delivery results were not verified")
	print("Early contract delivery: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func after_contract_intro(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	var original: RefCounted=station.fork()
	super.after_contract_intro(bindings,cat,library,station)
	verify_deliveries(bindings,cat,original)
	verify_passenger_delivery(bindings,cat,original)
	verify_unmarked_delivery(bindings,cat,original)
	verify_result_reputation(bindings,cat,original)
	verify_result_limits(bindings)
	delivery_verified=true

func destination_fixture(inventory: RefCounted,station_id: int) -> RefCounted:
	# The retained inventory itself remains real; only arrival is a fixture until
	# ordinary cursor13 travel is connected to the native station owner.
	var result: RefCounted=inventory.fork()
	result._state.loadout.station_id=station_id
	return result

func prepare_offer(bindings: RefCounted,cat: RefCounted,owner: RefCounted,id: int,kind_index: int,faction: int=3) -> bool:
	var state: Dictionary=owner.snapshot()
	var offer:=Offer.new()
	var context:={"campaign_cursor":state.campaign_cursor,"station_id":state.station_id,
		"rank":state.rank,"reputation":state.reputation.duplicate(true),"client_faction":faction}
	var choices:={"kind_index":kind_index,"difficulty_index":0,
		"destination_station_id":state.station_id if kind_index==4 else 76,"cargo_description_index":0}
	if not offer.configure(bindings,cat,context,choices) or not owner.register_offer(id,offer):check(false,offer.error+owner.error);return false
	return true

func verify_deliveries(bindings: RefCounted,cat: RefCounted,original: RefCounted) -> void:
	var station: RefCounted=original.fork()
	if not station.open_contracts(bindings,cat):check(false,station.error);return
	var owner: RefCounted=station._contracts.fork()
	var inventory: RefCounted=station.equipment_owner()
	var initial: Dictionary=owner.snapshot()
	var base_cargo: Dictionary=inventory.snapshot().cargo
	var expected_credits:=0
	for id in 4:
		inventory=destination_fixture(inventory,79)
		if not prepare_offer(bindings,cat,owner,id,1):return
		inventory=owner.accept(id,inventory)
		if inventory==null:check(false,owner.error);return
		var accepted: Dictionary=owner.snapshot()
		expected_credits+=int(accepted.mission.reward)+int(accepted.mission.bonus)
		check(owner.active_mission_for(79).is_empty() and owner.active_mission_for(76)==accepted.mission and owner.active_mission_for(999).is_empty(),"The side mission became active outside its target")
		check(owner.poll_station(inventory) and owner.snapshot()==accepted,"A delivery settled at its origin")
		check(not owner.poll_station(null) and owner.snapshot()==accepted,"An absent destination inventory changed the contract")
		var arrived:=destination_fixture(inventory,76)
		if not owner.poll_station(arrived):check(false,owner.error);return
		var pending: Dictionary=owner.snapshot()
		check(pending.pending_result.completed and pending.pending_result.acknowledgement_required and pending.completed_side_missions==id and pending.credits==accepted.credits,"Opening a result paid or counted it before acknowledgement")
		check(pending.reputation.axes==[accepted.reputation.axes[0],maxi(-100,accepted.reputation.axes[1]-5)],"The source client's reputation changed by the wrong amount")
		check(pending.progress.rank_score==accepted.progress.rank_score and arrived.snapshot().cargo==inventory.snapshot().cargo,"A result opening changed score or unloaded cargo early")
		check(owner.poll_station(arrived) and owner.snapshot()==pending,"Repeated polling changed reputation twice")
		check(owner.active_mission_for(76).is_empty() and owner.preview(id,arrived).is_empty(),"A completed result remained active or accepted another job")
		check(owner.acknowledge_delivery_result(inventory)==null and owner.snapshot()==pending,"A result was acknowledged with the origin inventory")
		var changed: RefCounted=arrived.fork()
		var hold: Dictionary=changed.snapshot().cargo
		hold.entries[-1].quantity-=1;hold.used-=1;hold.free_space+=1
		check(changed.retain_flight_cargo(hold),changed.error)
		check(owner.acknowledge_delivery_result(changed)==null and owner.snapshot()==pending,"An altered cargo hold received the prepared payment")
		var branch: RefCounted=owner.fork()
		var completed: RefCounted=branch.acknowledge_delivery_result(arrived)
		if completed==null:check(false,branch.error);return
		check(owner.snapshot()==pending and arrived.snapshot().cargo==inventory.snapshot().cargo,"A prospective result mutated the live owner or hold")
		owner=branch;inventory=completed
		var settled: Dictionary=owner.snapshot()
		check(settled.completed_side_missions==id+1 and settled.credits==expected_credits,"The delivery was not counted and paid exactly once")
		check(settled.delivery_statistics=={"cargo":14*(id+1),"passengers":0} and inventory.snapshot().cargo==base_cargo,"Delivery removed ordinary cargo or counted the wrong quantity")
		check(settled.mission.is_empty() and settled.active_offer_id==-1 and settled.pending_result.is_empty() and settled.offers[id].consumed,"Settlement failed to retire the mission or revived its contact")
		check(settled.progress.other_score==initial.progress.other_score+2*(id+1) and settled.progress.rank_score==initial.progress.rank_score+2*(id+1),"Completed jobs did not contribute their original rank weight")
		check(settled.campaign_cursor==13 and settled.progress.campaign_cursor==13,"A side mission advanced the pending story itself")
		check(owner.acknowledge_delivery_result(inventory)==null and owner.poll_station(inventory) and owner.snapshot()==settled,"Repeated acknowledgement or station polling duplicated a paid delivery")
	check(original.snapshot().completed_side_missions==0 and not original.snapshot().has("contracts"),"Detached settlement changed the original campaign")
	# The generated combat jobs are not station-delivery objectives.
	for kind in [2,3,4]:
		var other: RefCounted=station._contracts.fork()
		if not prepare_offer(bindings,cat,other,10,kind):return
		var equipped: RefCounted=other.accept(10,station.equipment_owner())
		var before: Dictionary=other.snapshot()
		var target:=destination_fixture(equipped,int(before.mission.station_id))
		check(other.poll_station(target) and other.snapshot()==before,"Docking completed an unsupported combat objective")

func verify_passenger_delivery(bindings: RefCounted,cat: RefCounted,original: RefCounted) -> void:
	var station:=cabin_fixture(bindings,cat,original)
	if station==null or not station.open_contracts(bindings,cat):check(false,"Passenger fixture could not open contracts");return
	var owner: RefCounted=station._contracts.fork()
	if not prepare_offer(bindings,cat,owner,0,0):return
	var inventory: RefCounted=owner.accept(0,station.equipment_owner())
	if inventory==null:check(false,owner.error);return
	var hold: Dictionary=inventory.snapshot().cargo
	check(owner.active_mission_for(76).is_empty(),"Passenger delivery incorrectly became the active flight mission")
	var arrived:=destination_fixture(inventory,76)
	check(owner.poll_station(arrived) and owner.snapshot().passengers==3,"Passenger arrival unloaded before acknowledgement")
	var result: RefCounted=owner.acknowledge_delivery_result(arrived)
	check(result!=null,owner.error)
	if result==null:return
	var state: Dictionary=owner.snapshot()
	check(state.passengers==0 and state.completed_side_missions==1 and state.delivery_statistics=={"cargo":0,"passengers":3} and result.snapshot().cargo==hold,"Passenger settlement changed cargo or failed to unload/count its passengers")

func verify_unmarked_delivery(bindings: RefCounted,cat: RefCounted,original: RefCounted) -> void:
	var station: RefCounted=original.fork()
	var inventory: RefCounted=station._equipment
	var hold: Dictionary=inventory.snapshot().cargo
	hold.entries.append({"item_id":116,"quantity":1});hold.used+=1;hold.free_space-=1
	if not inventory.retain_flight_cargo(hold):check(false,inventory.error);return
	station._state.cargo=hold.duplicate(true)
	if not station.open_contracts(bindings,cat):check(false,station.error);return
	var owner: RefCounted=station._contracts.fork()
	if not prepare_offer(bindings,cat,owner,0,1):return
	inventory=owner.accept(0,station.equipment_owner())
	if inventory==null:check(false,owner.error);return
	var arrived:=destination_fixture(inventory,76)
	var merged: Dictionary=arrived.snapshot().cargo
	check(merged.entries[-1]=={"item_id":116,"quantity":15},"The merge fixture lost its ordinary cargo marker")
	check(owner.poll_station(arrived),owner.error)
	var result: RefCounted=owner.acknowledge_delivery_result(arrived)
	check(result!=null and result.snapshot().cargo==merged and owner.snapshot().delivery_statistics.cargo==14,"Delivery removed the whole unmarked merged cargo row")

func verify_result_limits(bindings: RefCounted) -> void:
	var rules: Dictionary=bindings.early_contracts.delivery_results
	check(Contracts.credit_balance(25,-40,rules)==0 and Contracts.credit_balance(25,40,rules)==65,"Credit arithmetic failed its signed addition or zero clamp")
	check(Contracts.credit_balance(2147483640,20,rules)==0 and Contracts.credit_balance(15,1000000001,rules)==15,"Credit arithmetic invented a wallet cap or ignored the source delta bound")
	var altered:=rules.duplicate(true);altered.completion_rank_weight=10
	check(not Delivery.parameters(altered),"Modified completion rewards were accepted as source declarations")

func verify_result_reputation(bindings: RefCounted,cat: RefCounted,original: RefCounted) -> void:
	for difficulty in [0.5,1.499,1.5]:
		var station: RefCounted=original.fork()
		if not station.open_contracts(bindings,cat,difficulty):check(false,station.error);return
		for faction in [0,1,2,3,7]:
			var owner: RefCounted=station._contracts.fork()
			# Explicit near-cap standing and fee funds, not earned career changes.
			owner._state.reputation.axes=[98,-98]
			owner._state.progress.reputation=owner._state.reputation.duplicate(true)
			owner._state.credits=10000
			if not prepare_offer(bindings,cat,owner,0,1,faction):return
			var inventory: RefCounted=owner.accept(0,station.equipment_owner())
			if inventory==null:check(false,owner.error);return
			var expected:=[98,-98]
			var delta:=10 if difficulty==1.5 else 5
			match faction:
				0:expected[0]=100
				1:expected[0]-=delta
				2:expected[1]+=delta
				3:expected[1]=-100
			check(owner.poll_station(destination_fixture(inventory,76)) and owner.snapshot().reputation.axes==expected,"Result reputation changed the wrong axis/sign, hard-mode multiplier or cap")
