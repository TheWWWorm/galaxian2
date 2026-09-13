extends SceneTree
## Actual-content regression: caller supplies content/bindings/visual triples.
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const AEM = preload("res://src/content/aem.gd")
const Tracks = preload("res://src/content/animation_tracks.gd")
const Resources = preload("res://src/presentation/model_resources.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected actual content/bindings/visual triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1],args[index+2])
	print("Scenery static models: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, pack: String, textures: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var visuals := Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(textures,library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	if bindings.scenery_resources.is_empty():
		check(false,"Source scenery resource declarations are required");return
	var alternatives: Array = bindings.scenery_resources.model_ids
	check(alternatives.size()==4,"Expected four source scenery alternatives")
	if alternatives.size()!=4:return
	var paths := [];var models := {};var keyed_count := 0
	for base in alternatives:
		for level in 4:
			var path: String = bindings.resolve(int(base)+level,"mesh")
			check(not path.is_empty(),bindings.error)
			if path.is_empty():return
			var reader := AEM.new()
			var decoded: Dictionary = reader.decode(library.read_resource(path,AEM.MAX_BYTES))
			check(not decoded.is_empty(),library.error+reader.error)
			if decoded.is_empty():return
			check(Tracks.has_identity_tracks(decoded.surfaces),"Source scenery has unsupported nonidentity tracks: "+path.get_file())
			if decoded.keyframes>0:keyed_count+=1
			paths.append(path);models[path]=decoded
	check(paths.size()==16 and keyed_count>0,"Fixture must exercise all scenery levels and authored identity keys")
	var resources := Resources.new()
	if not resources.prepare(paths,library,visuals,bindings,"high",true):
		check(false,resources.error);return
	check(resources.covers(paths,bindings,"high",true),"Prepared static scenery resources are not covered")
	check(not resources.covers(paths,bindings,"high",true,false),"Source shader UV cache was reused for raw inspection")
	for path in paths:
		var model: Node3D = resources.instantiate(path)
		check(model!=null,resources.error)
		if model==null:continue
		for surface_index in model.surfaces.size():
			var raw_uvs: PackedVector2Array=model.surfaces[surface_index].uvs
			var uvs: PackedVector2Array=model.instances[surface_index].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
			check(uvs.size()==raw_uvs.size(),"Static scenery UV count changed")
			for vertex in uvs.size():check(uvs[vertex]==Vector2(raw_uvs[vertex].x,1.0-raw_uvs[vertex].y),"Static scenery lost source UV preparation")
		var time_range: Vector2 = Tracks.range_of(models[path].surfaces)
		for source_time in [time_range.x-1.0,time_range.x,time_range.y,time_range.y+1.0]:
			model.set_source_time(source_time)
			for instance in model.instances:
				check(instance.transform==Transform3D.IDENTITY,"Authored identity keys changed a scenery surface pose: "+path.get_file())
		model.free()
	for offset in [4,5]:
		var animated: String = bindings.resolve(int(alternatives[3])+offset,"mesh")
		check(not animated.is_empty(),bindings.error)
		if animated.is_empty():continue
		var reader := AEM.new()
		var decoded: Dictionary = reader.decode(library.read_resource(animated,AEM.MAX_BYTES))
		check(not decoded.is_empty(),library.error+reader.error)
		if decoded.is_empty():continue
		check(decoded.keyframes>0 and not Tracks.has_identity_tracks(decoded.surfaces),"Destruction animation passed the static predicate")
		# A valid first resource is staged before the animated resource fails.
		check(not resources.prepare([paths[0],animated],library,visuals,bindings,"high",true),"Static scene accepted destruction animation")
		check("source animation semantics" in resources.error,"Animated resource failed for an unrelated reason: "+resources.error)
		check(resources._prototypes.is_empty() and not resources.covers(paths,bindings,"high",true),"Failed static preparation retained prototypes or ownership")
		var residual: Node3D = resources.instantiate(paths[0])
		check(residual==null,"Failed preparation retained a usable prototype")
		if residual!=null:residual.free()
	resources.clear()
	print(library.manifest.profile.edition,": 16 static scenery levels verified; both destruction animations rejected")

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
