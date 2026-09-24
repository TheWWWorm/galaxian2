extends "res://tests/lounge_contacts.gd"
## Isolated source vectors for post-unlock generation. These exercise no campaign
## completion, travel, accepted job or reward; actual arrival owns those actions.
const Ordinary=preload("res://src/content/ordinary_generation_definitions.gd")
const Navigation=preload("res://src/simulation/contract_navigation.gd")
const Cache=preload("res://src/simulation/lounge_cache.gd")
const Session=preload("res://src/simulation/contract_session.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Ordinary station generation: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var context:={"campaign_cursor":18,"station_id":98,"rank":0,"reputation":{"axes":[0,0],"override":-1},"system_availability":Navigation.initial_availability(bindings,cat,true)}
	if not Ordinary.available(bindings):
		context.difficulty=1.0
		var random:=Random.new();random.seed_from(0)
		var history:=[];history.resize(15);history.fill(false)
		check(not Contacts.new().prepare(bindings,cat,lib,context,random.snapshot(),history),"Earlier bindings invented ordinary contacts")
		return
	verify_persistent(bindings,lib)
	verify_ordinary_quotes(bindings,cat,context)
	verify_ordinary_draws(bindings,cat,lib,context)
	verify_ordinary_populations(bindings,cat,lib,context)
	verify_ordinary_cache(bindings,cat,lib,context)
	verify_campaign_locations(bindings,cat,lib,context)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for span in Ordinary.SPANS:
		var bad: Dictionary=bindings.early_contracts.duplicate(true);bad.provenance.erase(span)
		check(not Definitions.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.mido_travel).is_empty(),"Missing ordinary source extent accepted: "+span)
	var bad: Dictionary=bindings.early_contracts.duplicate(true);bad.ordinary_generation.offers.difficulty_draw_bound=2
	check(not Definitions.parameters(bad),"Ordinary difficulty was silently replaced by the opening rule")
	bad=bindings.early_contracts.duplicate(true)
	var key:="ordinary_offer_selection"
	var other: Dictionary=Ordinary.SPANS if bad.briefing_text_base==Definitions.MAC_VALUES.briefing_text_base else Ordinary.MAC_SPANS
	bad.provenance[key].offset=int(bindings.arrival_staging.provenance.actor.offset)+int(other[key][0])
	check(not Definitions.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.mido_travel).is_empty(),"Mixed-source ordinary offer proof was accepted")

func verify_persistent(bindings: RefCounted,lib: RefCounted):
	var rules: Dictionary=bindings.early_contracts.ordinary_generation.persistent
	var bytes: PackedByteArray=lib.read_resource(rules.resource,1024*1024)
	var records:=Contacts.decode_persistent_contacts(bytes,rules)
	check(records.size()==27,"The original persistent contact table was not fully decoded")
	check(not records.any(func(row):return row.fields[1] in [95,96,97,98,99]),"Augmenta needs persistent contact behavior before generation")
	check(records.any(func(row):return row.fields[1]==78),"The parser discarded existing authored contacts")
	for malformed in [PackedByteArray(),bytes.slice(0,bytes.size()-1),bytes+PackedByteArray([0])]:
		check(Contacts.decode_persistent_contacts(malformed,rules).is_empty(),"Malformed persistent contact data accepted")

