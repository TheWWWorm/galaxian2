extends SceneTree
## Detached population and restoration checks; no journey or purchase is earned.
const Definitions=preload("res://src/content/persistent_contact_definitions.gd")
const Ordinary=preload("res://src/content/ordinary_generation_definitions.gd")
const Generation=preload("res://src/content/lounge_contact_definitions.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Navigation=preload("res://src/simulation/contract_navigation.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Portrait=preload("res://src/content/portrait_layer_definitions.gd")
var checks:=0
var failures:=0

class Draws extends RefCounted:
	var remaining:=[]
	var wrong:=false
	func _init(values: Array):remaining=values.duplicate(true)
	func next_int(bound: int) -> int:
		if remaining.is_empty():wrong=true;return 0
		var pair: Array=remaining.pop_front()
		if int(pair[0])!=bound:wrong=true
		return int(pair[1])

func _initialize():
	verify_proof()
	verify_count_draws()
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, binding and visual paths")
	else:verify_population(args)
	print("Persistent lounge contacts: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func check(condition: bool,message: String):
	checks+=1
	if not condition:failures+=1;printerr("FAIL: "+message)

func declarations(spans: Dictionary=Definitions.SPANS,origin: int=0x400000) -> Dictionary:
	var data: Dictionary=Definitions.VALUES.duplicate(true);data.provenance={}
	for key in spans:data.provenance[key]={"offset":origin+int(spans[key][0]),"bytes":int(spans[key][1])}
	return data

func verify_proof():
	const SIZE=0x1000000
	var arrival:={"provenance":{"actor":{"offset":0x400000,"bytes":315}}}
	check(Definitions.validate({},SIZE,"x86_64",{},{}).is_empty(),"Missing optional contact data was rejected")
	check(not Definitions.parameters({}),"Absent declarations enabled contacts")
	for spans in [Definitions.SPANS,Definitions.MAC_SPANS]:
		var data:=declarations(spans)
		check(Definitions.validate(data,SIZE,"x86_64",arrival,Ordinary.VALUES).is_empty(),"Complete source extents were rejected")
		check(Definitions.parameters(JSON.parse_string(JSON.stringify(data))),"Imported integer values were rejected")
		for key in data.provenance:
			for field in ["offset","bytes"]:
				var changed:=data.duplicate(true);changed.provenance[key][field]+=1
				check(not Definitions.validate(changed,SIZE,"x86_64",arrival,Ordinary.VALUES).is_empty(),"Changed source extent was admitted: "+key+"/"+field)
			var missing:=data.duplicate(true);missing.provenance.erase(key)
			check(not Definitions.validate(missing,SIZE,"x86_64",arrival,Ordinary.VALUES).is_empty(),"Missing source extent was admitted")
		for architecture in ["armv7","arm64",""]:
			check(not Definitions.validate(data,SIZE,architecture,arrival,Ordinary.VALUES).is_empty(),"Unsupported source architecture was admitted")
		for anchor in [{},{"provenance":null},{"provenance":{"actor":{"offset":0x400000,"bytes":314}}}]:
			check(not Definitions.validate(data,SIZE,"x86_64",anchor,Ordinary.VALUES).is_empty(),"Missing source anchor was admitted")
		check(not Definitions.validate(data,SIZE,"x86_64",arrival,{}).is_empty(),"Missing ordinary generation was admitted")
	for key in Definitions.VALUES:
		var changed:=declarations();changed.erase(key)
		check(not Definitions.parameters(changed),"Missing parameter was admitted: "+key)
	var changed:=declarations();changed.supported_contact_ids.append(6)
	check(not Definitions.parameters(changed),"An unproved contact was admitted")

func verify_count_draws():
	for case in [[0,[[2,0],[2,0]],3],[0,[[2,1],[2,1]],4],
		[1,[[2,1]],5],[1,[[2,0],[2,0]],4],[1,[[2,0],[2,1]],5]]:
		var owner:=Contacts.new();owner._rules=Generation.VALUES.duplicate(true)
		var draws:=Draws.new(case[1]);owner._rng=draws
		check(owner._population_count(int(case[0]),declarations())==case[2],"Contact count changed the cap decision")
		check(not draws.wrong and draws.remaining.is_empty() and owner._draws==case[1].size(),"Count consumed an incorrect random draw")

func verify_population(args: PackedStringArray):
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	if not load("res://src/content/free_campaign_definitions.gd").chapter_available(bindings.mido_travel):
		verify_earlier_records(bindings,cat,library)
		return
	var imported_capability: Dictionary=bindings.persistent_contacts.duplicate(true)
	var capability:=declarations()
	# A detached capability exercises native composition before a pack integrates
	# these declarations. It does not rewrite or relabel the supplied binding.
	bindings.persistent_contacts=capability
	check(Definitions.available(bindings),"Ordinary supported content did not compose with persistent declarations")
	var flags:=Navigation.initial_availability(bindings,cat,false)
	var history:=[];history.resize(15);history.fill(false)
	var campaign_rules=load("res://src/content/free_campaign_definitions.gd")
	var cursors: Array=[23,24]
	for cursor in cursors:check(campaign_rules.supported(bindings.mido_travel,cursor),"Contact test requires a supported campaign context")
	if failures:return
	var context:={"campaign_cursor":cursors[0],"station_id":10,"rank":0,"reputation":{"axes":[0,0],"override":-1},"difficulty":1.0,"system_availability":flags}
	var initial_random:=Random.new();initial_random.seed_from(0)
	bindings.persistent_contacts={}
	var unsupported:=Contacts.new()
	check(not unsupported.prepare(bindings,cat,library,context,initial_random.snapshot(),history) and unsupported.snapshot().is_empty() and unsupported.error.contains("unsupported persistent contact"),"Missing capability admitted or partially retained an authored population")
	bindings.persistent_contacts=capability
	var rules: Dictionary=bindings.early_contracts.ordinary_generation.persistent
	var raw:=library.read_resource(rules.resource,1024*1024)
	var records:=Contacts.decode_persistent_contacts(raw,rules)
	check(records.size()==27,"Original persistent table failed to decode")
	check(Contacts.decode_persistent_contacts(raw.slice(0,raw.size()-1),rules).is_empty(),"Truncated table was admitted")
	var extra:=raw.duplicate();extra.append(0)
	check(Contacts.decode_persistent_contacts(extra,rules).is_empty(),"Trailing table bytes were ignored")
	var selected:=records.filter(func(row):return row.fields[1]==10)
	check(selected.size()==1,"Station10 does not have exactly one authored contact")
	if selected.size()!=1:return
	var authored: Dictionary=selected[0]
	check(authored.fields==[5,10,6,1,1,-1,37,-1,2999] and authored.portrait==[1,2,2,0,8],"Authored contact terms differ from the selected source")
	verify_row_boundaries(cat,context,bindings,selected,capability)
	var sizes:={};var hostiles:=0
	for cursor in cursors:
		context.campaign_cursor=cursor
		for seed_value in range(16):
			context.reputation.axes=[100,100] if seed_value%2 else [0,0]
			var random:=Random.new();random.seed_from(seed_value*4097)
			var owner:=Contacts.new()
			if not owner.prepare(bindings,cat,library,context,random.snapshot(),history):check(false,owner.error);return
			var saved:=owner.snapshot();var first: Dictionary=saved.contacts[0]
			sizes[saved.contacts.size()]=true
			check(saved.contacts.size() in [4,5],"Authored population lost its count bound")
			check(first.contact_id==0 and first.source_contact_id==5 and first.generated==false and first.role==3 and first.name==authored.name,"Authored contact identity/order changed")
			check(first.faction==1 and first.male and first.portrait=={"status":"fixed","family":1,"parts":[2,2,0,8]},"Authored identity or portrait was regenerated")
			check(first.blueprint=={"item_id":37,"price":2999} and first.offer.is_empty(),"Blueprint terms became a procedural mission")
			for index in range(1,saved.contacts.size()):
				var row: Dictionary=saved.contacts[index]
				check(row.contact_id==index and row.generated and row.source_contact_id==-1,"Generated contact metadata lost its slot/source distinction")
				if row.role==7:hostiles+=1
			var room:=int(cat.tables.systems[6].fields[int(bindings.early_contracts.lounge_presentation.system_faction_field)])
			check(saved.contacts.size()<=bindings.early_contracts.lounge_presentation.visitor_slots[room].size(),"Authored roster exceeds original room positions")
			check(not Portrait.plan(bindings.portrait_layers,first.portrait,"large").has("error"),"Authored portrait does not compose with existing layers")
			var restored:=Contacts.new()
			check(restored.restore(bindings,cat,library,saved) and restored.snapshot()==saved,"Authored population failed exact deterministic restoration: "+restored.error)
			if seed_value==0:
				var corrupted:=saved.duplicate(true);corrupted.contacts[0].generated=true
				check(not restored.restore(bindings,cat,library,corrupted) and restored.snapshot()==saved,"Forged generated flag changed retained contact state")
	check(sizes.size()==2 and hostiles>0,"Population cases did not cover both count and hostile replacement branches")
	verify_supplier_contacts(bindings,cat,library,flags,history,records,cursors)
	verify_zero_contact_population(bindings,cat,library,flags,history,capability)
	bindings.persistent_contacts=imported_capability

func verify_earlier_records(bindings: RefCounted,cat: RefCounted,library: RefCounted):
	# Earlier packs have no chapter arrival capability. Exercise the shared
	# native contact constructor against their original data, not a fake career.
	var rules: Dictionary=bindings.early_contracts.ordinary_generation.persistent
	var raw: PackedByteArray=library.read_resource(rules.resource,1024*1024)
	var rows:=Contacts.decode_persistent_contacts(raw,rules)
	check(rows.size()==27,"Earlier original contact table failed to decode")
	check(Contacts.decode_persistent_contacts(raw.slice(0,raw.size()-1),rules).is_empty(),"Earlier truncated contact table was accepted")
	for values in [[5,10,6,1,1,-1,37,-1,2999],[4,43,8,0,1,-1,33,-1,1999],[6,5,1,4,1,-1,46,-1,5999]]:
		var selected:=rows.filter(func(row):return row.fields[1]==values[1])
		check(selected.size()==1 and selected[0].fields==values,"Earlier authored contact differs from the shared branch")
		if failures:return
		var owner:=Contacts.new();owner._rules=bindings.early_contracts.generation
		owner._ordinary=bindings.early_contracts.ordinary_generation;owner._catalogues=cat
		owner._context={"campaign_cursor":24,"station_id":values[1]}
		var result:=owner._authored_contacts(selected,int(values[2]),declarations())
		check(result.size()==1 and owner._draws==0,"Earlier native authored construction consumed a random identity")
		if result.is_empty():return
		check(result[0].source_contact_id==values[0] and not result[0].generated and result[0].blueprint=={"item_id":values[6],"price":values[8]},"Earlier authored service or terms changed")
		check(not Portrait.plan(bindings.portrait_layers,result[0].portrait,"large").has("error"),"Earlier original portrait cannot compose")
		for field in [0,2,5,7]:
			var changed:=selected.duplicate(true);changed[0].fields[field]+=1;owner.error=""
			check(owner._authored_contacts(changed,int(values[2]),declarations()).is_empty() and not owner.error.is_empty(),"Earlier unproved contact service was accepted")
	print("Earlier pack: detached source-backed contact construction; no chapter journey or population restore claimed")

func verify_supplier_contacts(bindings: RefCounted,cat: RefCounted,library: RefCounted,flags: Array,history: Array,records: Array,cursors: Array):
	for values in [[4,43,8,0,1,-1,33,-1,1999],[6,5,1,4,1,-1,46,-1,5999]]:
		var rows:=records.filter(func(row):return row.fields[1]==values[1])
		check(rows.size()==1 and rows[0].fields==values,"Supplier contact differs from the original table")
		if failures:return
		var source: Dictionary=rows[0]
		for cursor in [18,int(cursors.back())]:
			var context:={"campaign_cursor":cursor,"station_id":values[1],"rank":0,"reputation":{"axes":[0,0],"override":-1},"difficulty":1.0,"system_availability":flags}
			for seed_value in range(4):
				var random:=Random.new();random.seed_from(seed_value*4097)
				var owner:=Contacts.new()
				if not owner.prepare(bindings,cat,library,context,random.snapshot(),history):check(false,owner.error);return
				var saved:=owner.snapshot();var first: Dictionary=saved.contacts[0]
				check(saved.contacts.size() in [4,5] and first.contact_id==0 and first.source_contact_id==values[0] and not first.generated and first.name==source.name,"Supplier lost its authored-first roster")
				check(first.faction==values[3] and first.male and first.role==3 and first.offer.is_empty() and first.blueprint=={"item_id":values[6],"price":values[8]},"Supplier blueprint changed its service or price")
				check(first.portrait=={"status":"fixed","family":source.portrait[0],"parts":source.portrait.slice(1)} and not Portrait.plan(bindings.portrait_layers,first.portrait,"large").has("error"),"Supplier portrait cannot compose with original layers")
				var restored:=Contacts.new()
				check(restored.restore(bindings,cat,library,saved) and restored.snapshot()==saved,"Supplier contacts did not restore exactly: "+restored.error)
				var invalid:=saved.duplicate(true);invalid.contacts[0].blueprint.price+=1
				check(not restored.restore(bindings,cat,library,invalid) and restored.snapshot()==saved,"Altered supplier terms changed retained contacts")

func verify_row_boundaries(cat: RefCounted,context: Dictionary,bindings: RefCounted,selected: Array,capability: Dictionary):
	var owner:=Contacts.new();owner._rules=bindings.early_contracts.generation
	owner._ordinary=bindings.early_contracts.ordinary_generation;owner._catalogues=cat;owner._context=context.duplicate(true)
	var result:=owner._authored_contacts(selected,6,capability)
	check(result.size()==1 and owner._draws==0,"Authored contact consumed random identity draws")
	owner._context.campaign_cursor=16
	check(owner._authored_contacts(selected,6,capability).is_empty() and owner.error.is_empty(),"Persistent contact appeared before its source cursor gate")
	owner._context.campaign_cursor=17
	check(owner._authored_contacts(selected,6,capability).size()==1,"Strict after16 gate changed")
	for field in [0,2,5,7]:
		var altered:=selected.duplicate(true);altered[0].fields[field]+=1
		owner.error=""
		check(owner._authored_contacts(altered,6,capability).is_empty() and not owner.error.is_empty(),"Unproved authored service was admitted")
	var altered:=selected.duplicate(true);altered[0].portrait[4]=9;owner.error=""
	check(owner._authored_contacts(altered,6,capability).is_empty() and not owner.error.is_empty(),"Out-of-range fixed portrait was admitted")
	owner.error=""
	check(owner._authored_contacts(selected,6,{}).is_empty() and not owner.error.is_empty(),"Missing capability silently discarded an authored contact")

func verify_zero_contact_population(bindings: RefCounted,cat: RefCounted,library: RefCounted,flags: Array,history: Array,capability: Dictionary):
	var context:={"campaign_cursor":18,"station_id":98,"rank":0,"reputation":{"axes":[100,100],"override":-1},"difficulty":1.0,"system_availability":flags}
	for seed_value in range(8):
		var random:=Random.new();random.seed_from(seed_value)
		bindings.persistent_contacts={}
		var earlier:=Contacts.new()
		if not earlier.prepare(bindings,cat,library,context,random.snapshot(),history):check(false,earlier.error);return
		bindings.persistent_contacts=capability
		var current:=Contacts.new()
		if not current.prepare(bindings,cat,library,context,random.snapshot(),history):check(false,current.error);return
		check(current.snapshot()==earlier.snapshot(),"Optional contacts changed an ordinary zero-contact snapshot")
		check(current.snapshot().contacts.all(func(row):return not row.has("generated") and not row.has("source_contact_id")),"Existing generated-contact schema changed")
