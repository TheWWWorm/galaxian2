extends "res://tests/freighter_geometry.gd"
## The original Terran and Nivelian assemblies in an explicit landscape viewport.
const FreePopulation=preload("res://src/content/free_population_definitions.gd")

func verify(args: PackedStringArray):
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);return
	if not FreePopulation.available(bindings):check(false,"This fixture requires ordinary population declarations");return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=10;camera.far=250000
	camera.look_at_from_position(Vector3(10500,8000,-13500),Vector3(0,0,900))
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);viewport.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4
	viewport.add_child(environment)
	var ship:=Geometry.new();viewport.add_child(ship)
	for faction in [0,2]:
		var assembly: Dictionary=bindings.mido_travel.free_population.freighter_assemblies[str(faction)]
		var selector:=Detail.new()
		if not selector.configure_assembly(bindings,assembly):check(false,selector.error);break
		var distances: Array=[25000,45000] if faction==0 else [35000,60000]
		for band in [0.0,0.5,1.0]:
			var factor: float=0.5 if band==0.0 else 0.75 if band==0.5 else 1.0
			for index in 2:
				var squared: float=Detail.single(Detail.single(float(distances[index]*distances[index]))*factor)
				check(selector.select(squared,band)=={"visible":true,"level":index},"Ordinary freighter LOD changed at equality")
				check(selector.select(squared+512,band)=={"visible":true,"level":index+1},"Ordinary freighter LOD ignored its source distance")
		check(selector.select(40000000000.0,1.0).visible,"Ordinary freighter gained fighter distance culling")
		if not ship.build_population_assembly(assembly,library,visuals,bindings):check(false,ship.error);break
		check(ship.levels.size()==3 and ship.get_meta("source_ship_id")==15 and ship.engine_glow==null,"Ordinary freighter lost its special three-level assembly")
		var ids: Array=[17065,17066,17067] if faction==0 else [17060,17062,17063]
		var children: Array=[[17070,17074,17069],[17070],[17070]] if faction==0 else [[17061,17064],[],[]]
		for index in 3:
			var level: Node3D=ship.levels[index]
			check(not level.visible and level.get_meta("source_resource_id")==ids[index],"Ordinary freighter used another original body mesh")
			var parts: Array=level.get_children().filter(func(node):return node.has_meta("source_resource_id"))
			check(parts.map(func(node):return node.get_meta("source_resource_id"))==children[index],"Ordinary freighter lost or duplicated a light/engine child")
			check(parts.all(func(node):return node.transform==Transform3D.IDENTITY),"Ordinary freighter changed an authored child transform")
		for index in 3:
			check(ship.apply_selection({"visible":true,"level":index}),ship.error)
			check(ship.levels.filter(func(node):return node.visible).size()==1 and ship.levels[index].visible,"Ordinary freighter rendered overlapping levels")
			if DisplayServer.get_name()!="headless":
				var image:=await rendered(viewport)
				var foreground:=0;var background:=image.get_pixel(0,0)
				for y in range(0,image.get_height(),2):
					for x in range(0,image.get_width(),2):
						var pixel:=image.get_pixel(x,y)
						if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:foreground+=1
				check(foreground>200,"Original ordinary freighter geometry did not render")
				if args.size()==4:
					DirAccess.make_dir_recursive_absolute(args[3])
					check(image.save_png(args[3].path_join("ordinary-freighter-%d-lod-%d.png"%[faction,index]))==OK,"Ordinary freighter capture failed")
		var changed:=assembly.duplicate(true);changed.body_resource_ids[0]=17049
		check(not ship.build_population_assembly(changed,library,visuals,bindings) and ship.get_child_count()==0,"Invalid faction assembly left partial geometry")
		check(not selector.configure_assembly(bindings,changed) and not selector.is_configured(),"Invalid faction assembly retained old LOD state")
	ship.free();viewport.free()
