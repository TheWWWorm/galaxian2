extends SceneTree
## Explicit selection fixtures verify offer terms, not random contact generation
## or playable contract completion. No career, money or story state is awarded.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Offer=preload("res://src/simulation/contract_offer.gd")
const Definitions=preload("res://src/content/early_contract_definitions.gd")
var failures:=0
var checks:=0

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Early contract offers: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):
		check(false,lib.error+bindings.error+cat.error);return
	var offer:=Offer.new()
	var text_shift:=2 if cat.tables.ships.size()==64 else 0
	var context:={"campaign_cursor":13,"station_id":79,"rank":0,"reputation":{"axes":[30,0],"override":-1},"client_faction":3}
	var choices:={"kind_index":0,"difficulty_index":0,"destination_station_id":76,"cargo_description_index":0}
	if bindings.early_contracts.is_empty():
		check(not Offer.available(bindings) and not offer.configure(bindings,cat,context,choices) and offer.snapshot().is_empty(),"Older bindings fabricated early offers")
		return
	# The values below are hand-derived source vectors. In particular, quantities
	# are not randomized independently of early difficulty, and junk rewards do
	# not use conventional nearest-50 rounding.
	var vectors:=[
		{"kind":11,"name":"Passenger","quantity":[3,5],"reward":[1950,3100]},
		{"kind":0,"name":"Courier","quantity":[14,24],"reward":[2050,2600]},
		{"kind":7,"name":"Junk removal","quantity":[0,0],"reward":[1400,1800]},
		{"kind":4,"name":"Pirate hunting","quantity":[0,0],"reward":[2050,2600]},
		{"kind":12,"name":"Challenge","quantity":[0,0],"reward":[2050,2600]}]
	for index in vectors.size():
		var vector: Dictionary=vectors[index]
		choices.kind_index=index;choices.destination_station_id=79 if index==4 else 76
		for difficulty in 2:
			choices.difficulty_index=difficulty
			check(offer.configure(bindings,cat,context,choices),offer.error)
			var state: Dictionary=offer.snapshot();var mission: Dictionary=state.mission
			check(mission.kind==vector.kind and mission.difficulty==difficulty+1 and mission.quantity==vector.quantity[difficulty],"Early mission parameters changed")
			check(mission.reward==vector.reward[difficulty] and mission.bonus==0 and not mission.story,"Wrong source reward or fictional completion")
			check(lib.strings[mission.title_text_id]==vector.name and mission.briefing_text_id==773+text_shift+vector.kind,"Offer lost its original localized title or briefing")
			check(state.requirements.cargo_tons==(mission.quantity if mission.kind==0 else 0) and state.requirements.passenger_places==(mission.quantity if mission.kind==11 else 0),"Passenger space was confused with cargo tonnage")
			check(state.requirements.cargo_item_id==(116 if mission.kind==0 else -1),"Courier description was confused with the actual mission cargo")
			check(not state.has("accepted") and not state.has("completed_side_missions") and not state.has("credits"),"Quotation granted a career mutation")
	choices={"kind_index":1,"difficulty_index":0,"destination_station_id":75,"cargo_description_index":0}
	for description in 7:
		choices.cargo_description_index=description
		check(offer.configure(bindings,cat,context,choices),offer.error)
		var state:=offer.snapshot()
		check(state.mission.source_parameter==description and state.mission.cargo_text_id==800+text_shift+description and state.requirements.cargo_item_id==116 and state.mission.quantity==14,"Courier description changed the physical cargo")
	choices={"kind_index":3,"difficulty_index":0,"destination_station_id":75,"cargo_description_index":0}
	context.reputation.axes=[50,-25]
	for faction in 8:
		context.client_faction=faction
		check(offer.configure(bindings,cat,context,choices),offer.error)
		check(offer.snapshot().mission.bonus==[1050,0,0,500,0,0,0,0][faction],"Wrong faction sign or unrounded bonus input")
	context.client_faction=0
	for rank in [1,2,20]:
		context.rank=rank
		check(offer.configure(bindings,cat,context,choices),offer.error)
		check(offer.snapshot().mission.reward=={1:2050,2:2100,20:82050}[rank],"Rank reward is not cubic")
	context.rank=0;choices.kind_index=4;choices.destination_station_id=79
	check(offer.configure(bindings,cat,context,choices) and offer.snapshot().mission.bonus==0,"Challenge received a standing bonus")
	# Every Mido station can issue an early quote. Deliveries use a different
	# station; challenge uses the contact station, including Kernstal.
	for station in cat.tables.systems[15].station_ids:
		context.station_id=station;choices.kind_index=0;choices.destination_station_id=78 if station!=78 else 75
		for cursor in [13,14,15]:
			context.campaign_cursor=cursor
			check(offer.configure(bindings,cat,context,choices),offer.error)
		choices.kind_index=4;choices.destination_station_id=station
		check(offer.configure(bindings,cat,context,choices),offer.error)
	context.station_id=75;choices.kind_index=0;choices.destination_station_id=79
	var retained:=offer.snapshot()
	check(not offer.configure(bindings,cat,context,choices) and offer.snapshot()==retained,"Early delivery bypassed the reserved Kernstal destination")
	for vector in [[0,0],[24,0],[25,50],[26,0],[49,0],[50,50],[74,50],[75,100],[76,50],[99,50],[1025,1050],[1445,1400]]:
		check(Offer.quantize_credits(float(vector[0]),50)==vector[1],"Credit quantization changed at "+str(vector[0]))
	verify_retention(bindings,cat,offer)
	verify_provenance(bindings,args[1])

