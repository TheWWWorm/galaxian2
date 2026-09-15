extends "res://tests/station_generation.gd"
## Source boundary draws are deliberate fixtures; station populations below do
## not imply travel, a new game unlock, or a completed shopping transaction.
const BaseStock=preload("res://src/content/base_station_stock_definitions.gd")

func verify(args: PackedStringArray):
	super.verify(args)
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var rng:=Random.new();rng.seed_from(917)
	var context: Dictionary=SETTINGS.duplicate(true)
	context.station_id=98;context.campaign_cursor=15;context.ship_price_percent=0
	if not BaseStock.available(bindings):
		check(not Stock.new().prepare(bindings,cat,context,rng.snapshot(),1789423200),"Older packs enabled Alioth stock")
		return
	verify_ships(bindings,cat)
	verify_temporary_items(bindings,cat)
	verify_reseed_order(bindings,cat)
	verify_stock_proof(bindings,args[1])
	var catalogues: Dictionary=cat.tables.duplicate(true)
	var populations:=0;var ship_offers:=0;var alioth:={};var empty_items:=[]
	var stations:=[]
	for station in cat.tables.stations:
		if station.id<=99 and station.id!=10 and station.system_id<=21:stations.append(station.id)
	for cursor in [15,16,17,24,25,58,59,83]:
		context.campaign_cursor=cursor
		for station in stations:
			context.station_id=station
			context.supernova_owned=(station%2)==0
			context.valkyrie_owned=(station%3)==0
			context.difficulty=1.5 if cursor==83 else 0.5
			var stock:=Stock.new()
			if not stock.prepare(bindings,cat,context,rng.snapshot(),1789423200+station):check(false,stock.error);return
			var state: Dictionary=stock.snapshot();populations+=1;ship_offers+=state.ships.size()
			check(state.draw_calls>0,"A supported station skipped stock sampling")
			if state.items.is_empty():empty_items.append([station,cursor,cat.tables.stations[station].fields[2],state.draw_calls])
			check(Stock.new().restore(bindings,cat,state),"Ordinary stock failed deterministic restoration")
			for item in state.items:
				if item.item_id>=132 and item.item_id<=153:check(item.item_id==132+cat.tables.stations[station].system_id,"A station sold another system's local commodity")
			if cursor==15 and station==98:alioth=state
	check(ship_offers>0 and not alioth.is_empty(),"The base station generator did not reach Alioth")
	check(cat.tables==catalogues,"Stock changed source catalogue prototypes")
	var retained:=Stock.new();check(retained.restore(bindings,cat,alioth),retained.error)
	for change in [{"campaign_cursor":84},{"campaign_cursor":14},{"station_id":10},{"station_id":100},{"station_id":108},{"ship_price_percent":null}]:
		var bad: Dictionary=alioth.context.duplicate(true);bad.merge(change,true)
		check(not retained.prepare(bindings,cat,bad,rng.snapshot(),1789423200) and retained.snapshot()==alioth,"Unsupported context replaced retained stock")
	var changed: Dictionary=alioth.duplicate(true)
	changed.ships.append({"ship_id":8,"faction_id":9,"unit_price":0})
	check(not retained.restore(bindings,cat,changed) and retained.snapshot()==alioth,"A fabricated ship offer survived restoration")
	var old: Dictionary=bindings.early_contracts.duplicate(true)
	bindings.early_contracts.erase("base_station_stock")
	check(not retained.prepare(bindings,cat,alioth.context,rng.snapshot(),1) and retained.snapshot()==alioth,"Missing capability replaced retained stock")
	bindings.early_contracts=old
	print("Base stock: %d populations across %d original stations; %d ship offers"%[populations,stations.size(),ship_offers])
	print("Empty item samples [station,cursor,tech,draws]: ",empty_items)

func drawn_base(bindings: RefCounted,draws: Array) -> RefCounted:
	var stock: RefCounted=drawn_stock(bindings,draws)
	stock._base=bindings.early_contracts.base_station_stock.duplicate(true)
	stock._context.station_id=98;stock._context.campaign_cursor=15;stock._context.ship_price_percent=0
	stock._system=19;stock._faction=0
	return stock

