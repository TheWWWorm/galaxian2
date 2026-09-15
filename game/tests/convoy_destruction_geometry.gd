extends "res://tests/convoy_world.gd"
## Original capital breakup rendered from native death snapshots. Camera and
## lighting are isolated GPU fixtures; this is not a station presentation claim.
const CombatGroup=preload("res://src/simulation/opening_combat_group.gd")
const CapitalResources=preload("res://src/content/freighter_destruction_resources.gd")
const CapitalDeath=preload("res://src/simulation/freighter_destruction.gd")
const Geometry=preload("res://src/presentation/freighter_destruction_geometry.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
var _equipment: RefCounted
var _resources: RefCounted
var _stages:=[]
var capture_prefix:="convoy"
var camera_offset:=Vector3(45000,26000,-53000)

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("Convoy breakup GPU test timed out");quit(1))
	call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:
		super.verify(args.slice(0,3))
		if not failures:await render_stages(args)
	else:check(false,"Expected content, bindings, visuals and optional captures")
	print("Convoy breakup geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_bodies(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,context: Dictionary,world: RefCounted) -> void:
	super.verify_bodies(bindings,cat,equipment,context,world)
	_equipment=equipment

func verify_capture(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted) -> void:
	_resources=CapitalResources.new()
	var death:=CapitalDeath.new();var combat:=CombatGroup.new()
	if not _resources.configure_convoy(library,bindings) or not death.configure_convoy(bindings,_resources,construction,5) or not combat.configure_convoy(bindings,cat,construction,_equipment,Reputation.initial(bindings)):check(false,_resources.error+death.error+combat.error);return
	var random: Dictionary=construction.snapshot().random_state
	if not combat.begin_contact_pass(random,true) or combat.normal_hit(5,combat.snapshot().actors[5].vitals.hull).is_empty():check(false,combat.error);return
	var started:=death.advance(16,random,combat.snapshot().actors[5])
	if started.is_empty():check(false,death.error);return
	random=started.random_state
	_stages.append({"label":"entry","owner":death.fork_for_frame()})
	var midpoint: float=(death.snapshot().animation.start_ms+death.snapshot().animation.end_ms)/2.0
	while death.snapshot().phase=="animation":
		var result:=death.advance(100,random)
		if result.is_empty():check(false,death.error);return
		random=result.random_state
		if _stages.size()==1 and death.snapshot().animation.time_ms>=midpoint:_stages.append({"label":"middle","owner":death.fork_for_frame()})
	_stages.append({"label":"breakup","owner":death.fork_for_frame()})
	var wreck:=death.advance(150,random)
	if wreck.is_empty():check(false,death.error);return
	_stages.append({"label":"wreck","owner":death.fork_for_frame()})
	check(death.snapshot().material_id==33356 and death.snapshot().model_scale==2.0,"Original battleship wreck lost its material or scale")

func render_stages(args: PackedStringArray) -> void:
	if _stages.size()!=4:check(false,"Missing capital breakup stages");return
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.near=10;camera.far=250000;camera.fov=48;viewport.add_child(camera);camera.current=true
	var center: Vector3=_stages[0].owner.snapshot().pose.origin
	camera.look_at_from_position(center+camera_offset,center)
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);light.light_energy=2.0;viewport.add_child(light)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.75;viewport.add_child(env)
	var geometry:=Geometry.new();viewport.add_child(geometry)
	if not geometry.build(library,visuals,bindings,_resources,_stages[0].owner):check(false,geometry.error);viewport.free();return
	var images:=[]
	for stage in _stages:
		var before: Dictionary=stage.owner.snapshot()
		if not geometry.apply_state(stage.owner,camera.global_transform):check(false,geometry.error);break
		check(stage.owner.snapshot()==before,"GPU presentation advanced the native death")
		check(geometry.cargo.transform==before.cargo.pose,"Scaling the capital hull also scaled its salvage")
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var image:=viewport.get_texture().get_image();images.append(image)
		var background:=image.get_pixel(0,0);var count:=0
		for y in range(0,image.get_height(),2):
			for x in range(0,image.get_width(),2):
				var pixel:=image.get_pixel(x,y)
				if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:count+=1
		check(count>150,"Original battleship did not render: "+stage.label)
		if args.size()==4:
			DirAccess.make_dir_recursive_absolute(args[3])
			check(image.save_png(args[3].path_join(capture_prefix+"-"+stage.label+".png"))==OK,"Ship breakup capture failed")
	if images.size()==4:check(images[0].get_data()!=images[1].get_data() and images[2].get_data()!=images[3].get_data(),"Original breakup or wreck material rendered unchanged")
	viewport.free()