func verify_ordinary_quotes(bindings: RefCounted,cat: RefCounted,context: Dictionary):
	var career:=context.duplicate(true);career.client_faction=0
	var quote:=Offer.new()
	# Independent arithmetic vectors at difficulties1/5/9, same-system distance,
	# rank0 and neutral reputation. Credit rounding is the source half-step rule.
	var rewards:={7:[1400,3000,4500],9:[2450,5100,7700],3:[4100,8500,12900],5:[4100,8500,12900],11:[1950,8150,17800]}
	for kind in 15:
		if kind==8:continue
		for index in 3:
			var choice:={"kind":kind,"difficulty_index":[0,4,8][index],"destination_station_id":98 if kind==12 else 96,"parameter_index":6 if kind==0 else 0,"quantity_index":3 if kind==2 else 0}
			if not quote.configure(bindings,cat,career,choice):check(false,quote.error);return
			var state:=quote.snapshot();var mission: Dictionary=state.mission
			var quantity: int=[14,52,90][index] if kind==0 else ([3,11,18][index] if kind==11 else ([2,6,9][index] if kind in [3,5] else (5 if kind==2 else 0)))
			var parameter: int=6 if kind==0 else (116 if kind==3 else (117 if kind==5 else 0))
			check(mission.kind==kind and mission.difficulty==choice.difficulty_index+1 and mission.quantity==quantity and mission.source_parameter==parameter,"Ordinary parameter vector differs: %d/%d"%[kind,index])
			check(mission.reward==rewards.get(kind,[2050,4250,6450])[index] and mission.bonus==0,"Ordinary reward vector differs: %d/%d got%d"%[kind,index,mission.reward])
			check(state.requirements.cargo_tons==(quantity if kind==0 else 0) and state.requirements.passenger_places==(quantity if kind==11 else 0),"A quoted source quantity invented cargo or cabin requirements")
			check(not Session.acceptance_supported(bindings.early_contracts,18,state),"An unsupported ordinary quote enabled acceptance")
			if preload("res://src/content/ordinary_contracts_definitions.gd").available(bindings):
				check(Session.acceptance_supported(bindings.early_contracts,18,state,bindings)==(kind in [0,11]),"Ordinary acceptance crossed its implemented delivery types")
			check(Offer.new().restore(bindings,cat,state),"Ordinary quote did not restore exactly")
	for item in [97,98]:
		var choice:={"kind":8,"difficulty_index":8,"destination_station_id":96,"parameter_index":item,"quantity_index":14}
		check(quote.configure(bindings,cat,career,choice),quote.error)
		if quote.snapshot().is_empty():return
		var mission: Dictionary=quote.snapshot().mission
		check(mission.source_parameter==item and mission.quantity==19 and mission.difficulty==(1 if item==97 else 2) and mission.reward==(1900 if item==97 else 7750) and mission.bonus==0,"Collection quote lost its item-defined difficulty or maximum-price reward")
	var choice:={"kind":0,"difficulty_index":8,"destination_station_id":96,"parameter_index":0,"quantity_index":0}
	career.reputation.axes=[50,0];career.rank=2
	check(quote.configure(bindings,cat,career,choice),quote.error)
	check(quote.snapshot().mission.reward==6500 and quote.snapshot().mission.bonus==3250,"Rank cube or faction bonus changed")
	var before:=quote.snapshot()
	for field in ["kind","difficulty_index","destination_station_id","parameter_index","quantity_index"]:
		var invalid:=choice.duplicate();invalid[field]=-1
		check(not quote.configure(bindings,cat,career,invalid) and quote.snapshot()==before,"Invalid choice mutated the retained quote: "+field)
	for kind in [0,11,14]:
		var invalid:=choice.duplicate();invalid.kind=kind;invalid.destination_station_id=98
		check(not quote.configure(bindings,cat,career,invalid),"A different-destination mission remained at its origin")
	for id in [115,116,117,131,164,175,217,218]:
		check(Offer.collection_item(bindings.early_contracts,cat,id).is_empty(),"A source-excluded collection item was accepted")
	var faction_career:=career.duplicate(true);faction_career.client_faction=1
	var faction_choice:=choice.duplicate();faction_choice.kind=13
	check(not quote.configure(bindings,cat,faction_career,faction_choice),"A faction-specific job used a destination belonging to another faction")
	var invalid:=career.duplicate(true);invalid.campaign_cursor=19
	check(quote.configure(bindings,cat,invalid,choice)==Campaign.supported(bindings.mido_travel,19),"Quotation crossed its explicit campaign capability")
	invalid.campaign_cursor=20
	check(not quote.configure(bindings,cat,invalid,choice),"Quotation exceeded its integrated campaign boundary")
	invalid.campaign_cursor=18.5
	check(not quote.configure(bindings,cat,invalid,choice),"A fractional campaign cursor entered the ordinary quotation scope")
	var old:={"context":{"campaign_cursor":15},"choices":{"kind_index":0}}
	check(not Session.acceptance_supported(bindings.early_contracts,18,old),"An earlier cached quote bypassed the current acceptance boundary")

func ordinary_owner(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary,draws: Array) -> RefCounted:
	var owner:=setup_owner(bindings,lib,draws)
	owner._ordinary=bindings.early_contracts.ordinary_generation.duplicate(true)
	owner._context=context.duplicate(true);owner._context.difficulty=1.0
	owner._catalogues=cat;owner._stations=cat.tables.systems[19].station_ids.duplicate()
	owner._navigation=bindings.early_contracts.base_navigation.duplicate(true)
	return owner

