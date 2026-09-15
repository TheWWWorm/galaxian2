extends "res://tests/lounge_cache.gd"
## Explicit settings/time fixtures cover source draw boundaries and the hidden
## opening lounge sequence. Location selections here are not actual flown trips.
const Stock=preload("res://src/simulation/station_stock.gd")
const SETTINGS={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,
	"energy_availability_percent":0,"missile_availability_percent":0}

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var context: Dictionary=SETTINGS.duplicate(true);context.station_id=78;context.campaign_cursor=1
	var rng:=Random.new();rng.seed_from(917)
	if not Stock.available(bindings):
		check(not Stock.new().prepare(bindings,cat,context,rng.snapshot(),1),"Older packs enabled unverified stock")
		return
	verify_stock_boundaries(bindings)
	var prototype: Array=cat.tables.items.duplicate(true)
	for cursor in [1,6]:
		context.campaign_cursor=cursor
		var stock:=Stock.new()
		check(stock.prepare(bindings,cat,context,rng.snapshot(),null),stock.error)
		var state: Dictionary=stock.snapshot()
		check(state.items==[{"item_id":0,"quantity":1,"unit_price":0},{"item_id":22,"quantity":1,"unit_price":0},{"item_id":55,"quantity":1,"unit_price":0}],"Tutorial stock lost its three free offers")
		check(state.random==rng.snapshot() and state.draw_calls==0 and state.unix_seconds==null and state.ships.is_empty(),"The tutorial reseeded or consumed stock/ship randomness")
	var populations:=0
	for cursor in [7,11,13,15]:
		for station in [75,76,77,78,79]:
			for flags in [[false,false],[true,false],[false,true],[true,true]]:
				context.campaign_cursor=cursor;context.station_id=station
				context.difficulty=1.5 if cursor==15 else 0.5
				context.valkyrie_owned=flags[0];context.supernova_owned=flags[1]
				var stock:=Stock.new()
				if not stock.prepare(bindings,cat,context,rng.snapshot(),1789423200):check(false,stock.error);return
				var state: Dictionary=stock.snapshot();populations+=1
				check(state.draw_calls>0 and state.ships.is_empty(),"Early Mido stock skipped items or sold ships before cursor16")
				check(Stock.new().restore(bindings,cat,state),"Generated stock could not restore from its retained inputs")
				var other:=Random.new();other.seed_from(999)
				var repeat:=Stock.new();check(repeat.prepare(bindings,cat,context,other.snapshot(),1789423200),repeat.error)
				check(repeat.snapshot().items==state.items and repeat.snapshot().random==state.random,"Ordinary stock did not reseed from its sampled Unix time")
				var before: Dictionary=stock.snapshot();var bad: Dictionary=context.duplicate(true);bad.campaign_cursor=16
				check(not stock.prepare(bindings,cat,bad,rng.snapshot(),1789423200) and stock.snapshot()==before,"Unsupported cursor replaced retained stock")
	check(cat.tables.items==prototype,"Stock sampling mutated the item prototypes")
	var retained:=Stock.new()
	check(retained.prepare(bindings,cat,context,rng.snapshot(),1789423200),retained.error)
	var before: Dictionary=retained.snapshot()
	var changed: Dictionary=before.duplicate(true);changed.random.state^=1
	check(not retained.restore(bindings,cat,changed) and retained.snapshot()==before,"A changed retained random stream was accepted")
	for key in ["valkyrie_owned","supernova_owned","difficulty","energy_availability_percent","missile_availability_percent"]:
		var incomplete: Dictionary=context.duplicate(true);incomplete.erase(key)
		check(not retained.prepare(bindings,cat,incomplete,rng.snapshot(),1789423200) and retained.snapshot()==before,"Missing settings changed retained stock: "+key)
	check(not retained.prepare(bindings,cat,context,rng.snapshot(),null) and retained.snapshot()==before,"Ordinary stock invented a time seed")
	verify_location_history(bindings,cat,lib,rng.snapshot())
	print("Station stock: %d explicit catalogue populations"%populations)

func drawn_stock(bindings: RefCounted,draws: Array) -> RefCounted:
	var stock:=Stock.new();stock._rules=bindings.early_contracts.station_generation.duplicate(true)
	stock._context=SETTINGS.duplicate(true);stock._context.station_id=79;stock._context.campaign_cursor=13
	stock._tech=2;stock._faction=3;stock._rng=Draws.new(draws)
	return stock

func finished_stock(stock: RefCounted,label: String):
	check(stock.error.is_empty() and not stock._rng.wrong and stock._rng.choices.is_empty(),"Stock draw order: "+label)