func verify_retention(bindings: RefCounted,cat: RefCounted,offer: RefCounted):
	var held: Dictionary=offer.snapshot()
	var restored:=Offer.new()
	check(restored.restore(bindings,cat,held) and restored.snapshot()==held,restored.error)
	for corruption in ["identity","reward","bonus","quantity","story","accepted","cursor","foreign_station","same_delivery","remote_challenge","difficulty","description","rank","reputation","foreign_faction","requirement","missing","extra"]:
		var bad:=held.duplicate(true)
		match corruption:
			"identity":bad.base_content_id="foreign"
			"reward":bad.mission.reward+=1
			"bonus":bad.mission.bonus+=50
			"quantity":bad.mission.quantity+=1
			"story":bad.mission.story=true
			"accepted":bad.accepted=true
			"cursor":bad.context.campaign_cursor=16
			"foreign_station":bad.choices.destination_station_id=98
			"same_delivery":bad.choices.kind_index=0
			"remote_challenge":bad.choices.destination_station_id=75
			"difficulty":bad.choices.difficulty_index=2
			"description":bad.choices.cargo_description_index=7
			"rank":bad.context.rank=21
			"reputation":bad.context.reputation.axes[0]=101
			"foreign_faction":bad.context.client_faction=8
			"requirement":bad.requirements.cargo_tons=99
			"missing":bad.erase("context")
			"extra":bad.context.credits=1000
		check(not restored.restore(bindings,cat,bad) and restored.snapshot()==held,"Invalid retained quote changed its owner: "+corruption)
	var context: Dictionary=held.context.duplicate(true);var choices: Dictionary=held.choices.duplicate(true)
	check(restored.configure(bindings,cat,context,choices),restored.error)
	context.reputation.axes[0]=-100;choices.kind_index=-1;held.mission.reward=1
	check(restored.snapshot()==offer.snapshot(),"Caller mutation changed the retained quotation")
	var before: Dictionary=restored.snapshot()
	check(not restored.configure(bindings,cat,context,choices) and restored.snapshot()==before,"Rejected selection destroyed a previous offer")

func verify_provenance(bindings: RefCounted,pack: String):
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var terms: Dictionary=bindings.early_contracts
	for corruption in ["quantity","reward","missing_span","span_offset","span_length","architecture","travel"]:
		var bad:=terms.duplicate(true);var arch:="x86_64";var travel: Dictionary=bindings.mido_travel.duplicate(true)
		match corruption:
			"quantity":bad.passenger.quantity_by_difficulty[0]=1
			"reward":bad.reward.junk_multiplier=1.0
			"missing_span":bad.provenance.erase("side_mission_owner")
			"span_offset":bad.provenance.side_mission_owner.offset+=1
			"span_length":bad.provenance.side_mission_owner.bytes-=1
			"architecture":arch="unsupported"
			"travel":travel.erase("return_visit")
		check(not Definitions.validate(bad,int(header.source_executable_bytes),arch,bindings.arrival_staging,travel).is_empty(),"Changed contract declaration accepted: "+corruption)
	if terms.has("acceptance"):
		var alternate: bool=terms.briefing_text_base==775
		var bad:=terms.duplicate(true)
		bad.acceptance.replacement_text_id=851 if alternate else 853
		check(not Definitions.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.mido_travel).is_empty(),"Mixed source acceptance text was accepted")
		bad=terms.duplicate(true)
		var other: Dictionary=Definitions.ACCEPTANCE_SPANS if alternate else Definitions.MAC_ACCEPTANCE_SPANS
		bad.provenance.contract_replacement_notice.offset=int(bindings.arrival_staging.provenance.actor.offset)+int(other.contract_replacement_notice[0])
		check(not Definitions.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.mido_travel).is_empty(),"Mixed source acceptance proof was accepted")

func check(condition: bool,message: String):
	checks+=1
	if not condition:failures+=1;push_error(message)
