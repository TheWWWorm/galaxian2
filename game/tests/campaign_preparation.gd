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
const Travel=preload("res://src/content/mido_travel_definitions.gd")
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
	rules=bindings.mido_travel.kappa_preparation
	verify_source_layouts(bindings,args[1])
	verify_departure(bindings,cat,rules)
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

func verify_source_layouts(bindings: RefCounted,pack: String) -> void:
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var original: Dictionary=bindings.mido_travel.duplicate(true)
	var alternate: bool=original.kappa_preparation.visit.events[0].text_id==Definitions.MAC_VALUES.visit.events[0].text_id
	var origin:=int(bindings.arrival_staging.provenance.actor.offset)
	for name in ["kappa_preparation","emp_bombs","kappa_rescue","kappa_fighters","kappa_lifecycle","secondary_ownership","kappa_return","kappa_outcome","kappa_departure"]:
		if not original.has(name):continue
		var reader: Script=load("res://src/content/"+name+"_definitions.gd")
		var constants:=reader.get_script_constant_map()
		if constants.has("MAC_VALUES"):
			var mixed:=original.duplicate(true);mixed[name]=constants.VALUES if alternate else constants.MAC_VALUES
			check(not Travel.parameters(mixed),"A child from the other Mac source was accepted: "+name)
		var changed:=original.duplicate(true)
		var spans: Dictionary=constants.SPANS if alternate else constants.MAC_SPANS
		for key in spans:changed.provenance[key]={"offset":origin+int(spans[key][0]),"bytes":int(spans[key][1])}
		check(not Travel.validate(changed,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Foreign child proofs were accepted: "+name)
	check(bindings.mido_travel==original,"Variant checks changed the retained declarations")

func verify_departure(bindings: RefCounted,cat: RefCounted,rules: Dictionary) -> void:
	var owner:=Preparation.new()
	check(owner.departure_equipment({}).is_empty(),"Unconfigured launch inspection accepted equipment")
	if not Preparation.Departure.available(bindings):
		check(not owner.configure_departure(bindings,cat,21,rules.fitting.next_mission),"A retained pack without launch declarations enabled rescue departure")
		return
	var loadout:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":55,"slots":[null]}
	var blocked:={"allowed":false,"text_id":520};var allowed:={"allowed":true,"text_id":-1}
	check(owner.configure_departure(bindings,cat,20,rules.fitting.mission),owner.error)
	check(owner.departure_equipment(loadout)==blocked,"The unacknowledged fitting mission allowed departure from its target station")
	loadout.slots=[null,{"item_id":41,"quantity":1,"category":1,"slot":0}]
	check(owner.departure_equipment(loadout)==blocked,"Installed equipment bypassed the fitting lesson acknowledgement")
	loadout.station_id=56
	check(owner.departure_equipment(loadout)==allowed,"The preparation launch gate incorrectly applied at another station")
	loadout.station_id=55
	check(owner.configure_departure(bindings,cat,21,rules.fitting.next_mission),owner.error)
	check(owner.station_stock(55,[]).is_empty(),"A rescue departure supplied another fitting-mission reserve")
	var expected:=[41,42,43] if rules.visit.events[0].text_id==Definitions.MAC_VALUES.visit.events[0].text_id else [41]
	for id in [41,42,43]:
		for count in [1,3]:
			loadout.slots=[null,{"item_id":id,"quantity":count,"category":1,"slot":0}]
			check(owner.installed_equipment(loadout,true).ready,"An EMP model failed the independent subtype-based fitting predicate")
			check(owner.departure_equipment(loadout)==(allowed if id in expected else blocked),"Departure lost its source-specific installed item requirement: "+str(id))
			check(owner.fork().departure_equipment(loadout)==owner.departure_equipment(loadout),"Forking changed source-specific departure requirements")
	loadout.slots=[null];loadout.cargo=[{"item_id":41,"quantity":10}]
	check(owner.departure_equipment(loadout)==blocked,"Cargo-only ammunition passed the installed requirement")
	loadout.station_id=56
	check(owner.departure_equipment(loadout)==allowed,"The rescue launch gate incorrectly applied away from its target station")
	loadout.station_id=55
	for id in [2,40,55]:
		loadout.slots=[{"item_id":id,"quantity":1,"category":int(cat.tables.items[id].arrays[2][3]),"slot":0}]
		check(owner.departure_equipment(loadout)==blocked,"An unrelated installed item satisfied the EMP requirement")
	loadout.slots=[null,{"item_id":41,"quantity":1,"category":1,"slot":0}]
	var before:=loadout.duplicate(true)
	for invalid in [{"item_id":41,"quantity":0,"category":1,"slot":0},{"item_id":41,"quantity":1,"category":0,"slot":0},{"item_id":cat.tables.items.size(),"quantity":1,"category":1,"slot":0}]:
		var changed:=loadout.duplicate(true);changed.slots=[invalid]
		check(owner.departure_equipment(changed).is_empty(),"Malformed installed inventory enabled departure")
	var foreign:=loadout.duplicate(true);foreign.binding_id="foreign"
	check(owner.departure_equipment(foreign).is_empty(),"A foreign inventory passed the launch requirement")
	for cursor in [19,22,21.5]:check(not owner.configure_departure(bindings,cat,cursor,rules.fitting.next_mission),"Another campaign cursor enabled the rescue launch rule")
	var wrong: Dictionary=rules.fitting.next_mission.duplicate(true);wrong.reward=1
	check(not owner.configure_departure(bindings,cat,21,wrong),"A different mission enabled the rescue launch rule")
	check(owner.departure_equipment(loadout)==allowed and loadout==before,"Rejected inspection changed retained rules or the caller's inventory")

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
	check(receipt.from_cursor==19 and receipt.campaign_cursor==20 and Travel.Equal.equal_value(receipt.mission,rules.next_mission) and receipt.reward_credits==0,"Kappa acknowledgement changed its declared result")
	for language in library.manifest.languages:
		check(library.select_language(language) and Visit.new().configure(bindings,library,19,rules.mission),"Kappa visit lacks localized text or speakers: "+language)
		check(library.strings.size()>520 and library.strings[520] is String and not library.strings[520].is_empty(),"The original launch refusal is unavailable in "+language)

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
