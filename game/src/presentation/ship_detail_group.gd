extends RefCounted
## Periodic geometry-manager selection. The owner supplies positions/reference
## from the source update point; this component does not assume the latest camera.
const Clock = preload("res://src/content/lod_refresh_definitions.gd")
const Detail = preload("res://src/presentation/ship_detail.gd")
const GeometryDetail = preload("res://src/presentation/geometry_detail.gd")
const Frames = preload("res://src/simulation/frame_clock.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Library = preload("res://src/content/library.gd")
var error := ""
var _clock := {}
var _counter := 0
var _max_ms := 0
var _selectors := {}
var _selections := {}
var _base := ""
var _binding := ""

func configure(bindings: RefCounted, ships: Dictionary) -> bool:
	clear()
	if bindings==null:return reject("Ship detail group requires source declarations")
	if ships.is_empty(): return reject("Ship detail group requires registered ships")
	var staged := {}
	for key in ships:
		if not (key is int or key is String) or not ships[key] is int: return reject("Invalid ship detail group identity")
		var selector := Detail.new()
		if not selector.configure(bindings.ship_lod,ships[key]): return reject(selector.error)
		if bindings.ship_lod.body_resource_ids[ships[key]][0]==65535: return reject("Ships without alternate meshes are not registered with the source LOD manager")
		staged[key]=selector
	return configure_selectors(bindings,staged)

func configure_selectors(bindings: RefCounted, selectors: Dictionary) -> bool:
	clear()
	if bindings==null or not Clock.parameters(bindings.lod_refresh) or not Frames.valid_parameters(bindings.frame_clock) or not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):return reject("Geometry detail group requires valid source declarations and identity")
	if selectors.is_empty():return reject("Geometry detail group requires registered selectors")
	var staged := {}
	for key in selectors:
		var selector: Variant = selectors[key]
		if not (key is int or key is String) or not (selector is Detail or selector is GeometryDetail) or not selector.has_alternates():return reject("Invalid geometry detail selector")
		staged[key]=selector.fork_for_frame()
	_clock=bindings.lod_refresh.duplicate(true)
	_counter=int(_clock.initial_milliseconds)
	_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	_selectors=staged
	_base=bindings.base_content_id
	_binding=bindings.binding_id
	return true

func update(delta_ms: Variant, positions: Dictionary, reference: Variant, detail: Variant, suppressed: Variant) -> bool:
	error=""
	if _selectors.is_empty(): return reject("Configure ship detail group before updating")
	if not Numbers.integer(delta_ms,0,_max_ms) or not suppressed is bool: return reject("Invalid LOD frame or suppression state")
	# Suppressed source updates neither accumulate time nor select geometry.
	if suppressed: return true
	var next := _counter+int(delta_ms)
	if next<int(_clock.refresh_at_milliseconds):
		_counter=next
		return true
	if not refresh(positions,reference,detail): return false
	_counter=int(_clock.reset_milliseconds)
	return true

func refresh(positions: Dictionary, reference: Variant, detail: Variant) -> bool:
	error=""
	if _selectors.is_empty(): return reject("Configure ship detail group before refreshing")
	if not reference is Vector3 or not reference.is_finite() or positions.size()!=_selectors.size(): return reject("Invalid LOD reference or ship position set")
	var staged := {}
	for key in _selectors:
		var position: Variant = positions.get(key)
		if not position is Vector3 or not position.is_finite(): return reject("Invalid LOD position for ship %s" % key)
		var displacement: Vector3 = position-reference
		var selected: Dictionary = _selectors[key].select(displacement.length_squared(),detail)
		if selected.is_empty(): return reject(_selectors[key].error)
		staged[key]=selected
	_selections=staged
	# Immediate refreshes leave the periodic accumulator unchanged.
	return true

func snapshot() -> Dictionary:
	if _selectors.is_empty(): return {}
	return {"base_content_id":_base,"binding_id":_binding,"counter_ms":_counter,"selections":_selections.duplicate(true)}

func clear() -> void:
	error="";_clock={};_counter=0;_max_ms=0;_selectors={};_selections={};_base="";_binding=""

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._clock = _clock.duplicate(true)
	copy._counter = _counter
	copy._max_ms = _max_ms
	for key in _selectors: copy._selectors[key] = _selectors[key].fork_for_frame()
	copy._selections = _selections.duplicate(true)
	copy._base = _base
	copy._binding = _binding
	return copy

func reject(message: String) -> bool:
	error=message
	return false
