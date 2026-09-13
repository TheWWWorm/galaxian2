extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Background=preload("res://src/presentation/opening_sky.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1],args[i+2])
	print("Opening escape environment checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String, textures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new();var catalogues:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(textures,library.manifest) or not catalogues.open(library):check(false,library.error+bindings.error+visuals.error+catalogues.error);return
	var bodies:=Bodies.new();var effects:=Effects.new();var world:=Scenery.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not world.configure(bindings,catalogues,1789100000,true,bodies,effects):check(false,bodies.error+effects.error+world.error);return
	var cue:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"phase":10,"frame":{"world_change":{"sky_mesh_id":17809,"sky_texture_id":10074,"planet_texture_id":10042,"planet_scale_multiplier":2.0}}}
	if bindings.opening_staging.get("escape_camera",{}).is_empty():
		var old:=world.snapshot();check(not world.apply_escape_environment(cue) and world.snapshot()==old,"Legacy scenery acquired escape relocation");return
	var before:=world.snapshot();var bad:=cue.duplicate(true);bad.base_content_id="0".repeat(64)
	check(not world.apply_escape_environment(bad) and world.snapshot()==before,"Foreign relocation changed scenery")
	bad=cue.duplicate(true);bad.phase=9
	check(not world.apply_escape_environment(bad) and world.snapshot()==before,"Scenery retired before the source relocation phase")
	var actor: RefCounted=world._destruction[-1]
	world._destruction[-1]=actor.get_script().new();var damaged_fixture:=world.snapshot()
	check(not world.apply_escape_environment(cue) and world.snapshot()==damaged_fixture,"Late retirement failure changed preceding actors")
	world._destruction[-1]=actor
	# A controlled source RNG state makes the earlier earned destruction retain
	# cargo. Relocation must not remove that cargo or award destruction again.
	var random:=Random.new();random.seed_from(54);world._random_state=random.snapshot()
	check(world._bodies.normal_hit(0,2147483647).destroyed_now,"Could not prepare an earned destruction")
	check(world.update(100,Vector3.ZERO),world.error)
	check(not world.snapshot().destruction[0].lifecycle.cargo.is_empty(),"Controlled destruction did not create its original cargo candidate")
	world.take_events()
	check(world._bodies.normal_hit(1,2147483647).destroyed_now,"Could not prepare a not-yet-processed destruction")
	before=world.snapshot()
	var branch: RefCounted=world.fork_for_frame()
	check(branch.apply_escape_environment(cue),branch.error)
	check(world.snapshot()==before,"Detached relocation changed the old scenery owner")
	var after: Dictionary=branch.snapshot()
	check(after.escape_relocated and after.objects==before.objects and after.random_state==before.random_state,"Relocation moved scenery or consumed RNG")
	check(after.remaining_count==before.remaining_count and after.destroyed_count==before.destroyed_count and branch.take_events().is_empty(),"Relocation invented destruction accounting")
	for i in after.bodies.objects.size():
		var expected: Dictionary=before.bodies.objects[i].duplicate(true);expected.active=false
		check(after.bodies.objects[i]==expected,"Relocation changed hull, damage permission, bounds or contact history")
		var lifecycle: Dictionary=before.destruction[i].lifecycle.duplicate(true);lifecycle.actor_state=4
		check(after.destruction[i].lifecycle==lifecycle and after.destruction[i].effect==before.destruction[i].effect,"Retirement changed cargo, update flag or effect history")
		check(not branch._bodies.collision_context(i).eligible,"Retired scenery remains collidable")
	check(not branch.apply_escape_environment(cue) and branch.snapshot()==after,"Repeated relocation changed state")
	check(branch.update(0,Vector3.ZERO),branch.error)
	check(branch.snapshot().destruction==after.destruction,"Zero frame cleared the source update flag")
	check(branch.update(100,Vector3.ZERO),branch.error)
	var later: Dictionary=branch.snapshot()
	for i in later.destruction.size():check(not later.destruction[i].lifecycle.update_enabled and later.destruction[i].effect==after.destruction[i].effect,"Retired scenery advanced its effect or kept its updater")
	check(later.objects==after.objects and branch.take_events().is_empty() and later.random_state==after.random_state,"Retired scenery spun, generated drops or consumed RNG")
	var sky:=Background.new();root.add_child(sky)
	check(sky.build(library,visuals,bindings,catalogues,0,3,false,"high",true),sky.error)
	if sky.selection.is_empty():sky.free();return
	var stars: Node3D=sky.layers[0];var original:=sky.selection.duplicate(true)
	var view:={"pose":Transform3D(Basis(Vector3.UP,0.7),Vector3(140,200,310))}
	var escape:=cue.duplicate(true);escape.phase=9
	check(sky.apply_view(view,escape),sky.error)
	check(sky.layers.size()==3 and sky.layers[1].visible and not sky.layers[2].visible,"Initial sky selected the arrival nebula")
	check(sky.apply_view(view,cue),sky.error)
	check(sky.layers[0]==stars and stars.visible and not sky.layers[1].visible and sky.layers[2].visible,"Sky swap changed stars or left the old nebula visible")
	check(sky.selection.layers==[original.layers[0],{"mesh_id":17809,"texture_id":10074,"mode":2}],"Arrival selected a different original sky")
	var saved:=sky.selection.duplicate(true);var pose:=sky.transform
	bad=cue.duplicate(true);bad.binding_id="f".repeat(64)
	check(not sky.apply_view({"pose":Transform3D.IDENTITY},bad) and sky.selection==saved and sky.transform==pose,"Rejected sky frame changed presentation")
	check(sky.apply_view(view,escape) and sky.selection==original and sky.layers[1].visible and not sky.layers[2].visible,"Rollback could not restore the preceding sky")
	sky.free()
	print(library.manifest.profile.edition,": scripted retirement preserves hull/cargo/counters/RNG, blocks contacts and freezes effects; original sky replacement and rollback verified")

func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
