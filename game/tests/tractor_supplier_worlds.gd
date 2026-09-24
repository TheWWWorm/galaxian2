extends "res://tests/ordinary_worlds.gd"
## Detached catalogue/resource coverage; the application test separately earns
## the actual journey and purchase without assigning a station or inventory.
const SUPPLIERS={1:[5,6,7,8,9],8:[40,41,42,43,44]}

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Tractor supplier worlds: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):check(false,lib.error+bindings.error+cat.error);return
	var contact_rules: Dictionary=bindings.early_contracts.ordinary_generation.persistent
	var authored: Array=load("res://src/simulation/lounge_contacts.gd").decode_persistent_contacts(lib.read_resource(contact_rules.resource,1024*1024),contact_rules)
	check(authored.size()==27,"The original authored-contact table is incomplete")
	if not load("res://src/content/persistent_contact_definitions.gd").available(bindings):
		for station in [5,8,40,43]:check(Worlds.catalogue_location(bindings,cat,station).is_empty(),"Earlier content exposed a supplier without its authored-contact declarations")
		return
	var cache:=Cache.new()
	if not cache.configure(bindings):check(false,cache.error);return
	for system_id in SUPPLIERS:
		for station in SUPPLIERS[system_id]:
			var world:=Worlds.catalogue_location(bindings,cat,station)
			check(not world.is_empty() and world.system_id==system_id and world.faction==0,"Supplier world differs from the original catalogue")
			if failures:return
			if not select(cache,bindings,cat,lib,station):return
			var retained:=cache.snapshot()
			var planets:=PlanetLayout.new();var layout:=planets.for_lounge(bindings,cat,station,18)
			if layout.is_empty():check(false,planets.error);return
			check(layout.entries.size()==6 and layout.system_id==system_id and layout.station_id==station,"Supplier planet membership changed")
			for entry in layout.entries:check(lib.manifest.files.has(entry.texture_path),"Original supplier planet texture is missing")
			var current: Dictionary=layout.entries[layout.selected_index]
			var size_units:=int(current.scale*65536.0)
			var type: int=cat.tables.stations[station].planet_type
			var minimum:=35000 if type==17 else (32500 if type==16 else 20000)
			var maximum:=50000 if type==17 else (45500 if type==16 else 40000)
			check(size_units>=minimum and size_units<maximum,"Supplier planet ignored its source size group")
			var exterior: RefCounted=load("res://src/content/station_exterior_resources.gd").new()
			if not exterior.configure_ordinary_location(lib,bindings,cat,station):check(false,exterior.error);return
			var shape: Dictionary=exterior.snapshot()
			check(shape.station_id==station and shape.faction==0 and shape.layers.size()==3,"Supplier lost its original station assembly")
			for volume in shape.collision.get("shapes",shape.collision.boxes):check(exterior.point_volume(volume.center)>=0,"Supplier docking missed an original volume")
			var view:=StationView.select(bindings,station,18)
			var hangar: Dictionary=bindings.resolve_hangar(station,cat)
			check(not hangar.is_empty() and hangar.row==view.hangar_row and StationView.view_parameters(view),"Supplier selected another hangar or camera")
			var arrival:=ArrivalEnvironment.new()
			if not arrival.configure(bindings,cat,station,cache):check(false,arrival.error);return
			check(arrival.snapshot().system_id==system_id and cache.snapshot()==retained,"Supplier arrival changed its retained stock or location")
			check(not FreeFlight.flight(bindings,station).is_empty() and FreeFlight.docking_parameters(FreeFlight.docking(bindings,station)),"Supplier has no ordinary flight/docking owner")
			var context:=CONTEXT.duplicate(true);context.system_id=system_id;context.station_id=station
			for seed in [1,15,20]:
				var factory:=Factory.new()
				if not factory.configure_free_factory(bindings,cat,0,[81,86],context,seed):check(false,factory.error);return
				var packet:=factory.generate({"state":12345})
				if packet.is_empty():check(false,factory.error);return
				check(not Traffic.population(bindings,packet,0,0.5).is_empty() and not Life.population(bindings,packet).is_empty(),"Supplier traffic lacks native combat/lifecycle ownership")
			var stock: Array=cache.item_stock(station)
			if station==8:
				for id in [68,69,70]:check(stock.any(func(row):return row.item_id==id and row.quantity>0 and row.unit_price>0),"Taygete lost its source-designated tractor stock")
			check(select(cache,bindings,cat,lib,station) and cache.snapshot()==retained,"Browsing a supplier rerolled its original stock")
		var gate: int=Worlds.SYSTEMS[system_id].gate_station_id
		var last: int=SUPPLIERS[system_id].back()
		var original: int=cat.tables.stations[last].planet_type
		cat.tables.stations[last].planet_type=1
		check(Worlds.catalogue_location(bindings,cat,gate).is_empty(),"A modified neighboring planet passed supplier world validation")
		cat.tables.stations[last].planet_type=original
	check(Worlds.location(bindings.mido_travel,48).is_empty(),"Supplier travel exposed the unfinished Sahi world")