func verify_stock_boundaries(bindings: RefCounted):
	var item:={"item_id":1,"category":0,"subtype":0,"tech":1,"origin":0,"availability":100,
		"unit_price":100,"blueprint":false,"designated_station":-1,"vossk_only":-1,"affinity":100}
	var stock:=drawn_stock(bindings,[[100,50],[15,0]])
	check(stock._sample_item(item)=={"item_id":1,"quantity":1,"unit_price":100},"The last accepted availability roll was rejected")
	finished_stock(stock,"availability accepted")
	stock=drawn_stock(bindings,[[100,51]])
	check(stock._sample_item(item).is_empty(),"The first excluded availability roll was accepted");finished_stock(stock,"availability excluded")
	for id in [164,175,217,218]:
		item.item_id=id
		stock=drawn_stock(bindings,[])
		check(stock._sample_item(item).is_empty(),"An explicitly excluded item consumed an availability draw")
		finished_stock(stock,"excluded item")
	item.item_id=1
	item.tech=0
	for roll in [60,61]:
		var draws: Array=[[100,0],[100,roll]]
		if roll==60:draws.append([15,14])
		stock=drawn_stock(bindings,draws)
		check(stock._sample_item(item).is_empty()==(roll==61),"Low-tech roll60 must pass and61 must fail")
		finished_stock(stock,"low tech")
	item.tech=3;item.availability=0
	stock=drawn_stock(bindings,[[30,0]]);stock._context.valkyrie_owned=true
	check(stock._sample_item(item).is_empty(),"An expansion fallback bypassed station tech")
	finished_stock(stock,"fallback before tech rejection")
	stock=drawn_stock(bindings,[])
	check(stock._sample_item(item).is_empty(),"Absent expansion ownership created an item")
	finished_stock(stock,"unowned expansion")
	item.subtype=29
	stock=drawn_stock(bindings,[]);stock._context.valkyrie_owned=true
	check(stock._sample_item(item).is_empty(),"Mido generated the excluded gas-equipment fallback")
	finished_stock(stock,"Mido gas exclusion")
	item.subtype=0
	item.designated_station=79;item.availability=10;item.unit_price=0
	stock=drawn_stock(bindings,[[15,4]])
	check(stock._sample_item(item)=={"item_id":1,"quantity":1,"unit_price":0},"Designated station did not bypass ordinary inclusion filters")
	finished_stock(stock,"designated item")
	item.subtype=23
	stock=drawn_stock(bindings,[]);stock._context.difficulty=1.5
	check(stock._sample_item(item).is_empty(),"A designated offer bypassed the hard-difficulty equipment restriction")
	finished_stock(stock,"hard equipment restriction")
	item={"item_id":110,"category":4,"affinity":100}
	stock=drawn_stock(bindings,[[15,0],[10,0],[10,7]])
	check(stock._quantity(item)==17,"A capped quantity reused its first threshold draw")
	finished_stock(stock,"independent clamp replacement")
	item.affinity=50
	stock=drawn_stock(bindings,[[15,13],[10,8]])
	check(stock._quantity(item)==18,"An equal quantity/limit unnecessarily redrew")
	finished_stock(stock,"quantity equals limit")
	item={"item_id":111,"category":4,"affinity":100}
	for hard in [false,true]:
		stock=drawn_stock(bindings,[[15,0]]);stock._context.difficulty=1.5 if hard else 0.5
		check(stock._quantity(item)==(10 if hard else 100),"Distance affinity or difficulty scaled quantity incorrectly")
		finished_stock(stock,"goods scaling")
	item.item_id=109
	stock=drawn_stock(bindings,[[15,14]])
	check(stock._quantity(item)==9,"The special half-quantity item used ordinary goods scaling")
	finished_stock(stock,"half quantity")

func verify_location_history(bindings: RefCounted,cat: RefCounted,lib: RefCounted,initial_random: Dictionary):
	var cache:=Cache.new();check(cache.configure(bindings),cache.error)
	var random: Dictionary=initial_random.duplicate(true)
	var context:={"campaign_cursor":1,"station_id":78,"rank":0,"reputation":{"axes":[30,0],"override":-1}}
	var original:={};var kernstal:={}
	for visit in [[78,1],[78,6],[79,11],[76,12],[79,13]]:
		context.station_id=visit[0];context.campaign_cursor=visit[1]
		if visit[1]==13:context.rank=2;context.reputation.axes=[-20,50]
		var before: Dictionary=cache.snapshot()
		if not cache.select_location(bindings,cat,lib,context,SETTINGS,random,1789423200+visit[1]):check(false,cache.error);return
		var current: Dictionary=cache.snapshot();var location: Dictionary=cache.location(visit[0])
		check(location.stock.random==location.population.initial_random,"Contacts did not follow stock RNG")
		check(current.current_station_id==visit[0],"The generated cache lost its current selection")
		if visit==[78,1]:original=location
		elif visit==[78,6]:
			check(location==original and current.random==random and current.history==before.history,"A same-location tutorial visit rerolled hidden contacts")
		elif visit==[79,11]:kernstal=location
		elif visit==[79,13]:
			check(location==kernstal and location.population.context.campaign_cursor==11,"The first accessible lounge lost its earlier quotes")
			check(current.random==random and current.history==before.history,"Revisiting an old lounge rewound history or consumed randomness")
			check(current.locations.map(func(row):return row.station_id)==[78,79,76],"A revisit reordered the FIFO cache")
		random=current.random
	var before: Dictionary=cache.snapshot();var bad: Dictionary=context.duplicate(true);bad.station_id=75
	check(not cache.select_location(bindings,cat,lib,bad,{},random,1) and cache.snapshot()==before,"Failed stock preparation changed the location history")
	for station in [75,77]:
		context.station_id=station
		check(cache.select_location(bindings,cat,lib,context,SETTINGS,random,1789423220+station),cache.error)
		random=cache.snapshot().random
	check(cache.location(79).is_empty(),"A revisited old location survived FIFO eviction")
	context.station_id=79
	check(cache.select_location(bindings,cat,lib,context,SETTINGS,random,1789423400),cache.error)
	check(cache.location(79).population!=kernstal.population,"An evicted lounge reused its earlier generation")
	var fork: RefCounted=cache.fork();var detached: Dictionary=fork.snapshot();detached.history.fill(false)
	check(cache.snapshot()==fork.snapshot(),"A detached cache snapshot modified its owner")
