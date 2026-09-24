extends SceneTree
## Imported future content remains edition-local and bound to shared scenery.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const CAPABILITIES=["post_probe_visits","void_access","void_crystals","nehma_visit"]
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/binding/visual triples")
	for index in range(0,args.size()-2,3):verify(args[index],args[index+1])
	print("Post-probe bindings: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	var original: Dictionary=bindings.mido_travel.duplicate(true)
	if not original.has("post_probe_visits"):
		check(CAPABILITIES.all(func(key):return not original.has(key)),"An earlier binding invented a disconnected later declaration")
		return
	check(CAPABILITIES.all(func(key):return original.has(key)),"Use the complete post-probe source input")
	if failures:return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	check(validate(original,header,bindings).is_empty(),"The imported post-probe chain cannot reuse its source and scenery")
	var visits: Dictionary=original.post_probe_visits
	check(visits.missions["31"].completion.reward_credits==30000 and visits.missions["32"].completion.reward_credits==0 and original.void_crystals.final_next.debit_quantity==50,"Payment and the future crystal debit were confused")
	check(original.void_access.source.initial_station_id==91 and original.void_crystals.next_mission.station_id==30 and original.nehma_visit.next_mission.station_id==29,"The imported portal source or later targets changed")
	for key in CAPABILITIES:
		var changed:=original.duplicate(true);changed[key].scope="foreign"
		check(not validate(changed,header,bindings).is_empty(),"Unknown capability data was accepted: "+key)
	for key in ["dima_return","post_probe_visits","void_access","void_crystals"]:
		var changed:=original.duplicate(true);changed.erase(key)
		check(not Travel.parameters(changed),"A later declaration lost its prerequisite: "+key)
	var app_store: bool=Travel.Equal.equal_value(visits,Travel.PostProbe.VALUES)
	for pair in [["post_probe_visits",Travel.PostProbe.MAC_VALUES if app_store else Travel.PostProbe.VALUES],
		["void_crystals",Travel.VoidCrystals.MAC_VALUES if app_store else Travel.VoidCrystals.VALUES],
		["nehma_visit",Travel.Nehma.MAC_VALUES if app_store else Travel.Nehma.VALUES]]:
		var changed:=original.duplicate(true);changed[pair[0]]=pair[1].duplicate(true)
		check(not Travel.parameters(changed),"A declaration accepted another edition's text or source layout: "+pair[0])
	for key in ["ack_ack_advance","flight_briefing_start","map_warning_model","field_ore_direct","result34_voices"]:
		var changed:=original.duplicate(true);changed.provenance[key].offset+=1
		check(not validate(changed,header,bindings).is_empty(),"A shared or new source extent moved: "+key)
	var population: Dictionary=bindings.scenery_population.duplicate(true);population.count_base+=1
	check(not validate(original,header,bindings,population).is_empty(),"Void crystals accepted another shared field size")
	var resources: Dictionary=bindings.scenery_resources.duplicate(true);resources.fallback_item_id=163
	check(not validate(original,header,bindings,{},resources).is_empty(),"Void crystals accepted another shared ore identity")
	check(bindings.mido_travel==original,"Rejected declarations mutated the loaded binding")

func validate(data: Dictionary,header: Dictionary,bindings: RefCounted,population: Dictionary={},resources: Dictionary={}) -> String:
	return Travel.validate(data,int(header.source_executable_bytes),header.architecture,bindings.arrival_staging,
		bindings.station_entry,bindings.combat_training,
		bindings.scenery_population if population.is_empty() else population,
		bindings.scenery_resources if resources.is_empty() else resources)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
