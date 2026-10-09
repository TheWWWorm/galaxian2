extends SceneTree
## Detached quoted jobs and cargo arrangements isolate station transactions.
## Generated contacts, real shopping and travel are covered by the application.
var checks:=0
var failures:=0

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected matching original content, bindings and visuals")
	print("Purchase contract: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library=load("res://src/content/library.gd").new();var bindings=load("res://src/content/resource_bindings.gd").new();var cat=load("res://src/content/catalogues.gd").new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not library.select_language("gb"):check(false,library.error+bindings.error+cat.error);return
	var file=load("res://src/simulation/station_save_file.gd").new();var archive=load("res://src/simulation/station_archive.gd").new()
	var station: RefCounted=archive.restore(bindings,cat,library,file.load_document(OS.get_environment("GOF2_SOURCE_SAVE"),bindings,cat,library))
	if station==null:check(false,file.error+archive.error);return
	var source: Dictionary=station.snapshot();var contracts: RefCounted=station.contract_owner().fork()
	verify_requested_offer(station,bindings,cat,library)
	verify_wingman_once(station,bindings,cat,library)
	if failures:return
	var quote:=quoted_fixture(bindings,cat,contracts,118)
	if quote.is_empty():return
	var quotation=load("res://src/simulation/contract_offer.gd")
	for item in cat.tables.items.size():
		if quotation.collection_item(bindings.early_contracts,cat,item).is_empty():continue
		var eligible:=quoted_fixture(bindings,cat,contracts,item)
		check(not eligible.is_empty() and contracts.acceptance_supported(bindings.early_contracts,source.campaign_cursor,eligible,bindings),"An eligible catalogue item produced an unsupported Purchase quote")
	contracts._state.offers[0]={"consumed":false,"offer":quote}
	var equipment: RefCounted=contracts.accept(0,station.equipment_owner(),true,bindings)
	if equipment==null:check(false,contracts.error);return
	var accepted: Dictionary=contracts.snapshot();var inventory: Dictionary=equipment.snapshot()
	check(accepted.mission==quote.mission and accepted.passengers==0 and inventory.cargo==source.cargo,"Purchase acceptance supplied cargo or passengers")
	check(contracts.active_mission_for(source.loadout.station_id,bindings).is_empty(),"Purchase selected a combat cast at its hand-in station")
	check(contracts.poll_station(equipment,bindings) and contracts.snapshot()==accepted,"An empty hold completed the job")
	var context: Dictionary=contracts.free_flight_context(bindings,int(source.loadout.station_id))
	check(not context.is_empty() and context.mission.is_empty() and context.side_mission==quote.mission,"The unfinished Purchase job blocked ordinary departure")
	check(load("res://src/content/ordinary_contracts_definitions.gd").extra_count(bindings,context)==0,"Purchase added delivery pirates")
	var panel=load("res://src/presentation/lounge_panel.gd").new()
	panel._library=library;panel._bindings=bindings;panel._catalogues=cat
	var brief: String=panel.format_job(library.strings[quote.mission.briefing_text_id],quote.mission)
	check(brief.contains(library.strings[int(bindings.station_equipment.item_text_offset)+118]) and not brief.contains("#"),"The Purchase briefing omitted its requested item or left placeholders")
	panel.free()
	var quantity:=int(quote.mission.quantity)
	for amounts in [[quantity-1],[quantity-1,1]]:
		var short:=cargo_fixture(equipment,118,amounts)
		check(contracts.poll_station(short,bindings) and contracts.snapshot()==accepted,"Insufficient individual cargo rows completed the job")
	var ready:=cargo_fixture(equipment,118,[quantity+2])
	var elsewhere: RefCounted=ready.fork();elsewhere._state.loadout.station_id=36
	check(contracts.poll_station(elsewhere,bindings) and contracts.snapshot()==accepted,"The right cargo paid at the wrong station")
	var branch: RefCounted=contracts.fork()
	check(branch.poll_station(ready,bindings),branch.error)
	var pending: Dictionary=branch.snapshot()
	check(not pending.pending_result.is_empty() and pending.credits==accepted.credits and pending.completed_side_missions==accepted.completed_side_missions,"The result failed to open or paid before Close")
	check(branch.poll_station(ready,bindings) and branch.snapshot()==pending,"Repeated result polling changed standing twice")
	check(branch.acknowledge_delivery_result(equipment,bindings)==null and branch.snapshot()==pending,"A stale inventory received the prepared payment")
	var paid_inventory: RefCounted=branch.acknowledge_delivery_result(ready,bindings)
	if paid_inventory==null:check(false,branch.error);return
	var paid: Dictionary=branch.snapshot();var hold: Dictionary=paid_inventory.snapshot().cargo
	check(paid.credits==accepted.credits+quote.mission.reward+quote.mission.bonus and paid.completed_side_missions==accepted.completed_side_missions+1,"The quoted payment or completion count was wrong")
	check(paid.progress.other_score==accepted.progress.other_score+2 and paid.campaign_cursor==accepted.campaign_cursor,"Purchase lost its completion score or advanced the story")
	check(paid.delivery_statistics==accepted.delivery_statistics and paid.passengers==0,"Purchase counted goods as courier cargo or passengers")
	check(hold.entries==inventory.cargo.entries+[{"item_id":118,"quantity":2}] and hold.used==inventory.cargo.used+2 and paid_inventory.cargo_cache_valid(),"Delivery removed surplus or unrelated goods, or left stale capacity")
	check(paid_inventory.snapshot().prices.cargo==ready.snapshot().prices.cargo,"Partial delivery lost retained row prices")
	check(paid.mission.is_empty() and paid.accepted_contact.is_empty() and paid.pending_result.is_empty(),"The paid Purchase job remained active")
	check(branch.acknowledge_delivery_result(paid_inventory,bindings)==null and branch.poll_station(paid_inventory,bindings) and branch.snapshot()==paid,"The same hand-in paid twice")
	check(contracts.snapshot()==accepted and equipment.snapshot()==inventory and ready.snapshot().cargo.entries.back().quantity==quantity+2,"Staged settlement mutated its parent career or inventories")
	var split:=cargo_fixture(equipment,118,[1,quantity])
	var split_branch: RefCounted=contracts.fork()
	check(split_branch.poll_station(split,bindings),split_branch.error)
	var split_paid: RefCounted=split_branch.acknowledge_delivery_result(split,bindings)
	check(split_paid!=null and split_paid.snapshot().cargo.entries==inventory.cargo.entries+[{"item_id":118,"quantity":quantity}] and split_paid.cargo_cache_valid(),"Delivery lost the original first-matching-row removal behavior")
	var shopping: RefCounted=contracts.fork()
	var market: RefCounted=shopping.open_shopping(bindings,cat,ready,[1789102000,1789102000,1789102000],library)
	if market==null:check(false,shopping.error);return
	check(shopping.poll_station(market,bindings),shopping.error)
	var displayed: Dictionary=market.snapshot()
	var delivered_market: RefCounted=shopping.acknowledge_delivery_result(market,bindings)
	if delivered_market==null:check(false,shopping.error);return
	var delivered: Dictionary=delivered_market.snapshot()
	check(delivered.ordinary_shopping_open and delivered.market_rows.filter(func(row):return row.item_id==118)[0].owned==2 and delivered.cargo.entries.any(func(row):return row.item_id==118 and row.quantity==2),"Open-shop hand-in left stale market quantities")
	check(delivered.stock==displayed.stock and delivered_market.cargo_cache_valid() and market.snapshot()==displayed,"Hand-in sold goods into stock or mutated the displayed parent quote")
	var bought_again: RefCounted=shopping.transact_shopping(bindings,cat,delivered_market,"buy",118)
	check(bought_again!=null and bought_again.snapshot().cargo.entries.any(func(row):return row.item_id==118 and row.quantity==3),"Trading after hand-in restored the delivered goods")
	var replacement: RefCounted=contracts.fork()
	replacement._state.offers[3]={"consumed":false,"offer":quoted_fixture(bindings,cat,contracts,125)}
	var replaced: RefCounted=replacement.accept(3,ready,true,bindings)
	check(replaced!=null and replaced.snapshot().cargo==ready.snapshot().cargo and replacement.snapshot().completed_side_missions==accepted.completed_side_missions and replacement.snapshot().credits==accepted.credits,"Replacing Purchase deleted owned goods or paid the discarded job")
	check(station.snapshot()==source,"Detached Purchase checks changed the earned station")

## Commander (SpaceLounge::onKeyPress, offer 6: Agent::setOfferAccepted): a
## wingman captain is hired once, also after his crew has gone (#23).
func verify_wingman_once(station: RefCounted,bindings: RefCounted,cat: RefCounted,library: RefCounted) -> void:
	var captains: Array=station.snapshot().contracts.population.contacts.filter(func(contact):return contact.role==6)
	if captains.is_empty():print("This earned station has no wingman captain; Commander checks skipped");return
	var id:=int(captains[0].contact_id);var branch: RefCounted=station.fork()
	var funded: RefCounted=branch._contracts.fork();funded._state.credits=10000000;branch._contracts=funded
	if not branch.inspect_contract_contact(id,bindings):check(false,branch.error);return
	var quote: Dictionary=branch.wingman_preview(id,bindings)
	check(quote.get("can_accept",false) and not quote.get("consumed",false),"The earned captain cannot be hired: "+branch.error)
	if not branch.hire_lounge_wingmen(id,bindings):check(false,branch.error);return
	var hired: Dictionary=branch.snapshot().contracts.wingmen
	var gone: RefCounted=branch._contracts.fork();gone._state.wingmen={"hired_total":hired.hired_total,"active":{}};branch._contracts=gone
	var again: Dictionary=branch.wingman_preview(id,bindings)
	check(again.get("consumed",false) and not again.get("can_accept",true) and not branch.hire_lounge_wingmen(id,bindings) and branch.snapshot().contracts.wingmen.hired_total==hired.hired_total,"A wingman captain was hired twice")
	var file=load("res://src/simulation/station_save_file.gd").new();var archive=load("res://src/simulation/station_archive.gd").new()
	var path:="user://wingmen-hired.gof2save"
	if not file.save(path,branch,bindings,cat,library):check(false,file.error);return
	var restored: RefCounted=archive.restore(bindings,cat,library,file.load_document(path,bindings,cat,library))
	check(restored!=null and restored.wingman_preview(id,bindings).get("consumed",false),"Resume forgot the hired captain: "+archive.error)

func verify_requested_offer(station: RefCounted,bindings: RefCounted,cat: RefCounted,library: RefCounted) -> void:
	var original: Dictionary=station.snapshot()
	var people: Array=original.contracts.population.contacts.filter(func(contact):return contact.role==5)
	check(not people.is_empty(),"The earned station has no original goods-request contact")
	if people.is_empty():return
	var id:=int(people[0].contact_id);var branch: RefCounted=station.fork()
	check(not original.contracts.offers.has(id),"The untouched contact already contains a requested quote")
	if not branch.inspect_contract_contact(id,bindings):check(false,branch.error);return
	var inspected: Dictionary=branch.snapshot();var quote: Dictionary=inspected.contracts.offers[id].offer
	check(quote.mission.kind==8 and quote.mission.station_id==original.loadout.station_id and quote.context.rank==original.contracts.rank,"Inspection lost the local goods request or current rank")
	check(inspected.contracts.population==original.contracts.population and inspected.cargo==original.cargo and inspected.contracts.mission==original.contracts.mission,"Inspection rewrote the generated population or changed the accepted job")
	check(branch.inspect_contract_contact(id,bindings),branch.error)
	var revisited: Dictionary=branch.snapshot()
	check(revisited.contracts.conversations==int(inspected.contracts.conversations)+1,"Talking to the contact again did not count toward the Chatterbox medal")
	revisited.contracts.conversations=inspected.contracts.conversations
	check(revisited==inspected,"Inspecting the same contact rerolled its goods or reward")
	inspected=branch.snapshot()
	var file=load("res://src/simulation/station_save_file.gd").new();var archive=load("res://src/simulation/station_archive.gd").new()
	var path:="user://purchase-request.gof2save"
	if not file.save(path,branch,bindings,cat,library):check(false,file.error);return
	var document: Dictionary=file.load_document(path,bindings,cat,library)
	var restored: RefCounted=archive.restore(bindings,cat,library,document)
	if restored==null:check(false,file.error+archive.error);return
	check(restored.snapshot().contracts.offers==inspected.contracts.offers,"Resume lost or rerolled an inspected, unaccepted request")
	if not restored.accept_contract(id,true,bindings):check(false,restored.error);return
	var accepted: Dictionary=restored.snapshot()
	if not file.save(path,restored,bindings,cat,library):check(false,file.error);return
	document=file.load_document(path,bindings,cat,library)
	var resumed: RefCounted=archive.restore(bindings,cat,library,document)
	check(resumed!=null and resumed.snapshot().contracts.accepted_contact==accepted.contracts.accepted_contact and resumed.snapshot().contracts.mission==quote.mission,"Resume lost the accepted requested job")
	var altered:=document.duplicate(true)
	for location in altered.locations.locations:
		if location.station_id==original.loadout.station_id:location.requested_offers[id].offer.mission.quantity+=1
	check(archive.restore(bindings,cat,library,altered)==null,"Archive entry admitted changed requested goods")
	check(station.snapshot()==original,"Inspecting or accepting a request mutated the parent station")

func quoted_fixture(bindings: RefCounted,cat: RefCounted,contracts: RefCounted,item_id: int) -> Dictionary:
	var state: Dictionary=contracts.snapshot();var context: Dictionary=state.accepted_contact.offer.context.duplicate(true)
	context.station_id=state.station_id;context.campaign_cursor=state.campaign_cursor;context.rank=state.rank;context.reputation=state.reputation
	var quote=load("res://src/simulation/contract_offer.gd").new()
	if not quote.configure(bindings,cat,context,{"kind":8,"difficulty_index":0,"parameter_index":item_id,"quantity_index":2,"destination_station_id":state.station_id}):check(false,quote.error);return {}
	return quote.snapshot()

func cargo_fixture(equipment: RefCounted,item_id: int,amounts: Array) -> RefCounted:
	var result: RefCounted=equipment.fork();var hold: Dictionary=result.snapshot().cargo
	for quantity in amounts:hold.entries.append({"item_id":item_id,"quantity":quantity});hold.used+=quantity
	hold.free_space=hold.capacity-hold.used
	check(result.retain_flight_cargo(hold),result.error)
	return result
