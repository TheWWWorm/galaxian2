extends SceneTree
## Detached component cases. No career, save or earned mission is manufactured.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Preparation=preload("res://src/simulation/campaign_preparation.gd")
const Definitions=preload("res://src/content/kappa_preparation_definitions.gd")
const Visit=preload("res://src/simulation/campaign_visit.gd")
const Navigation=preload("res://src/content/free_navigation_definitions.gd")
const Prices=preload("res://src/simulation/station_prices.gd")
const Stock=preload("res://src/simulation/station_stock.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Campaign preparation: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not library.select_language("gb"):
		check(false,library.error+bindings.error+cat.error);return
	var rules: Dictionary=Definitions.VALUES
	var preparation:=Preparation.new()
	check(preparation.station_stock(55,[]).is_empty() and preparation.installed_equipment({},true).is_empty(),"Unconfigured preparation accepted state")
	if not Definitions.available(bindings):
		check(not preparation.configure(bindings,cat,20,rules.fitting.mission),"Older bindings enabled Kappa preparation")
		check(not Visit.new().configure(bindings,library,19,rules.visit.mission),"Older bindings enabled Kappa's conversation")
		return
	check(preparation.configure(bindings,cat,20,rules.fitting.mission),preparation.error)
	var source: Dictionary=cat.tables.duplicate(true)
	var original:=[{"item_id":42,"quantity":3,"unit_price":190},{"item_id":41,"quantity":2,"unit_price":70},{"item_id":41,"quantity":4,"unit_price":71}]
	var before: Array=original.duplicate(true)
	var result:=preparation.station_stock(55,original)
	check(result.get("applied",false) and result.items==[{"item_id":42,"quantity":3,"unit_price":190},{"item_id":41,"quantity":12,"unit_price":0},{"item_id":41,"quantity":4,"unit_price":0}],"Reserve did not merge into the first row and reprice all matching items")
	check(original==before and cat.tables==source,"Reserve changed caller-owned stock or catalogue prototypes")
	check(preparation.station_stock(56,original)=={"applied":false,"items":original},"Another station received Kappa's reserve")
	check(preparation.station_stock(55,[]).items==[{"item_id":41,"quantity":10,"unit_price":0}],"Empty market omitted its ten free bombs")
	check(preparation.station_stock(55,result.items).items[1].quantity==22,"Another station-entry call invented an unsupported once-only flag")
	var prices:=Prices.new()
	check(prices.prepare(bindings,cat,55,{"cargo":null,"installed":null,"stock":result.items},{"state":123},[null,null,1789100000]),prices.error)
	check(prices.snapshot().lists.stock[1].unit_price==0 and prices.snapshot().lists.stock[2].unit_price==0 and prices.snapshot().draw_calls.stock==1,"Hangar pricing changed free EMP prices or consumed extra draws")
	for invalid in [[{"item_id":41,"quantity":2147483640,"unit_price":1}],[{"item_id":41,"quantity":0,"unit_price":1}],[{"item_id":41,"quantity":1,"unit_price":-1}],[{"item_id":41,"quantity":1}],null]:
		check(preparation.station_stock(55,invalid).is_empty(),"Invalid or overflowing stock was accepted")
	check(preparation.station_stock(-1,original).is_empty() and preparation.station_stock(55.5,original).is_empty(),"Invalid location supplied mission stock")
	# Normal generation can omit EMP entirely. The adjunct preserves its stream.
	var stock:=Stock.new()
	var context:={"station_id":55,"campaign_cursor":20,"difficulty":1.0,"valkyrie_owned":false,"supernova_owned":false,"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
	check(stock.prepare(bindings,cat,context,{"state":1},1789100000),stock.error)
	var sampled:=stock.snapshot()
	check(sampled.items.all(func(row):return row.item_id not in [41,42,43]),"The original empty-EMP stock case changed")
	result=preparation.station_stock(55,sampled.items)
	check(result.items.any(func(row):return row.item_id==41 and row.quantity==10 and row.unit_price==0),"Authored reserve was omitted after real stock sampling")
	check(stock.snapshot()==sampled,"Authored reserve consumed random state or replaced the sampled stock")
	var loadout:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":56,"slots":[null]}
	check(not preparation.installed_equipment(loadout,true).ready,"An empty installed slot completed preparation")
	for id in [41,42,43]:
		loadout.slots=[null,{"item_id":id,"quantity":1,"category":1,"slot":0}]
		check(preparation.installed_equipment(loadout,true)=={"ready":true,"slot":1,"item_id":id},"An installed EMP subtype failed the docked predicate")
		check(not preparation.installed_equipment(loadout,false).ready,"Flight completed station preparation")
	loadout.slots=[{"item_id":2,"quantity":1,"category":0,"slot":0}]
	loadout.cargo=[{"item_id":41,"quantity":10}]
	check(not preparation.installed_equipment(loadout,true).ready,"Cargo-only bombs or a primary weapon completed preparation")
	var kept: Dictionary=loadout.duplicate(true)
	for bad in [{"item_id":41,"quantity":0,"category":1,"slot":0},{"item_id":41,"quantity":1,"category":0,"slot":0},{"item_id":cat.tables.items.size(),"quantity":1,"category":1,"slot":0}]:
		var changed: Dictionary=loadout.duplicate(true);changed.slots=[bad]
		check(preparation.installed_equipment(changed,true).is_empty(),"Malformed installed equipment completed preparation")
	var foreign: Dictionary=loadout.duplicate(true);foreign.binding_id="another-content-pack"
	check(preparation.installed_equipment(foreign,true).is_empty(),"Another content identity completed preparation")
	check(loadout==kept and cat.tables==source,"Inspection changed the caller's inventory or catalogue")
	for cursor in [19,21,20.5]:check(not preparation.configure(bindings,cat,cursor,rules.fitting.mission),"Another campaign state enabled EMP preparation")
	check(preparation.station_stock(55,original).items[1].quantity==12,"Rejected configuration replaced retained rules")
	verify_visit(bindings,library,rules.visit)
	check(not Navigation.ordinary_departure_at(bindings,19,rules.visit.mission,55),"Preparation declarations unlocked the incomplete rescue")

func verify_visit(bindings: RefCounted,library: RefCounted,rules: Dictionary) -> void:
	var visit:=Visit.new()
	check(visit.configure(bindings,library,19,rules.mission),visit.error)
	for poll in [[55,10000,5001],[55,10001,5000],[56,10001,5001]]:
		check(visit.poll(poll[0],poll[1],poll[2]) and not visit.snapshot().dialogue.visible,"Kappa visit ignored its original clock or location")
	check(visit.poll(55,10001,5001) and visit.snapshot().dialogue.visible,visit.error)
	for event in rules.events:
		var line: Dictionary=visit.snapshot().dialogue
		check(line.text_id==event.text_id and line.voice_event_id==event.voice_event_id and line.speaker_id==event.speaker_id,"Kappa dialogue changed its source ordering")
		check(visit.transition().is_empty(),"Kappa advanced before final acknowledgement")
		check(visit.navigate("next"),visit.error)
	var receipt:=visit.transition()
	check(receipt.from_cursor==19 and receipt.campaign_cursor==20 and receipt.mission==rules.next_mission and receipt.reward_credits==0,"Kappa acknowledgement changed its declared result")
	for language in library.manifest.languages:
		check(library.select_language(language) and Visit.new().configure(bindings,library,19,rules.mission),"Kappa visit lacks localized text or speakers: "+language)

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
