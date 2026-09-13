extends Control
## Original center frame, composed natively from the profile's image alias.
## Baseline atlas selection is explicit. This does not select or lock a target.
const Atlas = preload("res://src/content/atlas_region.gd")
const Library = preload("res://src/content/library.gd")
const IMAGE_ID := 1223
const PHONE_FRAME_WIDTH := 304.0
const BASELINE_ATLASES := {
	10062: "resources/data/textures/gof2_interface.aei",
	10063: "resources/data/textures/gof2_interface2_ipad.aei",
}
var error := ""
var prepared := false
var mobile_layout := false
var quarters: Array[TextureRect] = []
var _source := {}
var _quarter_size := Vector2.ZERO
var _active := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visible = false
	resized.connect(reflow)

func prepare(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> bool:
	clear()
	if library==null or bindings==null or visuals==null or not Library.valid_hash(bindings.binding_id) or bindings.base_content_id!=library.manifest.get("content_id") or visuals.base_content_id!=bindings.base_content_id:
		return fail("Target frame requires matching imported content, bindings and pixels")
	var geometry := source_geometry(library,bindings)
	if geometry.has("error"):return fail(geometry.error)
	var reader := Atlas.new()
	var texture := reader.load(library,visuals,geometry.resource,geometry.region)
	if texture==null:return fail(reader.error)
	_quarter_size=geometry.quarter_size
	_source=geometry
	for index in 4:
		var part := TextureRect.new()
		part.name = "Quarter%d" % index
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		part.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		part.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		part.stretch_mode = TextureRect.STRETCH_SCALE
		part.texture = texture
		part.flip_h = (index & 1)!=0
		part.flip_v = (index & 2)!=0
		quarters.append(part)
		add_child(part)
	prepared = true
	reflow()
	return true

func set_active(value: bool) -> void:
	_active = value
	visible = prepared and _active

func set_mobile_layout(value: bool) -> void:
	mobile_layout = value
	reflow()

func reflow() -> void:
	if not prepared: return
	# Physical atlas resolution differs between editions. The native composition
	# uses one phone width and half that width on desktop, preserving source aspect.
	var extent := marker_radii()
	var center := Vector2(floorf(size.x*0.5),floorf(size.y*0.5))
	for index in quarters.size():
		quarters[index].size = extent
		quarters[index].position = center + Vector2(0 if index & 1 else -extent.x,0 if index & 2 else -extent.y)

func marker_radii() -> Vector2:
	if not prepared: return Vector2.ZERO
	return logical_radii(_quarter_size,mobile_layout)

func source() -> Dictionary:
	return _source.duplicate(true)

func clear() -> void:
	for part in quarters: part.free()
	quarters.clear()
	_source = {}
	_quarter_size = Vector2.ZERO
	prepared = false
	_active = false
	visible = false
	error = ""

func fail(message: String) -> bool:
	error = message
	return false

static func logical_radii(quarter_size: Vector2, mobile: bool) -> Vector2:
	return quarter_size*(PHONE_FRAME_WIDTH/(2.0*quarter_size.x))*(1.0 if mobile else 0.5)

static func source_geometry(library: RefCounted, bindings: RefCounted) -> Dictionary:
	if library==null or bindings==null or bindings.base_content_id!=library.manifest.get("content_id"):return {"error":"Target frame requires matching content and bindings"}
	var region: Dictionary=bindings.resolve_image_region(IMAGE_ID)
	if region.is_empty():return {"error":bindings.error}
	var texture_id := int(region.texture_id)
	if not BASELINE_ATLASES.has(texture_id):return {"error":"Unsupported target frame atlas"}
	var resource: String=BASELINE_ATLASES[texture_id]
	var registered := false
	for record in bindings.records.get(texture_id,[]):
		if record.resource==resource and record.kind=="texture" and int(record.registration_type)==2:registered=true
	if not registered:return {"error":"Target frame atlas is not registered by this profile"}
	var reader := Atlas.new()
	var metadata := reader.region(library.read_resource(resource,Atlas.MAX_BYTES),int(region.region))
	if metadata.is_empty():return {"error":reader.error}
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"image_id":IMAGE_ID,
		"texture_id":texture_id,"resource":resource,"region":int(region.region),"source_rect":Rect2(metadata.rect),"quarter_size":Vector2(metadata.rect.size)}
