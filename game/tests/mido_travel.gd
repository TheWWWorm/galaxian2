extends SceneTree
## Component checks from the earned tutorial inventory. Training release and the
## following mission are explicit component fixtures, not a campaign playthrough.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/mido_travel_definitions.gd")
const Travel=preload("res://src/simulation/local_travel.gd")
const Planets=preload("res://src/simulation/opening_planet_layout.gd")
const Scenario=preload("res://tests/fixtures/equipment_scenario.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Mido travel components: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):
		check(false,library.error+bindings.error+cat.error);return
	if bindings.mido_travel.is_empty():
		check(not Definitions.location_supported(bindings.mido_travel,79,15,11),"An earlier pack invented local travel")
		return
	var rules: Dictionary=bindings.mido_travel
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(rules,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Recovered travel declarations failed validation")
	for key in Definitions.VALUES:
		var bad:=rules.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed travel data accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Disconnected travel source accepted: "+key)
	check(rules.conversations[1].events.map(func(row):return int(row.voice_event_id))==[190,191,194,195,196,197,198,199,200,201,192,193],"Kernstal voices lost their independent table order")
	var scenario:=Scenario.new()
	var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,scenario.error);return
	var earned: Dictionary=equipment.snapshot()
	check(not equipment.apply_station_exchange(bindings,cat,9) and equipment.snapshot()==earned,"Unreleased tutorial inventory accepted the exchange")
	check(equipment.prepare_training_completion(bindings,cat),equipment.error)
	check(equipment.complete_training(earned.cargo),equipment.error)
	var released: Dictionary=equipment.snapshot()
	for cursor in [8,10]:
		check(not equipment.apply_station_exchange(bindings,cat,cursor) and equipment.snapshot()==released,"Exchange accepted the wrong station conversation")
	var travel:=Travel.new()
	var mission:={"kind":11,"station_id":79,"reward":0,"bonus":0,"source_parameter":0}
	check(not travel.configure(bindings,cat,equipment,10,mission),"Travel skipped the drill exchange")
	check(equipment.apply_station_exchange(bindings,cat,9),equipment.error)
	var exchanged: Dictionary=equipment.snapshot()
	check(exchanged.loadout.equipment_ids==[22,86,81,55],"The prototype was not exchanged in its compatible slot")
	var drill_price: Dictionary={}
	for row in exchanged.prices.installed:
		if row!=null and row.item_id==86:drill_price=row
	check(drill_price=={"item_id":86,"unit_price":3967},"The new drill inherited the removed prototype's positional price")
	for key in ["cargo","stock","credit_delta","transactions","protected_item_ids"]:
		check(exchanged[key]==released[key],"Exchange changed retained inventory: "+key)
	check(exchanged.prices.cargo==released.prices.cargo,"Exchange repriced retained cargo")
	for index in exchanged.loadout.slots.size():
		if exchanged.loadout.slots[index]!=null and exchanged.loadout.slots[index].item_id==86:continue
		check(exchanged.loadout.slots[index]==released.loadout.slots[index] and exchanged.prices.installed[index]==released.prices.installed[index],"Exchange changed another installed slot")
	check(not equipment.apply_station_exchange(bindings,cat,9) and equipment.snapshot()==exchanged,"Repeated exchange mutated inventory")
	check(not travel.configure(bindings,cat,equipment,9,mission),"Travel unlocked before cursor10")
	var wrong:=mission.duplicate();wrong.reward=1
	check(not travel.configure(bindings,cat,equipment,10,wrong),"Travel accepted a fabricated reward")
	check(travel.configure(bindings,cat,equipment,10,mission),travel.error)
	if travel.snapshot().is_empty():return
	check(travel.snapshot().acquisition_duration_ms==4000,"The installed scanner's duration was discarded")
	check(travel.snapshot().event_serial==0,"Local travel invented a sound before acquisition")
	var before:=travel.snapshot()
	check(not travel.sample_acquisition(151,79,79,true) and travel.snapshot()==before,"An oversized travel frame committed state")
	check(not travel.sample_acquisition(1,76,76,true) and travel.snapshot()==before,"An unsupported destination entered travel")
	check(not travel.sample_acquisition(1,78,78,true) and travel.snapshot()==before,"The current planet became a travel destination")
	check(travel.sample_acquisition(150,79,79,true,true) and travel.snapshot()==before,"Paused acquisition advanced")
	check(sample_for(travel,4000,79),travel.error)
	check(travel.snapshot().phase=="flight" and travel.snapshot().acquired_station_id==-1,"Planet acquisition completed at equality")
	check(travel.sample_acquisition(1,79,79,true),travel.error)
	check(travel.snapshot().phase=="launch" and travel.snapshot().events==[{"kind":"sound","source_id":26},{"kind":"sound","source_id":5}],"Autopilot acquisition did not enter the source launch sequence")
	check(travel.snapshot().event_serial==1,"Automatic acquisition split its ordered sound batch")
	before=travel.snapshot()
	check(travel.advance_launch(150,true) and travel.snapshot()==before,"Paused launch advanced")
	check(not travel.sample_acquisition(1,79,79,true) and travel.snapshot()==before,"Acquisition restarted an active launch")
	for index in 20:check(travel.advance_launch(150),travel.error)
	check(travel.snapshot().phase=="launch" and travel.prepare_arrival().is_empty(),"Planet travel completed at 3000ms equality")
	check(travel.advance_launch(1),travel.error)
	check(travel.snapshot().event_serial==1 and travel.snapshot().events.is_empty(),"Launch ticks replayed the source sound batch")
	var arrival:=travel.prepare_arrival()
	check(arrival.get("station_id")==79 and arrival.get("from_station_id")==78 and arrival.get("campaign_cursor")==10 and arrival.get("source_state")==2 and arrival.get("world_type")==3 and arrival.get("audio_selector")==1,"Arrival lost its destination, world or music selection, or advanced the mission")
	arrival.station_id=76
	check(travel.prepare_arrival().station_id==79,"A returned arrival packet changed its owner")
	check(equipment.snapshot()==exchanged,"Travel changed equipment or current location before destination preparation")
	var manual:=Travel.new();check(manual.configure(bindings,cat,equipment,10,mission),manual.error)
	check(sample_for(manual,4001,-1),manual.error)
	check(manual.snapshot().phase=="flight" and manual.snapshot().acquired_station_id==79,"Manual target acquisition launched without an action")
	check(manual.sample_acquisition(1,-1,-1,true),manual.error)
	check(not manual.launch_acquired(),"A lost planet target remained launchable")
	check(sample_for(manual,4001,-1),manual.error)
	var fork: RefCounted=manual.fork()
	check(fork.launch_acquired() and fork.snapshot().phase=="launch" and manual.snapshot().phase=="flight","Travel forks share launch state")
	check(fork.snapshot().event_serial==manual.snapshot().event_serial+1 and fork.snapshot().events==[{"kind":"sound","source_id":5}],"Manual launch reused its preceding acquisition sound batch")
	verify_planets()

func sample_for(travel: RefCounted, milliseconds: int, autopilot: int) -> bool:
	var remaining:=milliseconds
	while remaining>0:
		var step:=mini(150,remaining)
		if not travel.sample_acquisition(step,79,autopilot,true):return false
		remaining-=step
	return true

func verify_planets() -> void:
	var layout:=Planets.new()
	var kernstal:=layout.arrange(79,11,[75,76,77,78,79],false)
	check(not kernstal.is_empty(),layout.error)
	if kernstal.is_empty():return
	check(kernstal.selected_index==5 and kernstal.entries.size()==6,"Kernstal lost its Mido planet membership")
	# Independent scalar oracle for station79's LCG sequence, including the
	# consumed ordinary size followed by the type11 replacement draw.
	check(kernstal.entries[5].scale==0.581512451171875,"Kernstal near size lost its type-specific source draw")
	check(kernstal.random_state.state==126403623076768,"Kernstal placement changed the source RNG continuation")
	check(layout.arrange(79,11,[75,76,77,78,79],true).is_empty(),"Opening scale was applied to an unsupported initial planet")
	check(layout.arrange(79,10,[75,76,77,78,79],false).is_empty(),"Unverified planet placement became supported")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
