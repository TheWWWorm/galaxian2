extends "res://tests/mido_continuation.gd"
## Continue the inherited native station visits through the original eight-line
## lounge introduction. No contract is accepted, completed or rewarded here.
var return_verified:=false

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	check(return_verified,"The station visit never reached the contract requirement")
	print("Mido Kernstal return: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func after_yrdal_visit(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	if bindings.mido_travel.get("return_visit",{}).is_empty():
		check(station.prepare_departure(bindings,cat).is_empty(),"Earlier bindings enabled the Kernstal return")
		return_verified=true;return
	var visit:=verify_visit(bindings,cat,library,station)
	if visit==null:return
	var finished: Dictionary=visit.snapshot()
	check(finished.mission.completed_contract_target==4 and finished.completed_side_missions==0,"The original four-contract requirement changed")
	check(visit.prepare_departure(bindings,cat).is_empty() and finished.phase=="contracts_required","The pending contract requirement was bypassed")
	return_verified=true
	after_contract_intro(bindings,cat,library,visit)

func after_contract_intro(_bindings: RefCounted,_cat: RefCounted,_library: RefCounted,_station: RefCounted) -> void:
	pass
