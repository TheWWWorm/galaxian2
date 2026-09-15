extends "res://tests/lounge_contacts.gd"
## Explicit populations test source FIFO retention independently of the opening.
const Cache=preload("res://src/simulation/lounge_cache.gd")
const Lifecycle=preload("res://src/content/lounge_lifecycle_definitions.gd")

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var cache:=Cache.new()
	if not Lifecycle.available(bindings):
		check(not cache.configure(bindings),"Older content enabled station contact retention")
		return
	check(cache.configure(bindings),cache.error)
	var context:={"campaign_cursor":13,"station_id":79,"rank":0,"reputation":{"axes":[30,0],"override":-1}}
	var random:=Random.new();random.seed_from(0)
	var history: Array=[];history.resize(15);history.fill(false)
	var original:={};var consumed:=-1
	for id in [79,75,77,76,78,79]:
		context.station_id=id
		var contacts:=Contacts.new()
		if not contacts.prepare(bindings,cat,lib,context,random.snapshot(),history):check(false,contacts.error);return
		var population: Dictionary=contacts.snapshot()
		if not cache.remember(contacts):check(false,cache.error);return
		check(cache.snapshot().locations.size()<=3,"The contact cache grew beyond the source capacity")
		check(cache.location(id).population==population and cache.snapshot().history==population.history,"Retention changed source quotes or mission-type history")
		check(random.restore(population.random),random.error);history=population.history
		if original.is_empty():
			original=population
			for offer_id in cache.location(id).offers:
				consumed=offer_id;break
			check(consumed>=0,"The explicit initial seed has no contract")
			check(cache.consume(id,consumed),cache.error)
			check(cache.location(id).offers[consumed].consumed,"The cached contact lost its consumed flag")
		elif id==77:
			var before: Dictionary=cache.snapshot()
			check(cache.location(79).offers[consumed].consumed and cache.location(79).population==original,"Returning to a retained station revived a consumed contact or repriced its offer")
			check(cache.snapshot()==before,"A cache hit reordered locations")
		elif id==76:check(cache.location(79).is_empty(),"The previously revisited oldest location was treated as LRU")
		elif id==79:
			check(population!=original and not cache.location(id).offers.get(consumed,{}).get("consumed",false),"An evicted station reused its old population or another generation's consumed flag")
		var before: Dictionary=cache.snapshot()
		check(not cache.remember(contacts) and cache.snapshot()==before,"The same location regenerated while cached")
		check(not cache.consume(90,0) and cache.snapshot()==before,"An absent contact changed retention")
	check(cache.snapshot().locations.map(func(row):return row.station_id)==[76,78,79],"New station insertion did not retain the last three generated populations")
	var before: Dictionary=cache.snapshot()
	var fork: RefCounted=cache.fork()
	var bad:=Contacts.new()
	context.station_id=75
	var stale: Array=[];stale.resize(15);stale.fill(false)
	check(bad.prepare(bindings,cat,lib,context,random.snapshot(),stale),bad.error)
	check(not fork.remember(bad) and fork.snapshot()==before and cache.snapshot()==before,"A stale history replaced a retained population")
	var altered: RefCounted=bindings.get_script().new();altered.early_contracts=bindings.early_contracts.duplicate(true)
	altered.early_contracts.station_lounges.capacity=4
	check(not Cache.new().configure(altered),"An unsupported capacity was accepted")
