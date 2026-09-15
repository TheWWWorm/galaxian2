extends "res://tests/gate_environment.gd"
## Price vectors have synthetic item data and no inventory, wallet or career.
const Prices=preload("res://src/simulation/station_prices.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify_prices(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Station prices: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_prices(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var owner:=Prices.new();var rng:=Random.new();rng.seed_from(17000)
	var lists:={"cargo":null,"installed":[],"stock":[]}
	if not Shopping.available(bindings):
		check(not owner.prepare(bindings,cat,95,lists,rng.snapshot(),[null,100,100]) and owner.snapshot().is_empty(),"Earlier content inferred paid station prices")
		return
	var rules: Dictionary=bindings.mido_travel.ordinary_shopping
	var vectors: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/station_price_vectors.json"))
	for vector in vectors:
		var item:={"minimum":int(vector.low),"maximum":int(vector.high),"origin":0,"maximum_origin":1,"current_system":2,"positions":vector.positions.map(func(p):return Vector2i(int(p[0]),int(p[1])))}
		rng.seed_from(int(vector.seed))
		var result:=owner.quote(item,rules.pricing,rng,int(vector.modifier),vector.special)
		check(result==int(vector.price) and rng.snapshot().state==int(vector.random_state),"Synthetic distance/variation/modifier vector changed: "+str(vector))
	var metadata:=owner.metadata(cat,0,rules.catalogue)
	if metadata.is_empty():check(false,owner.error);return
	check(metadata.minimum==2000 and metadata.maximum==2381 and metadata.origin==8 and metadata.maximum_origin==7,"Item price inputs selected different catalogue properties")
	lists={"cargo":[{"item_id":0,"unit_price":2100}],"installed":[null,{"item_id":0,"unit_price":2100}],"stock":[{"item_id":0,"unit_price":2100,"quantity":3},{"item_id":22,"unit_price":0,"quantity":1},{"item_id":55,"unit_price":-1,"quantity":2}]}
	var before:=lists.duplicate(true);var initial:=rng.snapshot()
	if not owner.prepare(bindings,cat,95,lists,initial,[100,101,102]):check(false,owner.error);return
	var accepted:=owner.snapshot();var quotes: Dictionary=accepted.lists
	check(lists==before and rng.snapshot()==initial,"Quoting changed a caller's lists or random owner")
	check(quotes.cargo[0].unit_price==quotes.installed[1].unit_price and quotes.cargo[0].unit_price==quotes.stock[0].unit_price,"Price lists failed to reseed at the same station or consumed a draw for a null slot")
	check(quotes.stock[0].quantity==3 and quotes.stock[1]==before.stock[1] and quotes.stock[2]==before.stock[2],"Price refresh changed quantities or nonpositive quotes")
	check(accepted.draw_calls=={"cargo":1,"installed":1,"stock":1},"Repricing used the wrong per-list draw order")
	var reseeded:=Random.new();reseeded.seed_from(102)
	check(accepted.random==reseeded.snapshot(),"Repricing restored the old stream instead of the final sampled Unix reseed")
	var second:=Prices.new()
	check(second.prepare(bindings,cat,95,lists,{"state":0},[999,999,999]) and second.snapshot().lists==quotes,"Random state or wall time changed station-seeded prices")
	var absent:={"cargo":null,"installed":null,"stock":null}
	check(second.prepare(bindings,cat,95,absent,initial,[null,null,null]) and second.snapshot().random==initial,"Null lists reseeded the shared random stream")
	absent.installed=[];reseeded.seed_from(123)
	check(second.prepare(bindings,cat,95,absent,initial,[null,123,null]) and second.snapshot().random==reseeded.snapshot(),"An allocated empty list skipped its source reseed")
	check(second.prepare(bindings,cat,95,lists,initial,[100,101,102],0,true) and second.snapshot().draw_calls=={"cargo":0,"installed":0,"stock":0},"Special markup consumed ordinary variation draws")
	var all:=[]
	for item in cat.tables.items:
		var low: int=item.properties[7];var high: int=item.properties[8]
		all.append({"item_id":int(item.id),"unit_price":low+(high-low)/2,"quantity":1})
	for station in [70,71,72,73,74,95,96,97,98,99]:
		check(second.prepare(bindings,cat,station,{"cargo":null,"installed":[],"stock":all},initial,[null,100,100]),"An original item or supported station lost its price fields: "+second.error)
		if failures:return
		check(second.snapshot().lists.stock.size()==cat.tables.items.size(),"Repricing dropped original catalogue rows")
	for destination in [-1,56,108,135,95.0]:
		check(not owner.prepare(bindings,cat,destination,lists,initial,[100,101,102]) and owner.snapshot()==accepted,"Unsupported location changed accepted prices")
	for bad_time in [[null,101,102],[100,101],[100,-1,102],[100,101.0,102]]:
		check(not owner.prepare(bindings,cat,95,lists,initial,bad_time) and owner.snapshot()==accepted,"Malformed time samples changed accepted prices")
	for change in [{"unit_price":1.5},{"quantity":-1},{"item_id":233},{"extra":true}]:
		var bad:=lists.duplicate(true);bad.stock[0].merge(change,true)
		check(not owner.prepare(bindings,cat,95,bad,initial,[100,101,102]) and owner.snapshot()==accepted,"Malformed item quote partially repriced the owner")
	var origin: Variant=cat.tables.items[0].properties[4]
	cat.tables.items[0].properties[4]=-1
	check(not owner.prepare(bindings,cat,95,lists,initial,[100,101,102]) and owner.snapshot()==accepted,"An invalid price origin changed accepted lists")
	cat.tables.items[0].properties[4]=origin
	var copied:=owner.snapshot();copied.lists.stock.clear()
	check(owner.snapshot()==accepted,"A caller changed the accepted quotes")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in Shopping.SPANS:
		var bad:=bindings.mido_travel.duplicate(true);bad.provenance.erase(key)
		check(not Travel.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing shopping proof was accepted: "+key)
