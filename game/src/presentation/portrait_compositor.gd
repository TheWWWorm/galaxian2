extends RefCounted
## Native alpha composition of original portrait parts at source positions.
## Bounds preserve the source origin. Original panel frames are a separate layer.
const Library = preload("res://src/content/library.gd")
const Placements = preload("res://src/content/portrait_layer_definitions.gd")
const Atlas = preload("res://src/content/atlas_region.gd")
var error := ""

func compose(library: RefCounted, bindings: RefCounted, visuals: RefCounted, speaker: int, variant: String) -> Dictionary:
	error = ""
	if library == null or bindings == null or visuals == null: return failed("Portrait content is not loaded")
	var identity: String = library.manifest.get("content_id", "")
	if not Library.valid_hash(identity) or bindings.base_content_id != identity or visuals.base_content_id != identity or not Library.valid_hash(bindings.binding_id): return failed("Portrait content belongs to a different base")
	var portrait: Dictionary = bindings.resolve_speaker_portrait(speaker)
	if portrait.is_empty(): return failed(bindings.error)
	return compose_definition(library,bindings,visuals,speaker,variant,portrait)

func compose_definition(library: RefCounted, bindings: RefCounted, visuals: RefCounted, speaker: int, variant: String, portrait: Dictionary) -> Dictionary:
	error=""
	if library==null or bindings==null or visuals==null:return failed("Portrait content is not loaded")
	var identity: String=library.manifest.get("content_id","")
	if not Library.valid_hash(identity) or bindings.base_content_id!=identity or visuals.base_content_id!=identity or not Library.valid_hash(bindings.binding_id):return failed("Portrait content belongs to a different base")
	var plan := Placements.plan(bindings.portrait_layers, portrait, variant)
	if plan.has("error"): return failed(plan.error)
	var layers := []
	var atlas := Atlas.new()
	for row in plan.layers:
		var alias: Dictionary = bindings.resolve_image_region(row.image_id)
		if alias.is_empty(): return failed(bindings.error)
		var resource: String = bindings.resolve_portrait_texture(alias.texture_id, variant)
		if resource.is_empty(): return failed(bindings.error)
		var texture: AtlasTexture = atlas.load(library, visuals, resource, alias.region)
		if texture == null: return failed(atlas.error)
		var pixels := texture.get_image()
		if pixels == null or pixels.is_empty(): return failed("Portrait layer pixels are unavailable")
		layers.append({"image": pixels, "anchor": row.anchor, "y": row.y, "image_id": row.image_id, "resource": resource, "part": row.part})
	var result := blend(layers)
	if result.is_empty(): return result
	result.merge({"base_content_id": identity, "binding_id": bindings.binding_id, "speaker": speaker, "variant": variant, "layers": plan.layers.duplicate(true)})
	return result

func blend(layers: Array) -> Dictionary:
	error = ""
	if layers.is_empty() or layers.size() > 4: return failed("Portrait requires one to four layers")
	var placed := []
	var bounds := Rect2i()
	for layer in layers:
		if not layer is Dictionary or not layer.get("image") is Image or layer.get("anchor") not in [0, 16, 32] or not Placements.Numbers.integer(layer.get("y"), -8192, 8192): return failed("Invalid portrait layer")
		var pixels: Image = layer.image
		if pixels.is_empty() or pixels.is_compressed(): return failed("Portrait requires decoded layer pixels")
		var position := Vector2i(0, int(layer.y) - (pixels.get_height() if int(layer.anchor) == 32 else 0))
		var rect := Rect2i(position, pixels.get_size())
		bounds = rect if placed.is_empty() else bounds.merge(rect)
		if bounds.size.x > 2048 or bounds.size.y > 2048: return failed("Portrait exceeds composition bounds")
		placed.append({"image": pixels, "position": position})
	var output := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for layer in placed:
		var pixels: Image = layer.image
		if pixels.get_format() != Image.FORMAT_RGBA8:
			pixels = pixels.duplicate()
			pixels.convert(Image.FORMAT_RGBA8)
		output.blend_rect(pixels, Rect2i(Vector2i.ZERO, pixels.get_size()), layer.position - bounds.position)
	return {"image": output, "bounds": bounds}

func failed(message: String) -> Dictionary:
	error = message
	return {}