func verify_ordinary_draws(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary):
	context=context.duplicate(true);context.station_id=96
	var career:=context.duplicate(true);career.client_faction=0
	var owner:=ordinary_owner(bindings,cat,lib,context,[[100,0],[15,0],[100,99],[100,0],[5,2],[9,8],[7,6]])
	var quote: Dictionary=owner._offer(bindings,cat,career)
	check(not quote.is_empty() and quote.mission.kind==0 and quote.mission.quantity==90 and quote.mission.station_id==97,"The general history kind was overwritten or destination retry lost")
	draws_finished(owner,"ordinary courier")
	owner=ordinary_owner(bindings,cat,lib,context,[[100,0],[15,13],[100,99],[100,0],[5,2],[9,4]])
	quote=owner._offer(bindings,cat,career)
	check(not quote.is_empty() and quote.mission.kind==13 and quote.mission.station_id==97,"Faction destination failed to discard its first candidate")
	draws_finished(owner,"faction destination redraw")
	owner=ordinary_owner(bindings,cat,lib,context,[[100,0],[15,2],[9,8],[4,3]])
	quote=owner._offer(bindings,cat,career)
	check(not quote.is_empty() and quote.mission.quantity==5,"Random encounter quantity used the early difficulty draw")
	draws_finished(owner,"random quantity")
	var draws:=[]
	for ignored in 1000:draws.append([15,8])
	owner=ordinary_owner(bindings,cat,lib,context,draws)
	check(owner._history_kind(0)==8 and owner._history.count(true)==0,"Finite rejection did not retain the source's final excluded draw")
	draws_finished(owner,"finite history rejection")
	draws=[[100,0]]
	for ignored in 1000:draws.append([15,8])
	draws.append_array([[9,8],[cat.tables.items.size()-97,18],[cat.tables.items.size()-97,0],[15,14]])
	owner=ordinary_owner(bindings,cat,lib,context,draws)
	quote=owner._offer(bindings,cat,career)
	check(not quote.is_empty() and quote.mission.kind==8 and quote.mission.source_parameter==97 and quote.mission.quantity==19 and quote.mission.reward==1900,"Finite history fallback lost collection item rejection or quantity draws")
	draws_finished(owner,"collection after exhausted history")
	owner=ordinary_owner(bindings,cat,lib,context,[[15,8],[15,1],[15,2]])
	owner._history.fill(true);owner._history[8]=false
	check(owner._history_kind(0)==2 and owner._history.count(true)==1 and owner._history[2],"Fourteen used types did not reset before the next selection")
	draws_finished(owner,"ordinary history reset")
	# Role6 skips the Terran gender draw, then draws two names and a per-person
	# price after its own identity and portrait. Hard mode multiplies by seven.
	draws=[[100,99],[7,6],[100,99],[16,0],[16,0],[11,0],[11,0],[11,0],[11,0],[3,2],[16,1],[16,2],[16,3],[16,4],[1300,1299]]
	owner=ordinary_owner(bindings,cat,lib,context,draws);owner._context.difficulty=1.5
	var contact: Dictionary=owner._contact(0)
	check(contact.role==6 and contact.male and contact.roster.extra_names.size()==2 and contact.roster.price==41979,"Role6 identity, roster order or hard-mode price changed")
	draws_finished(owner,"role6 roster")
	owner=ordinary_owner(bindings,cat,lib,context,[[100,99],[7,5],[100,99],[100,99],[16,0],[16,0],[4,0],[4,0],[5,0],[7,0]])
	contact=owner._contact(0)
	check(contact.role==5 and not contact.male and not contact.has("offer"),"Role5 was collapsed into an early job or generated a premature offer")
	draws_finished(owner,"role5 identity")

