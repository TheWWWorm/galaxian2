extends SceneTree
## Source draw boundaries use explicit fixtures. Seeded populations exercise the
## imported names, portraits and quotations together, not a full campaign RNG trace.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Offer=preload("res://src/simulation/contract_offer.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Portrait=preload("res://src/presentation/portrait_compositor.gd")
const Definitions=preload("res://src/content/early_contract_definitions.gd")
var failures:=0
var checks:=0

class Draws extends RefCounted:
	var choices:=[]
	var wrong:=false
	func _init(values: Array):choices=values.duplicate(true)
	func next_int(bound: int) -> int:
		if choices.is_empty():wrong=true;return 0
		var pair: Array=choices.pop_front()
		if pair[0]!=bound or pair[1]<0 or pair[1]>=bound:wrong=true
		return int(pair[1])

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Early lounge contacts: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):
		check(false,lib.error+bindings.error+cat.error);return
	var context:={"campaign_cursor":13,"station_id":79,"rank":0,"reputation":{"axes":[30,0],"override":-1}}
	var generator:=Contacts.new();var random:=Random.new();random.seed_from(0)
	var history: Array=[];history.resize(15);history.fill(false)
	if not Contacts.available(bindings):
		check(not generator.prepare(bindings,cat,lib,context,random.snapshot(),history) and generator.snapshot().is_empty(),"Older bindings fabricated lounge inhabitants")
		return
	check(generator.prepare(bindings,cat,lib,context,random.snapshot(),history),generator.error)
	if generator.snapshot().is_empty():return
	verify_names(bindings,lib)
	verify_draw_boundaries(bindings,cat,lib,context)
	verify_seeded_populations(bindings,cat,lib,context)
	verify_retention(bindings,cat,lib,generator)
	verify_provenance(bindings,args[1])
	verify_portraits(bindings,lib,args[2])

func setup_owner(bindings: RefCounted,lib: RefCounted,choices: Array) -> RefCounted:
	var owner:=Contacts.new()
	owner._rules=bindings.early_contracts.generation.duplicate(true)
	owner._stations=[75,76,77,78,79]
	owner._rng=Draws.new(choices)
	owner._history.resize(15);owner._history.fill(false)
	for path in owner._rules.names.resources:owner._names.append(Contacts.decode_names(lib.read_resource(path,1024*1024)))
	return owner

func draws_finished(owner: RefCounted,label: String):
	check(owner.error.is_empty() and not owner._rng.wrong and owner._rng.choices.is_empty(),"Source random draw order differs: "+label)

func verify_names(bindings: RefCounted,lib: RefCounted):
	var expected:=[16,16,16,18,18,13,13,14,14,27,15,15,28]
	for index in expected.size():
		var bytes: PackedByteArray=lib.read_resource(bindings.early_contracts.generation.names.resources[index],1024*1024)
		check(Contacts.decode_names(bytes).size()==expected[index],"Original name table was not fully decoded")
		check(Contacts.decode_names(bytes.slice(0,bytes.size()-1)).is_empty(),"A truncated name table was accepted")
	var valid:=PackedByteArray([0,0,0,1,0,3,65,66,67])
	check(Contacts.decode_names(valid)==["ABC"],"Name lengths are not big endian")
	for bytes in [PackedByteArray(),PackedByteArray([0,0,0,0]),PackedByteArray([0,0,0,1,0,0]),valid+PackedByteArray([0])]:
		check(Contacts.decode_names(bytes).is_empty(),"Invalid or trailing name bytes were accepted")
	var owner:=setup_owner(bindings,lib,[[2,1],[2,0],[13,2],[16,3]])
	check(owner._name(3,true)==owner._names[5][2]+" "+owner._names[2][3],"Midorian names failed to choose both pools before either name")
	draws_finished(owner,"Midorian first/last pools")
	owner=setup_owner(bindings,lib,[[16,4],[16,5]])
	check(owner._name(0,false)==owner._names[1][4]+" "+owner._names[2][5],"Female Terran used the male first-name pool")
	draws_finished(owner,"female Terran name")
	for pair in [[5,9,27],[7,12,28]]:
		owner=setup_owner(bindings,lib,[[pair[2],2]])
		check(owner._name(pair[0],true)==owner._names[pair[1]][2],"A single-name species gained a surname")
		draws_finished(owner,"single-name species")

