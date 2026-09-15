extends "res://tests/gate_environment.gd"
## Independent transition and pool vectors. These declarations do not earn travel.
const Arrival=preload("res://src/content/gate_arrival_definitions.gd")
const PlayerCache=preload("res://src/simulation/flight_player_cache.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify_arrival(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Gate arrival rules: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_arrival(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var request:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"from_station_id":95,"destination_station_id":70}
	if not Arrival.available(bindings):
		check(Arrival.packet(bindings,cat,request).is_empty(),"Older bindings inferred ordinary gate arrival")
		return
	var expected:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":18,"from_station_id":95,"from_system_id":19,"station_id":70,"system_id":14,"source_state":2,"world_type":3,"audio_selector":1}
	check(Arrival.packet(bindings,cat,request)==expected,"Gate packet changed its source world and selected destination")
	check(Arrival.packet_matches(bindings,cat,expected),"The canonical ordinary arrival was rejected")
	for id in [70,71,72,73,74]:
		var choice:=request.duplicate();choice.destination_station_id=id
		check(Arrival.packet(bindings,cat,choice).get("station_id")==id,"Supported Magnetar destination was lost")
	for id in [-1,56,95,96,98,1000]:
		var choice:=request.duplicate();choice.destination_station_id=id
		check(Arrival.packet(bindings,cat,choice).is_empty(),"Unavailable or local destination bypassed the gate boundary")
	for change in [{"from_station_id":98},{"destination_station_id":70.5},{"binding_id":"wrong"},{"extra":true}]:
		var choice:=request.duplicate();choice.merge(change,true)
		check(Arrival.packet(bindings,cat,choice).is_empty(),"Malformed gate request reached destination construction")
	for change in [{"from_system_id":14},{"system_id":19},{"campaign_cursor":17},{"audio_selector":0},{"source_state":1},{"campaign_cursor":18.0},{"world_type":3.0}]:
		var bad:=expected.duplicate();bad.merge(change,true)
		check(not Arrival.packet_matches(bindings,cat,bad),"Altered arrival semantics were accepted")
	var planet_type: int=cat.tables.stations[71].planet_type
	cat.tables.stations[71].planet_type=0
	check(Arrival.packet(bindings,cat,request).is_empty(),"A changed member of the destination system escaped catalogue validation")
	cat.tables.stations[71].planet_type=planet_type
	var origin:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"ship_id":0,"station_id":95,"system_id":19,"equipment_ids":[81,86]}
	var destination:=origin.duplicate(true);destination.station_id=70;destination.system_id=14
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,
		"campaign_cursor":18,"equipment_ids":[81,86],"vitals":{"hull":43,"armor":72,"shield":9.875},"gamma":45.5}
	var cached:=destination.duplicate(true);cached.campaign_cursor=18;cached.values={"hull":43,"armor":72,"shield":9,"gamma":45}
	check(PlayerCache.capture_gate_arrival(bindings.mido_travel,origin,destination,player)==cached,"Gate capture refilled or lost a current pool")
	check(PlayerCache.capture_local_arrival(bindings.mido_travel,origin,destination,player).is_empty(),"Local cache capture allowed a cross-system relocation")
	for change in [{"station_id":71},{"system_id":14},{"ship_id":1},{"equipment_ids":[81]}]:
		var bad:=origin.duplicate(true);bad.merge(change,true)
		check(PlayerCache.capture_gate_arrival(bindings.mido_travel,bad,destination,player).is_empty(),"Unrelated departure inventory supplied gate pools")
	var dead:=player.duplicate(true);dead.vitals.hull=0
	check(PlayerCache.capture_gate_arrival(bindings.mido_travel,origin,destination,dead).is_empty(),"Dead player crossed the arrival boundary")
	for value in [null,{}, {"jumpgates_used":-1},{"jumpgates_used":1.5},{"jumpgates_used":2147483648},{"jumpgates_used":0,"other":0}]:
		check(not Arrival.valid_statistics(value),"Malformed retained travel statistics were accepted")
	for count in [0,1,2147483647]:check(Arrival.valid_statistics({"jumpgates_used":count}),"Valid earned gate count was rejected")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in Arrival.SPANS:
		var bad:=bindings.mido_travel.duplicate(true);bad.provenance.erase(key)
		check(not Travel.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing arrival proof was accepted: "+key)