func verify_ordinary_populations(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary):
	var kinds:={};var roles:={};var duplicate_seen:=false
	for station in [95,96,97,98,99]:
		for seed in 32:
			var career:=context.duplicate(true);career.station_id=station;career.difficulty=1.5 if seed%2 else 1.0
			var random:=Random.new();random.seed_from(seed)
			var history:=[];history.resize(15);history.fill(false)
			var generator:=Contacts.new()
			if not generator.prepare(bindings,cat,lib,career,random.snapshot(),history):check(false,generator.error);return
			var state:=generator.snapshot();var roster_count:=0
			check(state.contacts.size() in [3,4],"Zero authored contacts changed ordinary population size")
			for contact in state.contacts:
				roles[contact.role]=true
				if contact.role==6:roster_count+=1
				if contact.role==1 and contact.has("roster"):duplicate_seen=true
				if contact.role in [5,6]:check(contact.offer.is_empty(),"Additional contact roles received an upfront contract")
				if not contact.offer.is_empty():
					kinds[contact.offer.mission.kind]=true
					check(Offer.new().restore(bindings,cat,contact.offer),"Generated ordinary offer cannot be restored")
			check(roster_count<=1,"A second role6 survived population uniqueness")
			var restored:=Contacts.new()
			check(restored.restore(bindings,cat,lib,state) and restored.snapshot()==state,"Ordinary population lost its stream or terms on restoration")
			if seed==0:
				var bad:=state.duplicate(true);bad.context.difficulty=2.0
				check(not restored.restore(bindings,cat,lib,bad) and restored.snapshot()==state,"Unsupported difficulty changed a retained population")
	check(roles.has(5) and roles.has(6) and duplicate_seen,"Population fixtures missed the additional roles or duplicate-role branch")
	for kind in 15:
		if kind!=8:check(kinds.has(kind),"Seeded populations missed ordinary kind%d"%kind)

func verify_ordinary_cache(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary):
	var career:=context.duplicate(true);career.erase("system_availability")
	var settings:={"difficulty":1.0,"valkyrie_owned":true,"supernova_owned":true,"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
	var cache:=Cache.new();check(cache.configure(bindings),cache.error)
	var random:=Random.new();random.seed_from(8)
	var original:={}
	for station in [98,95,96,98,97,99,98]:
		career.station_id=station
		var before:=cache.snapshot();var hit: Dictionary=cache.location(station)
		if not cache.select_location(bindings,cat,lib,career,settings,random.snapshot(),1000):check(false,cache.error);return
		var state:=cache.snapshot();var entry:=cache.location(station)
		if original.is_empty():original=entry
		check(entry.stock.random==entry.population.initial_random,"Contacts did not follow stock in the shared stream")
		if not hit.is_empty():check(state.locations==before.locations and entry==hit,"A cache hit reordered or regenerated ordinary terms")
		check(state.locations.size()<=3 and state.current_station_id==station,"Ordinary selection exceeded the FIFO or lost the selected station")
		check(random.restore(state.random),random.error)
	check(cache.snapshot().locations.map(func(row):return row.station_id)==[97,99,98],"Ordinary cache stopped using insertion order")
	check(cache.location(98)!=original,"An evicted ordinary location retained its old generation")
	var before:=cache.snapshot();career.station_id=56
	if Campaign.Visit.available(bindings):
		check(cache.select_location(bindings,cat,lib,career,settings,random.snapshot(),1000) and cache.snapshot().current_station_id==56,"The supported visit cannot retain its actual station contents")
	else:check(not cache.select_location(bindings,cat,lib,career,settings,random.snapshot(),1000) and cache.snapshot()==before,"Unsupported story destination changed the cache")

func verify_campaign_locations(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary) -> void:
	if not Campaign.Visit.available(bindings):return
	var settings:={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
	for cursor in [18,19]:
		var cache:=Cache.new();check(cache.configure(bindings),cache.error)
		var random:=Random.new();random.seed_from(4096)
		for station in [55,56,57]:
			var career:=context.duplicate(true);career.campaign_cursor=cursor;career.station_id=station;career.erase("system_availability")
			if not cache.select_location(bindings,cat,lib,career,settings,random.snapshot(),1789100000):check(false,cache.error);return
			var entry:=cache.location(station)
			check(entry.population.context.campaign_cursor==cursor and entry.stock.context.station_id==station,"Union's three-station system lost its current generation context")
			var contacts:=Contacts.new()
			check(contacts.restore(bindings,cat,lib,entry.population) and contacts.snapshot()==entry.population,"Union's generated contacts cannot restore their original terms")
			for id in entry.offers:check(Offer.new().restore(bindings,cat,entry.offers[id].offer),"Union's original offer cannot be restored")
			check(random.restore(cache.snapshot().random),random.error)