func verify_draw_boundaries(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary):
	# General helper first tries reserved 76, then reserved 79, then valid 77.
	# Its abandoned broad candidates still consume their source random draws.
	var owner:=setup_owner(bindings,lib,[[100,19],[5,1],[100,20],[100,39],[5,0],[5,4],[100,99],[100,40],[135,1],[5,2]])
	check(owner._destination()==77,"Reserved station escaped destination filtering")
	draws_finished(owner,"destination retries")
	owner=setup_owner(bindings,lib,[[2,1],[3,2],[5,4],[1,0]])
	check(owner._portrait(6,true)=={"status":"fixed","family":6,"parts":[1,2,4,0]} and owner._draws==4,"Missing Bobolan part failed to consume its zero-bound draw")
	draws_finished(owner,"zero-bound portrait part")
	var lcg:=Random.new();lcg.seed_from(12)
	owner._rng=lcg.fork();owner._draws=0
	check(owner._draw(0)==0 and lcg.next_bits(31)>=0 and owner._rng.snapshot()==lcg.snapshot(),"Zero-bound random selection changed the retained stream")
	for vector in [[3,true,[[4,0],[11,1],[11,2],[11,3],[11,4]],0],
		[3,true,[[4,3],[5,1],[5,2],[5,3],[5,4]],2],
		[0,false,[[4,1],[4,2],[5,3],[7,4]],10],
		[5,true,[[11,1],[11,2],[11,3],[11,4]],0]]:
		owner=setup_owner(bindings,lib,vector[2])
		check(owner._portrait(vector[0],vector[1]).family==vector[3],"Procedural portrait selected the wrong original family")
		draws_finished(owner,"portrait family")
	# First candidate 8 is excluded; second is already seen and clears the
	# fourteen-type history, the next chooses type2. Early override then picks
	# courier, same-station candidate77 retries to75, low difficulty and text6.
	owner=setup_owner(bindings,lib,[[100,0],[5,0],[4,2],[15,8],[15,1],[15,2],[5,1],[100,0],[5,0],[2,0],[7,6]])
	owner._history.fill(true);owner._history[8]=false
	var offer_context: Dictionary=context.duplicate(true);offer_context.station_id=77;offer_context.client_faction=3
	var offer: Dictionary=owner._offer(bindings,cat,offer_context)
	check(not offer.is_empty() and offer.mission.kind==0 and offer.mission.quantity==14 and offer.mission.station_id==75 and offer.mission.source_parameter==6,"Early override lost delivery retry or courier parameters")
	check(owner._history.count(true)==1 and owner._history[2],"Used mission types did not reset at fourteen")
	draws_finished(owner,"mission history and delivery override")
	# Non-major species must reject base type10 even though the early kind will
	# overwrite it. The local challenge always targets the contact station.
	owner=setup_owner(bindings,lib,[[100,0],[5,0],[4,0],[15,10],[15,4],[5,4],[2,1]])
	offer_context.client_faction=5
	offer=owner._offer(bindings,cat,offer_context)
	check(not offer.is_empty() and offer.mission.kind==12 and offer.mission.station_id==77 and offer.mission.difficulty==2 and not owner._history[10],"Non-major type filter or local challenge target changed")
	draws_finished(owner,"non-major mission filter")
	for faction in 4:
		var axis:=0 if faction<2 else 1
		var reputation:={"axes":[0,0],"override":-1}
		reputation.axes[axis]=-70 if faction%2==0 else 70
		check(not Contacts.is_hostile(reputation,faction,70),"Exactly seventy reputation was treated as hostile")
		reputation.axes[axis]+=-1 if faction%2==0 else 1
		check(Contacts.is_hostile(reputation,faction,70),"The faction hostility sign or strict threshold changed")

