extends "res://tests/mido_kernstal_return.gd"
## The inherited scenario discloses its cursor-ten placement and native onward
## visits. Offers here are explicit fixtures, not generated lounge inhabitants.
## Cabin installation and funded wallets below are detached boundary fixtures;
## they do not claim working shop purchases or earned contract rewards.
const Contracts=preload("res://src/simulation/contract_session.gd")
const Offer=preload("res://src/simulation/contract_offer.gd")
const Terms=preload("res://src/content/early_contract_definitions.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var contracts_verified:=false

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:
		var lib:=Library.new();var bindings:=Bindings.new()
		if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest):check(false,lib.error+bindings.error)
		elif Contracts.available(bindings):verify(args)
		else:
			check(not Contracts.new().configure(bindings,null,{},null,0.5),"Older content fabricated contract acceptance")
			contracts_verified=true
	check(contracts_verified,"Contract acceptance was not verified")
	print("Early contract acceptance: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func after_contract_intro(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	var replacement_text:=853 if cat.tables.ships.size()==64 else 851
	var incoming: Dictionary=station.snapshot()
	var original: RefCounted=station.fork()
	if not station.open_contracts(bindings,cat):check(false,station.error);return
	var empty: Dictionary=station.snapshot()
	check(empty.contracts.credits==0 and empty.contracts.passengers==0 and empty.contracts.mission.is_empty(),"Lounge initialization invented money, passengers or a mission")
	check(station.open_contracts(bindings,cat) and station.snapshot()==empty,"Opening the lounge twice reset its owner")
	check(not station.open_contracts(bindings,cat,1.5) and station.snapshot()==empty,"Changing difficulty reset the retained session")
	var courier:=offer_for(bindings,cat,incoming,1)
	var pirate:=offer_for(bindings,cat,incoming,3)
	var passenger:=offer_for(bindings,cat,incoming,0)
	var challenge:=offer_for(bindings,cat,incoming,4)
	if courier==null or pirate==null or passenger==null or challenge==null:return
	check(station.register_contract_offer(0,courier) and station.register_contract_offer(1,courier) and station.register_contract_offer(2,pirate) and station.register_contract_offer(3,passenger) and station.register_contract_offer(4,challenge),station.error)
	var registered: Dictionary=station.snapshot()
	check(not station.register_contract_offer(0,pirate) and station.snapshot()==registered,"An existing contact changed its terms")
	var preview: Dictionary=station.contract_preview(3)
	check(not preview.can_accept and preview.reason_text_id==327 and preview.passenger_capacity==0,"The starter loadout offered nonexistent passenger places")
	check(not station.accept_contract(3) and station.snapshot()==registered,"A blocked passenger job changed inventory")
	preview=station.contract_preview(0)
	check(preview.can_accept and preview.fee==0 and not preview.replacement_required and preview.cargo_tons==14,"The source small courier job was unavailable")
	if not station.accept_contract(0):check(false,station.error);return
	var accepted: Dictionary=station.snapshot()
	check(accepted.contracts.mission==courier.snapshot().mission and accepted.contracts.active_offer_id==0 and accepted.contracts.offers[0].consumed,"The accepted side mission was not retained")
	check(accepted.cargo.used==incoming.cargo.used+14 and accepted.cargo.entries[-1]=={"item_id":116,"quantity":14,"mission":true},"The courier did not load protected source cargo")
	check(accepted.equipment.cargo==accepted.cargo and accepted.equipment.loadout==accepted.loadout,"Acceptance split the station and inventory owners")
	check(accepted.contracts.credits==0 and accepted.mission==incoming.mission and accepted.completed_side_missions==0 and accepted.progress==incoming.progress,"Acceptance rewarded or replaced the story objective")
	check(not station.accept_contract(0) and station.snapshot()==accepted,"Repeated acceptance duplicated cargo or fees")
	check(station.register_contract_offer(0,courier) and station.snapshot()==accepted and station.contract_preview(0).is_empty(),"Re-registering a consumed contact restored it")
	preview=station.contract_preview(1)
	check(not preview.can_accept and preview.reason_text_id==326 and preview.replacement_required,"Replacement removed old cargo before checking free space")
	check(not station.accept_contract(1,true) and station.snapshot()==accepted,"A full-hold replacement discarded the current job")
	preview=station.contract_preview(2)
	check(preview.can_accept and preview.replacement_text_id==replacement_text and preview.replacement_required,"The replacement lost its source warning")
	check(not station.accept_contract(2) and station.snapshot()==accepted,"An unconfirmed replacement changed the accepted job")
	if not station.accept_contract(2,true):check(false,station.error);return
	var replaced: Dictionary=station.snapshot()
	check(replaced.cargo==incoming.cargo and replaced.contracts.mission.kind==4 and replaced.contracts.offers[0].consumed,"Replacing a courier lost ordinary cargo or revived its generated contact")
	check(not station.accept_contract(0,true) and station.snapshot()==replaced,"An abandoned generated contact duplicated its old job")
	check(station.accept_contract(4,true) and station.snapshot().contracts.mission.kind==12 and station.snapshot().cargo==incoming.cargo,"The local challenge changed cargo")
	check(station.accept_contract(1,true) and station.snapshot().cargo==accepted.cargo,"An untouched contact could not be accepted after space was freed")
	check(station.prepare_departure(bindings,cat).is_empty() and station.snapshot().completed_side_missions==0,"Acceptance bypassed unsupported flight objectives or completed a contract")
	check(original.snapshot()==incoming,"A detached contract session changed its original station")
	verify_fees(bindings,cat,original,pirate)
	verify_passengers(bindings,cat,original,passenger,pirate)
	verify_cargo_merge(bindings,cat,original,courier,pirate)
	verify_rejections(bindings,cat,original)
	if Contacts.available(bindings):verify_population(bindings,cat,library,original)
	check(not library.strings[192].is_empty() and not library.strings[326].is_empty() and not library.strings[327].is_empty() and not library.strings[replacement_text].is_empty(),"Acceptance lost original requirement text")
	contracts_verified=true

func verify_population(bindings: RefCounted,cat: RefCounted,library: RefCounted,original: RefCounted) -> void:
	# A fixed native seed is an explicit lounge input, not a claim that every
	# earlier hidden original station draw has been reconstructed.
	var random:=Random.new();random.seed_from(0)
	var history: Array=[];history.resize(15);history.fill(false)
	var station: RefCounted=original.fork()
	if not station.open_contracts(bindings,cat):check(false,station.error);return
	var before: Dictionary=station.snapshot()
	check(not station.populate_contracts(bindings,cat,library,{},history) and station.snapshot()==before,"A failed lounge generation changed the retained station")
	if not station.populate_contracts(bindings,cat,library,random.snapshot(),history):check(false,station.error);return
	var generated: Dictionary=station.snapshot()
	check(generated.contracts.has("population") and not generated.contracts.offers.is_empty(),"The source population did not register its generated offers")
	check(not station.populate_contracts(bindings,cat,library,random.snapshot(),history) and station.snapshot()==generated,"Reopening rerolled the lounge contacts")
	check(station.open_contracts(bindings,cat) and station.snapshot()==generated,"Reopening reset a generated lounge")
	var accepted_id:=-1
	for contact in generated.contracts.population.contacts:
		if contact.offer.is_empty():
			check(station.contract_preview(contact.contact_id).is_empty(),"A non-contract contact was available for mission acceptance")
			continue
		check(generated.contracts.offers[contact.contact_id].offer==contact.offer,"A generated contact lost its quoted terms")
		var preview: Dictionary=station.contract_preview(contact.contact_id)
		if accepted_id<0 and preview.can_accept:accepted_id=contact.contact_id
	check(accepted_id>=0,"Seed zero needs an affordable generated job with the earned starter inventory")
	if accepted_id<0:return
	var quote:=Offer.new()
	check(quote.restore(bindings,cat,generated.contracts.offers[accepted_id].offer),quote.error)
	check(not station.register_contract_offer(999,quote) and station.snapshot()==generated,"An absent generated contact was given a fabricated offer")
	check(station.accept_contract(accepted_id),station.error)
	var accepted: Dictionary=station.snapshot()
	check(accepted.contracts.population==generated.contracts.population and accepted.contracts.offers[accepted_id].consumed,"Accepting a generated job rerolled or revived its contact")
	check(accepted.mission==before.mission and accepted.progress==before.progress and accepted.completed_side_missions==0 and accepted.contracts.credits==0,"Generated acceptance completed the story or paid an unearned reward")
	check(not station.accept_contract(accepted_id) and station.snapshot()==accepted,"Generated contact acceptance was duplicated")
	check(not original.snapshot().has("contracts"),"The detached generated lounge changed its original station")

func offer_for(bindings: RefCounted,cat: RefCounted,station: Dictionary,kind_index: int) -> RefCounted:
	var offer:=Offer.new()
	var context:={"campaign_cursor":station.campaign_cursor,"station_id":station.loadout.station_id,
		"rank":station.progress.rank,"reputation":station.progress.reputation.duplicate(true),"client_faction":3}
	var choices:={"kind_index":kind_index,"difficulty_index":0,"destination_station_id":79 if kind_index==4 else 76,"cargo_description_index":0}
	if not offer.configure(bindings,cat,context,choices):check(false,offer.error);return null
	return offer

func verify_fees(bindings: RefCounted,cat: RefCounted,original: RefCounted,pirate: RefCounted) -> void:
	for difficulty in [0.5,1.0,1.499,1.5]:
		check(Contracts.acceptance_fee(bindings.early_contracts,{"reward":2050,"bonus":1050},difficulty)==(310 if difficulty==1.5 else 0),"Acceptance fee ignored the exact hardest setting or its reputation bonus")
	var station: RefCounted=original.fork()
	if not station.open_contracts(bindings,cat,1.5) or not station.register_contract_offer(0,pirate):check(false,station.error);return
	var preview: Dictionary=station.contract_preview(0)
	var before: Dictionary=station.snapshot()
	check(not preview.can_accept and preview.reason_text_id==192 and preview.missing_credits==preview.fee and preview.fee>0,"A penniless hard-mode pilot could pay the fee")
	check(not station.accept_contract(0) and station.snapshot()==before,"An unaffordable fee changed the career")
	# Deliberate financial boundary fixture, not an earned payment or save.
	station._contracts._state.credits=preview.fee-1
	before=station.snapshot()
	check(not station.accept_contract(0) and station.snapshot()==before,"One credit short was treated as affordable")
	station._contracts._state.credits=preview.fee
	check(station.accept_contract(0) and station.snapshot().contracts.credits==0,"Exact funds did not pay exactly one acceptance fee")
	before=station.snapshot()
	check(not station.accept_contract(0) and station.snapshot()==before,"A repeated hard-mode acceptance charged again")

func cabin_fixture(bindings: RefCounted,cat: RefCounted,original: RefCounted) -> RefCounted:
	var cabins:=Contracts.cabin_catalogue(cat,bindings.early_contracts.acceptance)
	check(not cabins.is_empty(),"Mac catalogue passenger cabins are absent")
	if cabins.is_empty():return null
	var cabin_id: int=cabins.keys()[0]
	var station: RefCounted=original.fork()
	var equipment: RefCounted=station._equipment
	var slots: Array=equipment._state.loadout.slots
	var category:=int(cat.tables.items[cabin_id].properties[1])
	var slot_index:=-1;var offset:=0
	for i in category:offset+=int(equipment._counts[i])
	for i in int(equipment._counts[category]):
		if slots[offset+i]==null:slot_index=offset+i;break
	if slot_index<0:slot_index=offset
	check(slot_index<slots.size(),"The cabin fixture requires a compatible equipment slot")
	if slot_index>=slots.size():return null
	# The starter ship's utility slots may all be occupied. Replace one utility
	# with a catalogue cabin in this detached unit-test loadout only.
	slots[slot_index]={"item_id":cabin_id,"category":category,"slot":slot_index-offset,"quantity":1}
	equipment._items[cabin_id]={"category":category,"subtype":20}
	equipment._state.loadout.equipment_ids=[]
	for slot in slots:
		if slot!=null:equipment._state.loadout.equipment_ids.append(slot.item_id)
	equipment._state.prices.installed[slot_index]={"item_id":cabin_id,"unit_price":equipment._completion_prices[cabin_id]}
	station._state.loadout=equipment.snapshot().loadout
	return station

func verify_passengers(bindings: RefCounted,cat: RefCounted,original: RefCounted,passenger: RefCounted,pirate: RefCounted) -> void:
	var cabins:=Contracts.cabin_catalogue(cat,bindings.early_contracts.acceptance)
	var station:=cabin_fixture(bindings,cat,original)
	if station==null:return
	var cabin_id: int=cabins.keys()[0]
	if not station.open_contracts(bindings,cat) or not station.register_contract_offer(0,passenger) or not station.register_contract_offer(1,pirate):check(false,station.error);return
	var before: Dictionary=station.snapshot()
	var preview: Dictionary=station.contract_preview(0)
	check(preview.can_accept and preview.passenger_capacity==cabins[cabin_id] and preview.passenger_places==3,"An installed cabin did not supply its catalogue places")
	check(station.accept_contract(0) and station.snapshot().contracts.passengers==3 and station.snapshot().cargo==before.cargo,"Passenger acceptance changed cargo tonnage or loaded the wrong count")
	check(station.accept_contract(1,true) and station.snapshot().contracts.passengers==0 and station.snapshot().cargo==before.cargo,"Replacing a passenger job failed to unload passengers")

func verify_cargo_merge(bindings: RefCounted,cat: RefCounted,original: RefCounted,courier: RefCounted,pirate: RefCounted) -> void:
	var station: RefCounted=original.fork()
	var equipment: RefCounted=station._equipment
	var hold: Dictionary=equipment.snapshot().cargo
	hold.entries.append({"item_id":116,"quantity":1});hold.used+=1;hold.free_space-=1
	if not equipment.retain_flight_cargo(hold):check(false,equipment.error);return
	station._state.cargo=hold.duplicate(true)
	if not station.open_contracts(bindings,cat) or not station.register_contract_offer(0,courier) or not station.register_contract_offer(1,pirate):check(false,station.error);return
	check(station.accept_contract(0),station.error)
	var merged: Dictionary=station.snapshot().cargo
	check(merged.entries[-1]=={"item_id":116,"quantity":15},"Source ID-only merging changed the existing cargo marker")
	check(station.accept_contract(1,true) and station.snapshot().cargo==merged,"Replacement removed an unmarked cargo row")
	var accepted: Dictionary=equipment.snapshot()
	hold.entries[-1].item_id=0;hold.entries[-1].mission=true
	check(not equipment.retain_flight_cargo(hold) and equipment.snapshot()==accepted,"Arbitrary inventory was accepted as mission cargo")

func verify_rejections(bindings: RefCounted,cat: RefCounted,original: RefCounted) -> void:
	var station: Dictionary=original.snapshot()
	for corruption in ["phase","acknowledgement","identity","story","completion"]:
		var bad:=station.duplicate(true)
		match corruption:
			"phase":bad.phase="conversation"
			"acknowledgement":bad.acknowledged=false
			"identity":bad.binding_id="other"
			"story":bad.mission.kind=4
			"completion":bad.completed_side_missions=4
		var session:=Contracts.new()
		check(not session.configure(bindings,cat,bad,original.equipment_owner(),0.5) and session.snapshot().is_empty(),"Unsupported contract career accepted: "+corruption)
	var rules: Dictionary=bindings.early_contracts.duplicate(true)
	rules.acceptance.initial_credits=1000
	check(not Terms.acceptance_parameters(rules),"A modified initial wallet was accepted as source content")
