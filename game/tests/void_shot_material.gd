extends SceneTree
## The Void fighter's Dark Matter Laser shot (type-1 alpha material) must blend
## by its texture alpha; type-2 weapon shots stay additive.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Surface=preload("res://src/presentation/animated_additive_model.gd")
var failures:=0
func check(ok: bool,text: String) -> void:
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if args.size()!=3 or not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,"Expected content, bindings and visuals")
	else:
		# 19091 is item 229's shot (alpha); 231's is additive.
		for model_id in [19091]:
			var resource: Variant=bindings.resolve(model_id,"mesh")
			check(int(bindings.material_for_mesh(resource,"high").get("render_type"))==1,"Void shot is no longer a type-1 material")
			var models:=Models.new()
			check(models.prepare([resource],library,visuals,bindings,"high",false,true),models.error)
			var surface:=Surface.new()
			for alpha in [true,false]:
				var model: Node3D=models.instantiate(resource)
				check(surface.prepare_model(model,alpha),surface.error)
				check((model.materials[0].shader==Surface.AlphaSource)==alpha,"Alpha flag %s chose the wrong shader"%alpha)
				surface.apply_surfaces(model,[{"pose":Transform3D.IDENTITY,"tint":Vector4(1,1,1,1)}],1.0)
				check((model.materials[0].shader==Surface.AlphaSource)==alpha,"apply_surfaces replaced the %s shader"%("alpha" if alpha else "additive"))
				model.free()
			models.clear()
	print("Void shot material: %d failures"%failures)
	quit(1 if failures else 0)
