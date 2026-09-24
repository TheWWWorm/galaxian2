extends "res://tests/free_population.gd"
## Source-context component checks; no earned career or player save is created.
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Traffic=preload("res://src/content/free_traffic_definitions.gd")
const Lifecycle=preload("res://src/content/free_lifecycle_definitions.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Campaign visit population: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var context:=CONTEXT.duplicate(true)
	context.system_id=11;context.station_id=56;context.mission_kind=156;context.mission_story=true;context.mission_completed=false
	if not Campaign.Visit.available(bindings):
		check(not Population.new().configure_free(bindings,cat,context,99),"Earlier bindings inferred the campaign world")
		check(not Campaign.supported(bindings.mido_travel,19),"Earlier bindings inferred post-visit progress")
		return
	check(Campaign.mission(bindings.mido_travel,19)=={"kind":156,"station_id":55,"reward":0,"bonus":0,"source_parameter":0},"The next source mission changed")
	var gates=load("res://src/content/gate_arrival_definitions.gd")
	var request:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"from_station_id":95,"destination_station_id":55}
	check(gates.packet(bindings,cat,request).is_empty(),"A single gate jump skipped Weymire on the original Union route")
	request.from_station_id=70
	check(not gates.packet(bindings,cat,request).is_empty(),"The original Magnetar–Union link is unavailable")
	for cursor in [17,25 if Campaign.chapter_available(bindings.mido_travel) else 20,18.5]:check(not Campaign.supported(bindings.mido_travel,cursor),"An unsupported campaign stage was enabled")
	for seconds in [0,999,1789100000]:
		for seed in [1,98765,2147483647]:
			var population:=Population.new()
			if not population.configure_free(bindings,cat,context,seconds):check(false,population.error);return
			var before:={"state":seed};var actual:=population.generate(before)
			if actual.is_empty():check(false,population.error);return
			var random:=Random.new();random.restore(before)
			var enemy:=8 if random.next_int(100)<75 else 1
			check(actual.actor_count==0 and actual.groups.values().all(func(count):return count==0),"The visit spawned ambient ships")
			check(actual.mission_kind==156 and actual.system_faction==0 and actual.security==2 and not actual.hostile_selected and actual.hostile_faction==enemy,"The visit changed Union's selected-mission population")
			check(actual.incoming_random_state==before and actual.before_actors_random_state==random.snapshot() and not actual.has("unix_seconds"),"The visit reseeded or changed the source random draw order")
			var factory:=Factory.new()
			if not factory.configure_free_factory(bindings,cat,0,[81,86],context,seconds):check(false,factory.error);return
			var packet:=factory.generate(before)
			if packet.is_empty():check(false,factory.error);return
			check(packet.actors.is_empty() and packet.population==actual and packet.random_state==random.snapshot(),"Empty visit construction consumed an actor draw")
			check(not Traffic.population(bindings,packet,context.rank,context.difficulty).is_empty(),"The empty visit lacks supported combat")
			check(not Lifecycle.population(bindings,packet).is_empty(),"The empty visit lacks supported world lifecycle")
			var world:=World.new()
			if not world.configure_free_factory(bindings,cat,0,[81,86],context,seconds,{"companions_empty":true,"location_match":false,"special_placement":false}):check(false,world.error);return
			var assembled:=world.generate(before)
			if assembled.is_empty():check(false,world.error);return
			check(assembled.npc_construction==packet and assembled.random_state==random.snapshot(),"Visit weapon initialization changed an empty actor stream")
	var invalid:=context.duplicate(true);invalid.mission_kind=-1
	check(not Population.new().configure_free(bindings,cat,invalid,0),"An inconsistent selected visit entered the population")
	invalid=context.duplicate(true);invalid.station_id=55
	check(not Population.new().configure_free(bindings,cat,invalid,0),"Kappa used Suttnar's selected mission")
	var ordinary:=CONTEXT.duplicate(true);ordinary.campaign_cursor=19;ordinary.system_id=11;ordinary.station_id=56
	var population:=Population.new()
	if not population.configure_free(bindings,cat,ordinary,2):check(false,population.error);return
	var after:=population.generate({"state":98765})
	check(after.actor_count>=2 and after.has("unix_seconds") and after.security==2,"A later ordinary flight retained the old visit's empty population")
