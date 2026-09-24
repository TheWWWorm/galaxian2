extends SceneTree
## Catalogue route vectors, graph distances and detached guidance. No flight,
## earned progress, system availability or visit history is manufactured here.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Navigation=preload("res://src/simulation/system_navigation.gd")
const Contracts=preload("res://src/simulation/contract_navigation.gd")
const Definitions=preload("res://src/content/free_navigation_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [2,3]:verify(args)
	else:check(false,"Expected content and binding paths")
	print("System navigation: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var owner:=Navigation.new()
	var flags:=Contracts.initial_availability(bindings,cat,false)
	if not Definitions.available(bindings):
		check(not owner.configure(bindings,cat,flags) and owner.snapshot().is_empty(),"Older bindings inferred route declarations")
		check(not Definitions.ordinary_departure_at(bindings,18,{"kind":156,"station_id":56,"reward":0,"bonus":0,"source_parameter":0},98),"Older bindings inferred free departure")
		return
	if not owner.configure(bindings,cat,flags):check(false,owner.error);return
	var retained:=owner.snapshot()
	verify_distances(owner,cat,flags)
	check(owner.route(19,2)==[19,8,2],"Equal-length Behen route lost catalogue link order")
	check(owner.route(19,11)==[19,9,11],"Equal-length Union route lost catalogue link order")
	check(owner.route(19,15).is_empty() and owner.route(15,19).is_empty(),"Mido acquired an absent inter-system route")
	check(owner.course(75,79).guidance=={"kind":"planet","station_id":79,"planet_index":4},"A missing gate blocked ordinary local navigation")
	check(owner.course(98,98).guidance=={"kind":"clear"},"Reaching a selected station retained its course")
	check(owner.course(98,95).guidance=={"kind":"planet","station_id":95,"planet_index":0},"Gome C lost its source planet index")
	var course:=owner.course(98,16)
	check(course.system_path==[19,3] and course.jump_count==1 and course.guidance=={"kind":"planet","station_id":95,"planet_index":0},"Alioth did not route through its actual gate station")
	check(course.from_station_id==98 and course.destination_station_id==16,"Planning replaced the destination with its gate")
	course=owner.course(95,16)
	check(course.guidance=={"kind":"gate","station_id":95,"environment_object_index":1},"At Gome C guidance did not select the original gate object")
	check(owner.course(95,56).system_path==[19,9,11],"Story destination was confused with contract destination exclusions")
	check(owner.course(98,30).destination_station_id==30,"Player navigation inherited contract-only exclusions")
	check(owner.course(98,105).is_empty(),"Unavailable Loma became a destination")
	for pair in [[-1,98],[98,135],[98,-1],[135,98]]:check(owner.course(pair[0],pair[1]).is_empty(),"Invalid station produced a course")
	for pair in [[-1,19],[19,34]]:check(owner.route(pair[0],pair[1]).is_empty(),"Invalid system produced a route")
	check(owner.snapshot()==retained,"Planning mutated retained availability or content identity")
	var invalid:=flags.duplicate();invalid[0]=1
	check(not owner.configure(bindings,cat,invalid) and owner.snapshot()==retained,"Malformed availability replaced valid navigation")
	check(not owner.configure(bindings,cat,[]) and owner.snapshot()==retained,"Absent availability replaced valid navigation")
	var alternate:=flags.duplicate();alternate[8]=false
	check(owner.configure(bindings,cat,alternate),owner.error)
	check(owner.route(19,2)==[19,9,2],"Unavailable intermediate system remained in the route")
	alternate.fill(false)
	check(owner.route(19,2)==[19,9,2],"Caller mutation changed retained availability")
	var expanded:=Contracts.initial_availability(bindings,cat,true)
	check(owner.configure(bindings,cat,expanded),owner.error)
	check(owner.route(19,25)==[19,9,11,25],"Explicit expansion availability lost its shortest route")
	verify_distances(owner,cat,expanded)
	var story:={"kind":156,"station_id":56,"reward":0,"bonus":0,"source_parameter":0}
	var suttnar_visit: bool=bindings.mido_travel.has("suttnar_visit")
	for station in 135:check(Definitions.ordinary_departure_at(bindings,18,story,station)==(station!=56 or suttnar_visit),"Pending story selection differs at station%d"%station)
	check(not Definitions.ordinary_departure_at(bindings,17,story,98),"Travel skipped the final Alioth acknowledgement")
	check(not Definitions.ordinary_departure_at(bindings,18,story,-1),"Unknown station was accepted for ordinary departure")
	story.reward=1
	check(not Definitions.ordinary_departure_at(bindings,18,story,98),"Changed story mission was accepted")
	if Definitions.Campaign.supported(bindings.mido_travel,27):
		var pending: Dictionary=Definitions.Campaign.mission(bindings.mido_travel,27)
		check(Definitions.ordinary_departure_at(bindings,27,pending,48),"Acknowledged Sahi return cannot depart at its retained cursor")
		check(Definitions.destination_supported(bindings,27,pending,45),"Pending Thynome visit blocked ordinary Weymire navigation")
		check(not Definitions.destination_supported(bindings,27,pending,int(pending.station_id)),"The unfinished Thynome station result became an ordinary destination")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in Definitions.SPANS:
		var broken: Dictionary=bindings.mido_travel.duplicate(true);broken.provenance.erase(key)
		check(not Travel.validate(broken,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing navigation proof was accepted: "+key)
	var broken: Dictionary=bindings.mido_travel.duplicate(true);broken.free_navigation.gate_station_field=5
	check(not Travel.parameters(broken),"Changed gate binding was accepted")
	broken=bindings.mido_travel.duplicate(true)
	var key:="free_navigation_gate_helpers"
	var alternate_source: bool=int(broken.conversations[0].events[0].text_id)==int(Travel.MAC_VALUES.conversations[0].events[0].text_id)
	var other: Dictionary=Definitions.SPANS if alternate_source else Definitions.MAC_SPANS
	broken.provenance[key].offset=int(bindings.arrival_staging.provenance.actor.offset)+int(other[key][0])
	check(not Travel.validate(broken,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Mixed-source route proof was accepted")

func verify_distances(owner: RefCounted,cat: RefCounted,flags: Array) -> void:
	# Independent all-pairs distance calculation checks optimality without
	# duplicating the queue and predecessor algorithm used by the native owner.
	var size: int=cat.tables.systems.size()
	var distance:=[]
	for origin in size:
		var row:=[];row.resize(size);row.fill(999);row[origin]=0
		for target in cat.tables.systems[origin].linked_system_ids:
			if flags[target]:row[target]=1
		distance.append(row)
	for via in size:
		for origin in size:
			for target in size:distance[origin][target]=mini(distance[origin][target],distance[origin][via]+distance[via][target])
	for origin in size:
		for target in size:
			var path: Array=owner.route(origin,target)
			check(path.size()-1==int(distance[origin][target]) if not path.is_empty() else distance[origin][target]==999,"Incorrect route length %d to %d"%[origin,target])
			if path.is_empty():continue
			check(path[0]==origin and path[-1]==target,"Route endpoints changed")
			for index in range(1,path.size()):check(flags[path[index]] and cat.tables.systems[path[index-1]].linked_system_ids.has(path[index]),"Route crossed an unavailable or unlinked system")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
