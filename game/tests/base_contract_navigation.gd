extends "res://tests/lounge_contacts.gd"
## Explicit source vectors and seeded populations; these are quotations and
## retained station selections, not proof of freely playable inter-system jobs.
const Navigation=preload("res://src/simulation/contract_navigation.gd")
const NavigationRules=preload("res://src/content/base_contract_navigation_definitions.gd")
const Cache=preload("res://src/simulation/lounge_cache.gd")
const SETTINGS={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,
	"energy_availability_percent":0,"missile_availability_percent":0}
const ELIGIBLE=[16,17,18,19,20,21,23,24,25,26,28,31,32,35,36,37,39,41,42,43,44,45,46,49,57,59,61,62,63,64,67,68,69,71,72,73,84,87,88,89,96,97,99]

func verify(args: PackedStringArray):
	super.verify(args)
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	if not NavigationRules.available(bindings):
		check(Navigation.initial_availability(bindings,cat,false).is_empty(),"Older bindings inferred available systems")
		return
	var flags:=Navigation.initial_availability(bindings,cat,false)
	var expected:=[]
	for id in 34:expected.append(id in [2,3,4,5,7,8,9,11,12,13,14,15,16,17,18,19,20,26])
	check(flags==expected,"System availability disagrees with original catalogue flags")
	expected[25]=true
	check(Navigation.initial_availability(bindings,cat,true)==expected,"Owned Valkyrie did not add only its initial available system")
	var rules: Dictionary=bindings.early_contracts.base_navigation
	for id in cat.tables.stations.size():check(Navigation.eligible(rules,cat,19,flags,id)==(id in ELIGIBLE),"Destination eligibility differs for station%d"%id)
	check(Navigation.eligible(rules,cat,15,flags,75) and not Navigation.eligible(rules,cat,19,flags,75),"Mido's missing jump link was ignored")
	for vector in [[2,395.40093994140625],[19,0.0],[15,739.0065307617188],[3,321.0039367675781],[9,334.5543212890625]]:
		check(Navigation.distance(rules,cat,19,vector[0])==vector[1],"Contract distance lost source depth truncation or float32 order")
	var context:={"campaign_cursor":15,"station_id":98,"rank":0,"reputation":{"axes":[0,0],"override":-1},"system_availability":flags}
	verify_alioth_quotes(bindings,cat,context)
	verify_alioth_draws(bindings,cat,lib,context)
	verify_alioth_populations(bindings,cat,lib,context)
	verify_alioth_cache(bindings,cat,lib)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in NavigationRules.SPANS:
		var bad: Dictionary=bindings.early_contracts.duplicate(true);bad.provenance.erase(key)
		check(not Definitions.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.mido_travel).is_empty(),"Missing navigation proof was accepted: "+key)

func verify_alioth_quotes(bindings: RefCounted,cat: RefCounted,context: Dictionary):
	var offer:=Offer.new();var origin:=context.duplicate(true);origin.client_faction=0
	var choice:={"kind_index":1,"difficulty_index":0,"destination_station_id":31,"cargo_description_index":0}
	for vector in [[31,2,2750],[96,19,2050],[16,3,2550],[46,9,2600]]:
		choice.destination_station_id=vector[0]
		if not offer.configure(bindings,cat,origin,choice):check(false,offer.error);return
		var state: Dictionary=offer.snapshot()
		check(state.mission.reward==vector[2] and state.mission.system_id==vector[1] and state.mission.bonus==0,"Alioth courier quote did not retain source distance and reward rounding")
		check(Offer.new().restore(bindings,cat,state),"A source-distance offer could not be restored")
	var retained:=offer.snapshot()
	for destination in [98,75,10,52,110,134]:
		choice.destination_station_id=destination
		check(not offer.configure(bindings,cat,origin,choice) and offer.snapshot()==retained,"An excluded or unavailable destination replaced a retained quote")
	choice.kind_index=4;choice.destination_station_id=98
	check(offer.configure(bindings,cat,origin,choice) and offer.snapshot().mission.station_id==98,"The local challenge lost its explicit origin override")
	retained=offer.snapshot()
	for field in ["system_availability","campaign_cursor"]:
		var invalid:=origin.duplicate(true)
		if field=="campaign_cursor":invalid[field]=16
		else:invalid.erase(field)
		check(not offer.configure(bindings,cat,invalid,choice) and offer.snapshot()==retained,"An unsupported origin changed a quote")

func drawn_alioth(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary,draws: Array) -> RefCounted:
	var owner:=setup_owner(bindings,lib,draws)
	owner._navigation=bindings.early_contracts.base_navigation.duplicate(true)
	owner._catalogues=cat;owner._context=context.duplicate(true)
	owner._stations=cat.tables.systems[19].station_ids.duplicate()
	return owner

