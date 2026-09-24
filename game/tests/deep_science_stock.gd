extends "res://tests/base_station_stock.gd"
## Both medal branches are explicit component inputs, never earned achievements.
## A detached fixture adds no capability to the selected immutable content pack.
const DeepScience=preload("res://src/content/deep_science_stock_definitions.gd")

class DetachedBindings extends RefCounted:
	var base_content_id: String
	var binding_id: String
	var source_architecture: String
	var early_contracts: Dictionary
	var deep_science_stock: Dictionary

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected content, bindings, visuals and optional detached stock declarations")
	if args.size() in [3,4]:verify(args)
	print("Deep Science stock: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	if not metadata is Dictionary:check(false,"Missing identified source metadata");return
	var declaration: Variant=bindings.get("deep_science_stock")
	if args.size()==4:
		var detached: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[3]))
		if not detached is Dictionary or detached.get("scope")!="detached_deep_science_stock_component_fixture" or detached.get("base_content_id")!=bindings.base_content_id or detached.get("binding_id")!=bindings.binding_id or detached.get("source_executable_sha256")!=metadata.source_executable_sha256:check(false,"Detached stock proof belongs to another source or pack");return
		declaration=detached.get("deep_science_stock")
	var failure:=DeepScience.validate(declaration,int(metadata.source_executable_bytes),bindings.source_architecture,bindings.arrival_staging,bindings.early_contracts.base_station_stock)
	if not failure.is_empty() or not DeepScience.parameters(declaration):check(false,"Missing verified Deep Science declaration: "+failure);return
	var fixture:=DetachedBindings.new()
	fixture.base_content_id=bindings.base_content_id;fixture.binding_id=bindings.binding_id
	fixture.source_architecture=bindings.source_architecture;fixture.early_contracts=bindings.early_contracts.duplicate(true)
	fixture.deep_science_stock=declaration.duplicate(true)
	check(DeepScience.available(fixture),"The detached declaration is unavailable")
	check(cat.tables.stations[10].system_id==6 and cat.tables.stations[10].fields[2]==10 and cat.tables.systems[6].fields[2]==0,"The source station10 catalogue changed")
	verify_deep_definitions(bindings,fixture,int(metadata.source_executable_bytes))
	verify_deep_draws(fixture,cat)
	verify_deep_populations(bindings,fixture,cat)
	verify_deep_failures(fixture,cat)
	# Existing focused vectors retain fixed ships, duplicate retries, foreign
	# selection, prices and edition-specific appended offers in their source order.
	verify_ships(fixture,cat)
	verify_source_ships(fixture,cat)
	verify_temporary_items(fixture,cat)
	verify_reseed_order(fixture,cat)

func deep_context(gold: bool,cursor: int=23) -> Dictionary:
	var value: Dictionary=SETTINGS.duplicate(true)
	value.station_id=10;value.campaign_cursor=cursor;value.ship_price_percent=0
	value.all_base_medals_gold=gold
	return value

func deep_drawn(bindings: RefCounted,draws: Array,gold: bool) -> RefCounted:
	var stock: RefCounted=drawn_base(bindings,draws)
	stock._deep_science=bindings.deep_science_stock.duplicate(true)
	stock._context=deep_context(gold);stock._system=6;stock._tech=10;stock._faction=0
	return stock

func verify_deep_definitions(original: RefCounted,fixture: RefCounted,source_bytes: int):
	var base: Dictionary=fixture.early_contracts.base_station_stock
	var original_declaration: Dictionary=fixture.deep_science_stock.duplicate(true)
	for key in DeepScience.VALUES:
		var bad: Dictionary=original_declaration.duplicate(true);bad.erase(key)
		check(not DeepScience.parameters(bad),"Incomplete Deep Science parameters accepted: "+key)
	for key in original_declaration.provenance:
		for field in ["offset","bytes"]:
			var bad: Dictionary=original_declaration.duplicate(true);bad.provenance[key][field]+=1
			check(not DeepScience.validate(bad,source_bytes,original.source_architecture,original.arrival_staging,base).is_empty(),"Changed stock source extent accepted: "+key+"/"+field)
	check(not DeepScience.validate(original_declaration,source_bytes,"armv7",original.arrival_staging,base).is_empty(),"Deep Science enabled a deferred architecture")
	var other_base: Dictionary=BaseStock.VALUES if BaseStock.Equal.equal_value(base,BaseStock.MAC_VALUES) else BaseStock.MAC_VALUES
	check(not DeepScience.validate(original_declaration,source_bytes,original.source_architecture,original.arrival_staging,other_base).is_empty(),"Stock proofs were mixed between content layouts")
	fixture.deep_science_stock={}
	check(not DeepScience.available(fixture),"An empty declaration enabled station10")
	fixture.deep_science_stock=original_declaration

