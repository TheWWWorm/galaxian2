extends RefCounted
## Shared GPU verification for retained original freighter breakup frames.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Geometry=preload("res://src/presentation/freighter_destruction_geometry.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Roots=preload("res://src/presentation/npc_destruction_pose.gd")
const FreighterLife=preload("res://src/simulation/freighter_destruction.gd")
var tree: SceneTree
var report: Callable
var stages: Array
var death_resources: RefCounted
var prefix: String
var mesh_parts: int
var camera_distance: float

func verify(owner: SceneTree,args: PackedStringArray,resources: RefCounted,frames: Array,name: String,parts: int,distance:=1.0) -> void:
	tree=owner;report=Callable(owner,"check");death_resources=resources;stages=frames;prefix=name;mesh_parts=parts
	camera_distance=distance
	await render_stages(args)

func check(value: bool,message: String) -> void:report.call(value,message)

func render_stages(args: PackedStringArray) -> void:
	check(stages.size()==6,"Missing retained freighter rendering stages")
	if stages.size()!=6:return
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;tree.root.add_child(viewport)
	var camera:=Camera3D.new();camera.near=10;camera.far=250000;camera.fov=40;viewport.add_child(camera);camera.current=true
	var center: Vector3=stages[0].owner.snapshot().pose.origin
	camera.look_at_from_position(center+Vector3(8000,6500,-12000)*camera_distance,center)
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);light.light_energy=2.0;viewport.add_child(light)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.75;viewport.add_child(env)
	var geometry:=Geometry.new();viewport.add_child(geometry)
	if not geometry.build(library,visuals,bindings,death_resources,stages[0].owner):check(false,geometry.error);viewport.free();return
	check(geometry.body.instances.size()==mesh_parts,"Freighter rendering lost original body pieces: %d / %d"%[geometry.body.instances.size(),mesh_parts])
	check(geometry.effect.models.size()==2+stages[0].owner.snapshot().fragments.size(),"Freighter rendering lost generated debris")
	var images:={};var materials:={}
	for stage in stages:
		var state: Dictionary=stage.owner.snapshot();var before:=state.duplicate(true)
		if not geometry.apply_state(stage.owner,camera.global_transform):check(false,geometry.error);break
		check(stage.owner.snapshot()==before,"Presenting the freighter advanced its simulation")
		check(geometry.cargo.visible and geometry.body.visible and geometry.visible,"Freighter presentation omitted retained cargo or wreck")
		check(geometry.cargo.transform==state.cargo.pose,"Freighter cargo was drawn at another source pose")
		var roots:=Roots.for_death(stage.owner,camera.global_transform)
		if state.effect.active:
			check(is_equal_approx(roots.roots[0].basis.x.length(),state.effect_scale),"Final explosion lost its original scale")
			check(is_equal_approx(roots.roots[2].basis.x.length(),state.fragments[0].scale),"Explosion incorrectly scaled constructor debris")
		materials[stage.label]=geometry.body.materials[0].get_shader_parameter("diffuse_texture")
		if DisplayServer.get_name()!="headless":
			await tree.process_frame;await tree.process_frame;await RenderingServer.frame_post_draw
			var image:=viewport.get_texture().get_image();images[stage.label]=image
			var background:=image.get_pixel(0,0);var count:=0
			for y in range(0,image.get_height(),2):
				for x in range(0,image.get_width(),2):
					var pixel:=image.get_pixel(x,y)
					if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:count+=1
			check(count>100,"Original freighter geometry did not render: "+stage.label)
			if args.size()==4:
				DirAccess.make_dir_recursive_absolute(args[3])
				check(image.save_png(args[3].path_join(prefix+"-"+stage.label+".png"))==OK,"Freighter capture failed")
	check(materials.get("entry")==materials.get("animation-end") and materials.get("entry")!=materials.get("wreck-material") and materials.get("wreck-material")==materials.get("cleanup"),"Freighter texture change did not follow original timing")
	if images.size()==6:
		check(images.entry.get_data()!=images.middle.get_data() and images.middle.get_data()!=images["animation-end"].get_data(),"Original breakup animation rendered a static hull")
		check(images["animation-end"].get_data()!=images.cleanup.get_data(),"Original wreck material change did not affect the rendered image")
	var retained: Transform3D=geometry.body.instances[0].transform
	check(not geometry.apply_state(FreighterLife.new(),camera.global_transform) and geometry.body.instances[0].transform==retained,"Invalid lifecycle changed rendered geometry")
	viewport.free()