func verify_alioth_draws(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary):
	# First retains excluded Alioth. Local index3 is also Alioth, then the global
	# branch tries inaccessible Mido before selecting Behen's station31.
	var owner:=drawn_alioth(bindings,cat,lib,context,[[100,19],[100,20],[100,39],[5,3],[100,20],[100,40],[135,75],[100,20],[100,40],[135,31]])
	check(owner._destination()==31,"General destination retries retained an excluded candidate")
	draws_finished(owner,"Alioth local/global retries")
	var origin:=context.duplicate(true);origin.client_faction=0
	owner=drawn_alioth(bindings,cat,lib,context,[[100,20],[100,39],[5,1],[15,2],[5,1],[2,0],[7,6]])
	var offer: Dictionary=owner._offer(bindings,cat,origin)
	check(not offer.is_empty() and offer.mission.station_id==96 and offer.mission.source_parameter==6 and offer.mission.difficulty==1,"Alioth inherited the Mido destination override")
	draws_finished(owner,"Alioth quotation order")
	owner=drawn_alioth(bindings,cat,lib,context,[[100,20],[100,39],[5,4],[15,4],[5,4],[2,1]])
	offer=owner._offer(bindings,cat,origin)
	check(not offer.is_empty() and offer.mission.station_id==98 and offer.mission.kind==12 and offer.mission.difficulty==2,"Alioth challenge skipped the discarded destination draw")
	draws_finished(owner,"Alioth local challenge")
	owner=drawn_alioth(bindings,cat,lib,context,[]);owner._draws=Contacts.MAX_DRAWS
	check(owner._destination()==-1 and not owner.error.is_empty(),"Destination exhaustion did not stop safely")

func verify_alioth_populations(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary):
	var history:=[];history.resize(15);history.fill(false)
	var kinds:={};var destinations:={};var generator:=Contacts.new()
	for seed in 64:
		var random:=Random.new();random.seed_from(seed)
		if not generator.prepare(bindings,cat,lib,context,random.snapshot(),history):check(false,generator.error);return
		var state:=generator.snapshot()
		check(state.contacts.size() in [3,4] and state.context.station_id==98,"Alioth lost its original early population size")
		check(Contacts.new().restore(bindings,cat,lib,state),"Alioth contacts could not restore their explicit source inputs")
		for contact in state.contacts:
			if contact.offer.is_empty():continue
			var mission: Dictionary=contact.offer.mission;kinds[mission.kind]=true;destinations[mission.system_id]=true
			check(mission.station_id==98 if mission.kind==12 else mission.station_id in ELIGIBLE,"A generated Alioth job escaped its destination rules")
	check(kinds.size()==5 and destinations.size()>5,"Seeded Alioth contacts did not exercise all early types and multiple systems")
	var retained: Dictionary=generator.snapshot();var invalid:=context.duplicate(true);invalid.system_availability.fill(false)
	var random:=Random.new();random.seed_from(0)
	check(not generator.prepare(bindings,cat,lib,invalid,random.snapshot(),history) and generator.snapshot()==retained,"No available destination replaced the retained population")
	print("Alioth quotation fixtures:64 populations; ",destinations.size()," destination systems")

func verify_alioth_cache(bindings: RefCounted,cat: RefCounted,lib: RefCounted):
	var cache:=Cache.new();check(cache.configure(bindings),cache.error)
	var random:=Random.new();random.seed_from(917)
	var context:={"campaign_cursor":1,"station_id":78,"rank":0,"reputation":{"axes":[30,0],"override":-1}}
	if not cache.select_location(bindings,cat,lib,context,SETTINGS,random.snapshot(),null):check(false,cache.error);return
	var mido: Dictionary=cache.location(78);var before: Dictionary=cache.snapshot()
	context.campaign_cursor=15;context.station_id=98
	check(not cache.select_location(bindings,cat,lib,context,SETTINGS,before.random,1789423200) and cache.snapshot()==before,"Missing Alioth ship pricing changed the cache")
	var settings:=SETTINGS.duplicate(true);settings.ship_price_percent=0
	check(not cache.select_location(bindings,cat,lib,context,settings,before.random,null) and cache.snapshot()==before,"Missing Alioth time seed changed the cache")
	if not cache.select_location(bindings,cat,lib,context,settings,before.random,1789423200):check(false,cache.error);return
	var after:=cache.snapshot();var alioth:=cache.location(98)
	check(after.locations.map(func(row):return row.station_id)==[78,98] and cache.location(78)==mido,"Alioth erased retained Mido contacts")
	check(alioth.stock.context.station_id==98 and alioth.population.context.station_id==98 and alioth.stock.random==alioth.population.initial_random,"Alioth did not generate stock before contacts")
	check(alioth.population.initial_history==before.history and after.history==alioth.population.history and after.random==alioth.population.random,"Alioth lost shared contact history or random state")
	check(after.system_availability==before.system_availability and alioth.population.context.system_availability==before.system_availability,"Arrival changed the career's available systems")
	check(cache.select_location(bindings,cat,lib,context,{},after.random,null) and cache.snapshot()==after,"A retained Alioth visit rerolled stock or contacts")
	var fork:=cache.fork();var retained: Dictionary=fork.snapshot()
	fork._state.system_availability[0]=true
	check(cache.snapshot()==after and retained==after,"Availability was shared between career forks")