func verify_deep_draws(bindings: RefCounted,cat: RefCounted):
	var appended: Array=[[7,1]] if cat.tables.ships.size()==64 else []
	var stock: RefCounted=deep_drawn(bindings,[[6,0]],false)
	stock._context.supernova_owned=true
	check(stock._sample_ships(cat).is_empty(),"Station10 zero-count stock performed extra rolls")
	finished_stock(stock,"station10 false zero count")
	stock=deep_drawn(bindings,[[6,1],[37,8],[37,1]]+appended,false)
	check(stock._sample_ships(cat)==[{"ship_id":1,"faction_id":0,"unit_price":124146}],"The false medal branch bypassed ordinary selection or its excluded ship8")
	finished_stock(stock,"station10 false selection")
	stock=deep_drawn(bindings,[[6,2],[37,1],[100,22],[37,1],[100,22],[37,5],[100,22]]+appended,false)
	check(stock._sample_ships(cat).map(func(row):return row.ship_id)==[1,5],"Station10 duplicate retry skipped ordinary foreign draws")
	finished_stock(stock,"station10 duplicate draws")
	stock=deep_drawn(bindings,appended,true)
	var rows: Array=stock._sample_ships(cat)
	check(rows==[{"ship_id":8,"faction_id":9,"unit_price":cat.tables.ships[8].stats.base_price}],"All-gold stock lost its original ship8 affiliation or applied a local discount")
	finished_stock(stock,"all-gold count and selection consume no draws")
	stock=deep_drawn(bindings,([[7,0]] if cat.tables.ships.size()==64 else [])+[[8,0]],true)
	stock._context.supernova_owned=true
	rows=stock._sample_ships(cat)
	check(rows.map(func(row):return row.ship_id)==([8,62,51] if cat.tables.ships.size()==64 else [8,51]),"The guaranteed ship replaced independent appended offers")
	check(rows.map(func(row):return row.faction_id)==([9,3,0] if cat.tables.ships.size()==64 else [9,0]),"Appended offers lost their own affiliations")
	finished_stock(stock,"all-gold appended draws preserve source order")

func verify_deep_populations(original: RefCounted,fixture: RefCounted,cat: RefCounted):
	var rng:=Random.new();rng.seed_from(917)
	var catalogues: Dictionary=cat.tables.duplicate(true)
	for cursor in [15,16,17,23,24,25,44,45,58,59,83]:
		for owned in [false,true]:
			var same_items: Array=[]
			for gold in [false,true]:
				var context:=deep_context(gold,cursor);context.supernova_owned=owned;context.valkyrie_owned=owned
				var stock:=Stock.new()
				if not stock.prepare(fixture,cat,context,rng.snapshot(),1789423200):check(false,stock.error);return
				var state: Dictionary=stock.snapshot()
				check(state.context==context and state.base_content_id==original.base_content_id and state.binding_id==original.binding_id,"Sampled medal context or pack identity was discarded")
				check(Stock.new().restore(fixture,cat,state),"Station10 stock failed deterministic restoration")
				if gold:
					check(state.items==same_items,"The ship-only medal predicate changed item stock or pre-reseed temporary offers")
					check(not state.ships.is_empty() and state.ships[0].ship_id==8,"The retained true flag lost its guaranteed ship")
				else:
					same_items=state.items
					check(not state.ships.any(func(row):return row.ship_id==8),"Ordinary station10 stock offered the gold-only ship")
	# Adding the optional capability preserves exact existing snapshots, including
	# old eight-field contexts, RNG and original fixed offers at41/78.
	for station in [41,78,98]:
		for cursor in [16,23,24,83]:
			var context:=deep_context(false,cursor);context.erase("all_base_medals_gold");context.station_id=station
			var baseline:=Stock.new();var changed:=Stock.new()
			check(baseline.prepare(original,cat,context,rng.snapshot(),1789423200) and changed.prepare(fixture,cat,context,rng.snapshot(),1789423200),baseline.error+changed.error)
			check(changed.snapshot()==baseline.snapshot(),"The optional station10 declaration changed ordinary stock")
	check(cat.tables==catalogues,"Stock mutated original catalogue prototypes")

func verify_deep_failures(fixture: RefCounted,cat: RefCounted):
	var rng:=Random.new();rng.seed_from(917)
	var stock:=Stock.new()
	check(stock.prepare(fixture,cat,deep_context(true),rng.snapshot(),1789423200),stock.error)
	var retained: Dictionary=stock.snapshot()
	for alteration in [{"all_base_medals_gold":null},{"all_base_medals_gold":0},{"all_base_medals_gold":"false"},{"campaign_cursor":14},{"campaign_cursor":84},{"station_id":11},{"extra":false}]:
		var bad:=deep_context(false);bad.merge(alteration,true)
		check(not stock.prepare(fixture,cat,bad,rng.snapshot(),1789423200) and stock.snapshot()==retained,"Unsupported Deep Science context changed retained stock")
	var missing:=deep_context(false);missing.erase("all_base_medals_gold")
	check(not stock.prepare(fixture,cat,missing,rng.snapshot(),1789423200) and stock.snapshot()==retained,"Missing medal result was guessed")
	var bad: Dictionary=retained.duplicate(true);bad.context.all_base_medals_gold=false
	check(not stock.restore(fixture,cat,bad) and stock.snapshot()==retained,"Changed sampled medal result survived restoration")
	bad=retained.duplicate(true);bad.ships[0].faction_id=0
	check(not stock.restore(fixture,cat,bad) and stock.snapshot()==retained,"Changed gold-ship affiliation survived restoration")
	var declaration: Dictionary=fixture.deep_science_stock
	fixture.deep_science_stock={}
	check(not stock.prepare(fixture,cat,deep_context(false),rng.snapshot(),1789423200) and stock.snapshot()==retained,"Missing optional capability changed retained stock")
	fixture.deep_science_stock=declaration
