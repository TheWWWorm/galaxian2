extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Reticle=preload("res://src/presentation/flight_aim_reticle.gd")
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):await verify(args[i],args[i+1],args[i+2])
	print("Flight aim reticle checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String, pixels: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(pixels,library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var reticle:=Reticle.new();root.add_child(reticle);reticle.size=Vector2(801,601)
	if bindings.opening_staging.get("player_aim",{}).is_empty():
		check(not reticle.prepare(library,bindings,visuals) and not reticle.prepared,"Legacy pack acquired unverified reticle aliases");reticle.free();return
	if not reticle.prepare(library,bindings,visuals):check(false,reticle.error);reticle.free();return
	var source:=reticle.source()
	check(source.texture_id==10062 and source.regions[0].region==115 and source.regions[1].region==129,"Reticle changed original alias mapping")
	var original: Image=visuals.load_image(source.resource)
	check(original!=null,"Original reticle atlas missing")
	var sample:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"point":Vector3(400.9,300.9,-2000),"visible":true,"image_id":1216}
	check(not reticle.visible,"Reticle visible before its first ordinary frame")
	for phone in [false,true]:
		reticle.set_mobile_layout(phone)
		for index in 2:
			sample.image_id=source.regions[index].image_id
			check(reticle.present(sample),reticle.error)
			var crop: Image=original.get_region(Rect2i(source.regions[index].source_rect))
			var texture: Image=reticle.sprite.texture.get_image()
			check(crop.get_size()==texture.get_size() and crop.get_data()==texture.get_data(),"Reticle altered original atlas pixels")
			check(reticle.sprite.size==Vector2(crop.get_size())*(1.0 if phone else 0.5),"Desktop/phone reticle size mismatch")
			check(reticle.sprite.position+reticle.sprite.size*0.5==Vector2(400,300),"Reticle ignored integer anchor or centered on the static frame")
			check(reticle.visible and reticle.mouse_filter==Control.MOUSE_FILTER_IGNORE and reticle.sprite.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Reticle hidden or intercepting controls")
			if DisplayServer.get_name()!="headless":
				await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var output:=OS.get_environment("GOF2_CAPTURE_DIR")
				if not output.is_empty():check(root.get_texture().get_image().save_png(output.path_join("aim-%s-%d-%s.png"%[library.manifest.profile.edition,sample.image_id,"phone" if phone else "desktop"]))==OK,"Reticle capture failed")
	var rect:=reticle.sprite.get_rect()
	var bad:=sample.duplicate();bad.binding_id="0".repeat(64)
	check(not reticle.present(bad) and reticle.sprite.get_rect()==rect,"Foreign aim replaced the displayed sample")
	bad=sample.duplicate();bad.point=Vector3(INF,0,0)
	check(not reticle.present(bad) and reticle.sprite.get_rect()==rect,"Invalid aim moved the reticle")
	sample.visible=false;check(reticle.present(sample) and not reticle.visible,"Hidden aim remained visible")
	check(reticle.present({}) and not reticle.visible,"Missing capability did not hide reticle")
	var id: String=visuals.base_content_id;visuals.base_content_id="bad"
	check(not reticle.prepare(library,bindings,visuals) and not reticle.visible and reticle.get_child_count()==0,"Cross-profile texture selection retained artwork")
	visuals.base_content_id=id
	var records: Array=bindings.records[10062];bindings.records[10062]=[]
	check(not reticle.prepare(library,bindings,visuals),"Unregistered baseline atlas was accepted")
	bindings.records[10062]=records
	check(reticle.prepare(library,bindings,visuals),reticle.error)
	reticle.clear();check(reticle.source().is_empty() and reticle.get_child_count()==0 and not reticle.visible,"Clear retained reticle resources")
	reticle.free()
	print(library.manifest.profile.edition,": original reticle rectangles ",source.regions," verified")

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