func verify_ships(bindings: RefCounted,cat: RefCounted):
	var stock: RefCounted=drawn_base(bindings,[[6,0]])
	stock._system=17;stock._context.supernova_owned=true
	check(stock._sample_ships(cat).is_empty(),"An initial empty ship stock performed extra rolls")
	finished_stock(stock,"zero ships")
	stock=drawn_base(bindings,[[6,1],[37,0],[37,15],[37,3],[37,1]])
	check(stock._sample_ships(cat)==[{"ship_id":1,"faction_id":0,"unit_price":124146}],"Ship selection ignored exclusions, affiliation or local price adjustment")
	finished_stock(stock,"excluded and foreign candidate rejection")
	stock=drawn_base(bindings,[[6,2],[37,1],[100,22],[37,1],[100,22],[37,5],[100,22]])
	check(stock._sample_ships(cat).map(func(row):return row.ship_id)==[1,5],"Duplicate ship selection failed to repeat its source draws")
	finished_stock(stock,"duplicate retry")
	stock=drawn_base(bindings,[[6,2],[37,1],[100,21],[5,4],[37,1],[37,2],[37,5],[100,22]])
	check(stock._sample_ships(cat).map(func(row):return row.ship_id)==[2,5],"Foreign roll21 or excluded-faction fallback failed")
	finished_stock(stock,"foreign threshold and fallback")
	stock=drawn_base(bindings,[[6,2],[100,0],[5,0],[37,1],[100,22]])
	stock._context.station_id=78;stock._context.campaign_cursor=16;stock._system=15
	check(stock._sample_ships(cat).map(func(row):return row.ship_id)==[0,1],"Var Hastra's first Betty or discarded foreign draw was lost")
	finished_stock(stock,"fixed Betty")
	stock=drawn_base(bindings,[[6,0]])
	stock._context.station_id=41
	check(stock._sample_ships(cat).map(func(row):return row.ship_id)==[10],"The extra fixed ship at station41 was not retained")
	finished_stock(stock,"fixed station41 ship")
	stock=drawn_base(bindings,[[6,1],[4,0]])
	stock._faction=1;stock._context.supernova_owned=true
	check(stock._sample_ships(cat).map(func(row):return row.ship_id)==[9,54],"Vossk stock before the later campaign used an unsupported hull")
	finished_stock(stock,"Vossk and Supernova ownership")
	stock=drawn_base(bindings,[[6,1],[37,1],[8,0],[3,0],[3,1],[3,0]])
	stock._system=17;stock._context.supernova_owned=true
	check(stock._sample_ships(cat).map(func(row):return row.ship_id)==[1,51,42,52],"Independent system17 ship rolls or ownership order changed")
	finished_stock(stock,"owned and system extras")
	stock=drawn_base(bindings,[])
	check(stock._ship_offer(cat,0,3).unit_price==16200,"An imported ship received the local-faction discount")
	stock._faction=3
	check(stock._ship_offer(cat,0,3).unit_price==16038,"Betty's original local price is not16038")
	stock._context.ship_price_percent=10
	check(stock._ship_offer(cat,0,3).unit_price==17658,"The ship modifier was applied to the discounted price")
	stock._context.ship_price_percent=-100
	stock._ship_offer(cat,0,3)
	check(not stock.error.is_empty(),"A negative shop price was silently accepted")
	stock=drawn_base(bindings,[[6,1]]);stock._draws=Stock.MAX_SELECTION_DRAWS
	check(stock._sample_ships(cat).is_empty() and not stock.error.is_empty(),"Exhausted ship sampling did not stop safely")
	stock=drawn_base(bindings,[]);stock._context.station_id=79;stock._system=15
	check(stock._sample_ships(cat).is_empty(),"Mido cursor15 generated ships")
	finished_stock(stock,"Mido early return")

func verify_temporary_items(bindings: RefCounted,cat: RefCounted):
	for cursor in [16,17,24,25]:
		for roll in [39,40]:
			var active: bool=cursor in [17,24]
			var stock: RefCounted=drawn_base(bindings,[[100,roll]] if active else [])
			stock._context.campaign_cursor=cursor
			var rows: Array=stock._temporary_stock(cat)
			check(rows.size()==int(active and roll==39),"The temporary item used the wrong cursor or roll boundary")
			if not rows.is_empty():check(rows[0].item_id==68 and rows[0].quantity==1,"The temporary offer lost the cloned prototype quantity")
			finished_stock(stock,"temporary offer")
	var item:={"item_id":181,"blueprint":false,"category":0,"subtype":0}
	for cursor in [58,59]:
		var stock: RefCounted=drawn_base(bindings,[])
		stock._context.campaign_cursor=cursor;stock._context.valkyrie_owned=true
		check(stock._expansion_eligible(item)==(cursor==59),"Item181's later fallback gate was ignored")

func verify_reseed_order(bindings: RefCounted,cat: RefCounted):
	var initial:={}
	for seed in 100:
		var rng:=Random.new();rng.seed_from(seed)
		var before: Dictionary=rng.snapshot()
		initial[rng.next_int(100)<=39]=before
		if initial.size()==2:break
	check(initial.size()==2,"Reseed fixtures did not span the temporary-offer boundary")
	if initial.size()!=2:return
	var context: Dictionary=SETTINGS.duplicate(true)
	context.station_id=98;context.campaign_cursor=17;context.ship_price_percent=0
	var yes:=Stock.new();var no:=Stock.new()
	check(yes.prepare(bindings,cat,context,initial[true],1789423200),yes.error)
	check(no.prepare(bindings,cat,context,initial[false],1789423200),no.error)
	var a: Dictionary=yes.snapshot();var b: Dictionary=no.snapshot()
	check(a.items[0].item_id==68 and a.items.slice(1)==b.items,"Reseeding lost or rerolled the preceding temporary offer")
	check(a.ships==b.ships and a.random==b.random and a.draw_calls==b.draw_calls,"The incoming random stream leaked past the ordinary stock reseed")
	check(Stock.new().restore(bindings,cat,a) and Stock.new().restore(bindings,cat,b),"Temporary stock could not be restored with its incoming random state")

func verify_stock_proof(bindings: RefCounted,pack: String):
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in BaseStock.SPANS:
		var bad: Dictionary=bindings.early_contracts.duplicate(true)
		bad.provenance.erase(key)
		check(not Definitions.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.mido_travel).is_empty(),"A missing ship stock source span was accepted")
	var bad: Dictionary=bindings.early_contracts.duplicate(true)
	bad.base_station_stock.ships.affiliations[0]=0
	check(not Definitions.parameters(bad),"An altered ship faction table was accepted")
