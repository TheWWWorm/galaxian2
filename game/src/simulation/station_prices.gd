extends RefCounted
## Native station quotes. Repricing is separate from stock generation and never
## changes quantities. Each source list has its own station-seeded random stream.
const Definitions=preload("res://src/content/ordinary_shopping_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var error:=""
var _state:={}

func prepare(bindings: RefCounted,cat: RefCounted,station_id: Variant,lists: Variant,random_state: Variant,unix_seconds: Variant,price_percent: Variant=0,special_markup: Variant=false) -> bool:
	error=""
	var place:=Definitions.location(bindings,cat,station_id)
	if place.is_empty():return reject("Station prices require a supported location and matching content")
	if not price_percent is int or not Numbers.integer(price_percent,-100,1000) or not special_markup is bool:return reject("Unsupported retained item-price modifier")
	var rules: Dictionary=bindings.mido_travel.ordinary_shopping
	var names: Array=rules.pricing.list_order
	if not lists is Dictionary or lists.size()!=names.size() or not unix_seconds is Array or unix_seconds.size()!=names.size():return reject("Reprice cargo, installed items and stock with their sampled reseed times")
	var rng:=Random.new()
	if not rng.restore(random_state):return reject(rng.error)
	var next: Dictionary=lists.duplicate(true);var counts:={}
	for index in names.size():
		var name: String=names[index]
		if not lists.has(name):return reject("Missing item list: "+name)
		var rows: Variant=next[name]
		counts[name]=0
		if rows==null:
			if unix_seconds[index]!=null:return reject("An absent list cannot sample a reseed time")
			continue
		if not rows is Array or rows.size()>4096 or not unix_seconds[index] is int or not Numbers.integer(unix_seconds[index],0,9223372036854775807):return reject("Invalid station item list or reseed time")
		rng.seed_from(station_id)
		for row in rows:
			if row==null:continue
			if not row is Dictionary or row.size()!=2+int(row.has("quantity")) or not row.get("item_id") is int or not row.get("unit_price") is int or not Numbers.integer(row.get("item_id"),0,cat.tables.items.size()-1) or not Numbers.integer(row.get("unit_price"),-2147483648,2147483647):return reject("Invalid retained item quote")
			if row.has("quantity") and (not row.quantity is int or not Numbers.integer(row.quantity,0,2147483647)):return reject("Invalid retained item quantity")
			var item:=metadata(cat,row.item_id,rules.catalogue)
			if item.is_empty():return false
			item.current_system=place.system_id
			# Original free/disabled prices survive entry and consume no draw.
			if row.unit_price<=0:continue
			var quoted:=quote(item,rules.pricing,rng,price_percent,special_markup)
			if quoted<0:return false
			if not special_markup:counts[name]+=1
			row.unit_price=quoted
		rng.seed_from(unix_seconds[index])
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":station_id,"system_id":place.system_id,"price_percent":price_percent,
		"special_markup":special_markup,"lists":next,"draw_calls":counts,
		"initial_random":random_state.duplicate(true),"random":rng.snapshot(),"unix_seconds":unix_seconds.duplicate()}
	return true

func metadata(cat: RefCounted,item_id: int,rules: Dictionary) -> Dictionary:
	var properties: Dictionary=cat.tables.items[item_id].properties
	var origin: Variant=properties.get(int(rules.origin_property))
	var maximum_origin: Variant=properties.get(int(rules.maximum_origin_property))
	var low: Variant=properties.get(int(rules.minimum_price_property))
	var high: Variant=properties.get(int(rules.maximum_price_property))
	if not Numbers.integer(origin,0,cat.tables.systems.size()-1) or not Numbers.integer(maximum_origin,0,cat.tables.systems.size()-1) or not Numbers.integer(low,0,2147483647) or not Numbers.integer(high,low,2147483647):reject("The item lacks supported price origins or bounds");return {}
	var positions:=[]
	# Current location is set by the caller through the resolved catalogue row.
	for system in cat.tables.systems:
		var values:=[]
		for field in rules.system_coordinate_fields:
			if typeof(system.get("fields")) not in [TYPE_ARRAY,TYPE_PACKED_INT32_ARRAY] or system.fields.size()<=int(field) or not Numbers.integer(system.fields[int(field)],-32768,32767):reject("The system catalogue lacks supported map coordinates");return {}
			values.append(system.fields[int(field)])
		positions.append(Vector2i(values[0],values[1]))
	return {"minimum":low,"maximum":high,"origin":origin,"maximum_origin":maximum_origin,"positions":positions}

func quote(item: Dictionary,rules: Dictionary,rng: RefCounted,price_percent: int,special_markup: bool) -> int:
	# The resolved station system is carried in the temporary quote context.
	var current: int=item.current_system
	var origin: Vector2i=item.positions[item.origin]
	var span:=map_distance(origin,item.positions[item.maximum_origin])
	var travelled:=map_distance(origin,item.positions[current])
	if span<0 or travelled<0:return -1
	var price: int=item.maximum
	if special_markup:
		price=int(Vitals.single(Vitals.single(float(price))*float(rules.special_multiplier)))
	else:
		# MINSS selects its second operand for the source zero-distance NaN.
		var ratio: float=rules.ratio_maximum
		if span>0:
			var scale:=Vitals.single(float(rules.distance_percent_scale)/Vitals.single(float(span)))
			ratio=minf(float(rules.ratio_maximum),Vitals.single(Vitals.single(Vitals.single(float(travelled))*scale)/float(rules.distance_percent_scale)))
		price=int(item.minimum)+int(Vitals.single(Vitals.single(float(int(item.maximum)-int(item.minimum)))*ratio))
		var radius:=maxi(int(rules.minimum_variation),int(Vitals.single(Vitals.single(float(price))*float(rules.variation_fraction))))
		if radius>1073741823:return reject_price("The item variation exceeds the supported random range")
		var draw: int=rng.next_int(radius*2+1)
		if not rng.error.is_empty():return reject_price(rng.error)
		price+=draw-radius
	if price_percent!=0:
		var base:=Vitals.single(float(price))
		var adjustment:=Vitals.single(Vitals.single(Vitals.single(float(price_percent))*base)*float(rules.percent_fraction))
		price=int(Vitals.single(base+adjustment))
	if price<0 or price>2147483647:return reject_price("The source modifier produces an unsupported item price")
	return price

func map_distance(a: Vector2i,b: Vector2i) -> int:
	var dx:=int(a.x)-int(b.x);var dy:=int(a.y)-int(b.y)
	var squared:=dx*dx+dy*dy
	if squared>2147483647:return reject_price("The system distance exceeds the supported source range")
	return int(Vitals.single(sqrt(Vitals.single(float(squared)))))

func snapshot() -> Dictionary:return _state.duplicate(true)
func reject_price(message: String) -> int:reject(message);return -1
func reject(message: String) -> bool:error=message;return false