func verify_seeded_populations(bindings: RefCounted,cat: RefCounted,lib: RefCounted,context: Dictionary):
	var roles:={};var kinds:={};var counts:={};var empty_seen:=false;var enemy_seen:=false;var merchant_seen:=false
	for seed in 32:
		var random:=Random.new();random.seed_from(seed)
		var history: Array=[];history.resize(15);history.fill(false)
		var career:=context.duplicate(true)
		if seed%2:career.reputation.axes=[-71,-71]
		var generator:=Contacts.new()
		if not generator.prepare(bindings,cat,lib,career,random.snapshot(),history):check(false,generator.error);return
		var state:=generator.snapshot();counts[state.contacts.size()]=true
		var jobs:=0;var enemies:=[]
		for id in state.contacts.size():
			var contact: Dictionary=state.contacts[id];roles[contact.role]=true
			check(contact.contact_id==id and not contact.name.is_empty() and contact.role in [0,1,2,7],"Early generated contact identity is invalid")
			if contact.role==0:
				jobs+=1;kinds[contact.offer.mission.kind]=true
				var offer:=Offer.new()
				check(offer.restore(bindings,cat,contact.offer) and contact.source_auxiliary_amount>=0,offer.error)
			elif contact.role==7:enemies.append(contact.faction)
			elif contact.role==2:
				merchant_seen=true
				var trade: Dictionary=contact.trade
				var row: Dictionary=cat.tables.items[trade.item_id]
				check(not trade.item_id in [131,164,175,217,218] and row.arrays[0].is_empty() and row.arrays[2][13]!=0,"Merchant offered an excluded item")
				check(trade.quantity==1 if int(row.properties[1]) in [0,2,3] else trade.quantity>=5 and trade.quantity<=19,"Merchant quantity ignored its item category")
				check(trade.total_price>=0,"Merchant price is invalid")
			if contact.role!=0:check(contact.offer.is_empty(),"A non-contract contact retained an offer")
		if not enemies.is_empty():
			enemy_seen=true;check(enemies==[2,0],"Hostile replacement changed faction order or replaced the same slot twice")
		empty_seen=empty_seen or jobs==0
		check(history.count(true)==0 and random.snapshot()==state.initial_random,"Population consumed its caller-owned inputs")
	check(counts.has(3) and counts.has(4) and counts.size()==2,"Early lounge count is not three or four")
	check(kinds.size()==5 and roles.size()==4 and empty_seen and enemy_seen and merchant_seen,"Seed fixtures did not cover the early roles, all job kinds, empty-job lounge and hostility")

func verify_retention(bindings: RefCounted,cat: RefCounted,lib: RefCounted,generator: RefCounted):
	var original: Dictionary=generator.snapshot();var restored:=Contacts.new()
	check(restored.restore(bindings,cat,lib,original) and restored.snapshot()==original,restored.error)
	for corruption in ["missing","identity","name","portrait","reward","random","history","cursor","foreign_station","extra"]:
		var bad: Dictionary=original.duplicate(true)
		match corruption:
			"missing":bad.erase("initial_random")
			"identity":bad.base_content_id="foreign"
			"name":bad.contacts[0].name="Changed"
			"portrait":bad.contacts[0].portrait.parts[0]=255
			"reward":bad.contacts[0].offer={"reward":1000000}
			"random":bad.random.state+=1
			"history":bad.initial_history[0]=1
			"cursor":bad.context.campaign_cursor=16
			"foreign_station":bad.context.station_id=98
			"extra":bad.context.credits=1000
		check(not restored.restore(bindings,cat,lib,bad) and restored.snapshot()==original,"Invalid retained population changed its owner: "+corruption)
	original.contacts.clear()
	check(restored.snapshot()==generator.snapshot(),"Caller mutation changed the retained population")

func verify_provenance(bindings: RefCounted,pack: String):
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for corruption in ["count","names","portraits","reserved","missing_span","span_offset"]:
		var bad: Dictionary=bindings.early_contracts.duplicate(true)
		match corruption:
			"count":bad.generation.count.minimum=5
			"names":bad.generation.names.pool_choices_by_faction[3][0]=[0]
			"portraits":bad.generation.portraits.counts[6][3]=1
			"reserved":bad.generation.destinations.helper_excluded_station_ids=[]
			"missing_span":bad.provenance.erase("contact_source_random")
			"span_offset":bad.provenance.contact_hostile_order.offset+=1
		check(not Definitions.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.mido_travel).is_empty(),"Changed contact declaration accepted: "+corruption)

func verify_portraits(bindings: RefCounted,lib: RefCounted,pack: String):
	var visuals:=Visuals.new();var compositor:=Portrait.new()
	if not visuals.open(pack,lib.manifest):check(false,visuals.error);return
	var directory:=OS.get_environment("GOF2_CONTACT_PORTRAITS")
	if not directory.is_empty():DirAccess.make_dir_recursive_absolute(directory)
	for family in [0,1,2,4,6,7,10]:
		var parts:=[]
		for count in bindings.early_contracts.generation.portraits.counts[family]:parts.append(maxi(0,int(count)-1))
		var image: Dictionary=compositor.compose_definition(lib,bindings,visuals,-1,"large",{"status":"fixed","family":family,"parts":parts})
		check(not image.is_empty(),"Original generated portrait cannot be composed: "+compositor.error)
		if not image.is_empty() and not directory.is_empty():check(image.image.save_png(directory.path_join("family-%d.png"%family))==OK,"Could not save local portrait verification")

func check(condition: bool,message: String):
	checks+=1
	if not condition:failures+=1;push_error(message)
