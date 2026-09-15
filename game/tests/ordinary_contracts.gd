extends "res://tests/ordinary_shopping.gd"
## Contract acceptance replays the earned opening and retained source contacts.
const DeliveryContracts=preload("res://src/content/ordinary_contracts_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify_contracts(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Ordinary contracts: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_contracts(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var checkpoint:=Checkpoint.new()
	var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_FREE_PLAY_STATION_SCENARIO"),bindings)
	if station==null:check(false,checkpoint.error);return
	var original: Dictionary=station.snapshot()
	var selected:=-1
	for id in original.contracts.offers:
		var quote: Dictionary=original.contracts.offers[id].offer
		var preview: Dictionary=station.contract_preview(id,bindings)
		print("Retained contact ",id," kind ",quote.mission.kind," destination ",quote.mission.station_id," difficulty ",quote.mission.difficulty," preview ",preview)
		if quote.mission.kind==0 and preview.get("can_accept",false):selected=id
		elif not DeliveryContracts.delivery_mission(bindings,quote.mission):check(preview.is_empty(),"Unsupported offer was enabled")
	if selected<0:check(false,"The retained Alioth lounge has no supported affordable courier; exercise an actual new location");return
	var offered: Dictionary=original.contracts.offers[selected].offer
	var terms: Dictionary=station.contract_preview(selected,bindings)
	check(not station.accept_contract(selected,false) and station.snapshot()==original,"Ordinary acceptance inferred absent imported capability")
	if not station.accept_contract(selected,false,bindings):check(false,station.error);return
	var accepted: Dictionary=station.snapshot()
	check(accepted.contracts.mission==offered.mission and accepted.contracts.accepted_contact.offer==offered,"Acceptance changed its generated terms")
	check(accepted.mission==original.mission and accepted.progress==original.progress and accepted.completed_side_missions==4,"Acceptance changed pending story or earned progress")
	check(accepted.contracts.credits==original.contracts.credits-int(terms.fee) and accepted.cargo.used==original.cargo.used+int(offered.requirements.cargo_tons),"Acceptance did not atomically charge and retain its cargo")
	check(not station.accept_contract(selected,true,bindings) and station.snapshot()==accepted,"A consumed contact accepted twice")
	check(station.poll_contract_result(bindings) and station.snapshot()==accepted,"Off-target station paid or changed a delivery")
	var owner:=Construction.new()
	check(owner.prepare_free(bindings,cat,station,4096,1789100000),owner.error)
	if failures:return
	var departure: Dictionary=owner.snapshot()
	check(departure.departure.mission==original.mission and departure.departure.free_context.side_mission==offered.mission,"Departure replaced pending story with the side job")
	check(departure.departure.free_context.side_missions_empty==false and departure.departure.free_context.mission_kind==-1,"Off-target courier activated its destination mission")
	check(station.snapshot()==accepted,"Detached contract construction changed retained station state")
