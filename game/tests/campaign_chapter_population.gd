extends "res://tests/campaign_visit_population.gd"
const Navigation=preload("res://src/content/free_navigation_definitions.gd")
const Worlds=preload("res://src/content/ordinary_world_definitions.gd")

func verify(args: PackedStringArray) -> void:
	super.verify(args)
	if failures:return
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	if not Campaign.chapter_available(bindings.mido_travel):
		for cursor in [20,21,22,23,24]:check(not Campaign.supported(bindings.mido_travel,cursor),"An older pack acquired a later chapter")
		for station in [10,35,36,37,38,39]:check(Worlds.location(bindings.mido_travel,station).is_empty(),"An older pack acquired an onward world")
		return
	for row in [[19,55,11,156],[20,55,11,189],[22,55,11,11],[23,10,6,11]]:
		var context:=CONTEXT.duplicate(true)
		context.campaign_cursor=row[0];context.station_id=row[1];context.system_id=row[2]
		context.mission_kind=row[3];context.mission_story=true;context.mission_completed=false
		var mission:=Campaign.mission(bindings.mido_travel,row[0])
		check(Campaign.empty_story(bindings.mido_travel,context) and Navigation.ordinary_departure_at(bindings,row[0],mission,row[1]),"The source-selected world lacks native composition")
		for seed in [1,98765]:
			var factory:=Factory.new()
			if not factory.configure_free_factory(bindings,cat,0,[81,86],context,1789100000):check(false,factory.error);return
			var packet:=factory.generate({"state":seed})
			if packet.is_empty():check(false,factory.error);return
			var random:=Random.new();random.restore({"state":seed});random.next_int(100)
			check(packet.actors.is_empty() and packet.population.mission_kind==row[3],"A selected story generated ordinary traffic")
			check(packet.random_state==random.snapshot() and not packet.population.has("unix_seconds"),"The empty story reseeded or changed its retained random stream")
			check(not Traffic.population(bindings,packet,context.rank,context.difficulty).is_empty() and not Lifecycle.population(bindings,packet).is_empty(),"Selected story lacks its shared empty combat/lifecycle")
		var incorrect:=context.duplicate(true);incorrect.mission_kind=-1;incorrect.mission_story=false;incorrect.mission_completed=true
		check(not Population.new().configure_free(bindings,cat,incorrect,0),"Selected story silently became ordinary traffic")
	var rescue:=Campaign.mission(bindings.mido_travel,21)
	check(Navigation.destination_supported(bindings,21,rescue,55) and not Navigation.ordinary_departure_at(bindings,21,rescue,55),"Kappa rescue must select its authored cast")
	check(Navigation.ordinary_departure_at(bindings,21,rescue,57),"Off-target fitting prevented ordinary travel to the rescue")
	check(not Navigation.destination_supported(bindings,24,Campaign.mission(bindings.mido_travel,24),48),"The unfinished Sahi encounter was exposed")
	for station in [10,35,36,37,38,39]:check(not Worlds.catalogue_location(bindings,cat,station).is_empty(),"The onward world differs from its actual catalogue")
	var ordinary=load("res://src/content/ordinary_flight_definitions.gd")
	for station in [55,35,10]:
		var expected: Array=bindings.mido_travel.kappa_return.arrival_briefing.events if station==10 else []
		check(ordinary.briefing(bindings,23,true,station).events==expected,"Deep Science briefing escaped its source-selected destination")
	var history=load("res://src/simulation/faction_reputation.gd").new()
	check(history.configure(bindings,21,[0,0,0,0],0.5) and history.snapshot().has("spawn_generations") and not history.snapshot().has("kappa_rescue"),"An ordinary four-ship population acquired scripted rescue accounting")
