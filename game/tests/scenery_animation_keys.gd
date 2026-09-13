extends SceneTree
const Keys = preload("res://src/content/scenery_animation_keys.gd")
const AEM = preload("res://src/content/aem.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Scenery animation key checks: %d failures" % failures)
	quit(1 if failures else 0)

func track(width: int, values: Array) -> Dictionary:
	return {"dimensions":width,"keys":PackedFloat32Array(values)}

func surface(groups: Dictionary) -> Dictionary:
	return {"tracks":groups}

func check_synthetic() -> void:
	var compiler := Keys.new()
	var raw := [surface({"translation":[track(1,[0,0,10,10]),track(1,[0,1,10,3]),track(1,[0,2,10,4])],
		"rotation":[track(3,[0,0,0,0,10,0.3,0.6,0.9])],"scale":[track(3,[0,1,2,3,10,4,5,6])],"scalar":[track(1,[0,50,10,200])]})]
	var before: Array = raw.duplicate(true)
	var compiled := compiler.prepare(raw)
	check(not compiled.is_empty(),compiler.error)
	if compiled.is_empty():return
	check(compiled.surfaces[0].times==PackedInt32Array([0,10]),"Source key times changed")
	check(row(compiled,0)==PackedFloat32Array([0,2,-1,0,0,0,1,2,3,0.5]),"Split translation conversion, defaults or scalar percentage changed")
	check(row(compiled,1)==PackedFloat32Array([10,4,-3,0.3,0.6,0.9,4,5,6,2]),"Final keyed values changed or scalar was clamped")
	check(raw==before,"Key preparation changed source AEM channels")
	compiled.surfaces[0].values[0]=999
	check(row(compiler.prepare(raw),0)[0]==0,"Prepared keys share mutable state")
	# A scalar key adds a record between rotation keys, so its intermediate
	# rotation is prepared linearly before runtime quaternion sampling.
	raw=[surface({"translation":[track(3,[0,0,0,0,10,100,200,300])],
		"rotation":[track(1,[]),track(1,[]),track(1,[5,7])],
		"scale":[track(3,[10,2,2,2])],"scalar":[track(1,[2,0])]})]
	compiled=compiler.prepare(raw)
	check(not compiled.is_empty(),compiler.error)
	if not compiled.is_empty():
		check(compiled.surfaces[0].times==PackedInt32Array([0,2,5,10]),"Channels did not share their integer time grid")
		check(row(compiled,0)==PackedFloat32Array([0,0,0,0,0,0,1,1,1,1]),"First record lost its defaults")
		check(row(compiled,1)==PackedFloat32Array([20,40,60,0,0,2.8,1.2,1.2,1.2,0]),"Inserted key did not interpolate all existing channels")
		check(row(compiled,2)==PackedFloat32Array([50,100,150,0,0,7,1.5,1.5,1.5,0]),"Earlier gap or later scalar fill changed")
		check(row(compiled,3)==PackedFloat32Array([100,200,300,0,0,7,2,2,2,0]),"Late channel values did not carry forward")
	# Repeated raw times collapse after truncation; later values replace the
	# same integer-time component. A new earlier key keeps fresh defaults.
	raw=[surface({"translation":[track(1,[1.1,4,1.9,9,10,10]),track(1,[]),track(1,[])],"scalar":[track(1,[0,100])]})]
	compiled=compiler.prepare(raw)
	check(compiled.surfaces[0].times==PackedInt32Array([0,1,10]) and row(compiled,0)[0]==0 and row(compiled,1)[0]==9,"Equal integer times or insertion before the first key changed")
	# Gap filling computes 1 - rounded ratio, not a fresh direct time ratio.
	raw=[surface({"translation":[track(3,[0,0,0,0,10,1,0,0])],"rotation":[track(3,[1,0,0,7])],"scalar":[track(1,[10,100])]})]
	compiled=compiler.prepare(raw)
	check(bits(row(compiled,1)[0])==0x3dccccd0,"Earlier gaps lost source complement-ratio rounding")
	# Both source paths flip zero signs. Build -0 from bits because the parser
	# can fold a decimal -0.0 literal into +0.0.
	var negative_zero := PackedByteArray([0,0,0,128]).decode_float(0)
	raw=[surface({"translation":[track(1,[]),track(1,[1,0.0,2,negative_zero]),track(1,[])]})]
	compiled=compiler.prepare(raw)
	check(bits(row(compiled,0)[2])==0x80000000 and bits(row(compiled,1)[2])==0,"Split-axis zero sign bits changed")
	var overflow := [surface({"translation":[track(3,[0,3e38,0,0,2,-3e38,0,0])],"rotation":[track(3,[1,0,0,0])]})]
	check(compiler.prepare(overflow).is_empty() and not compiler.error.is_empty(),"Overflowing gap interpolation published a table")
	var malformed := [surface({"translation":[track(1,[1,0,2,1])],"uv":[track(1,[1,0])]})]
	check(compiler.prepare(malformed).is_empty(),"Unsupported keyed UV layout accepted")
	var many := []
	for index in 1400:many.append(index);many.append(index)
	check(compiler.prepare([surface({"scalar":[track(1,many)]})]).is_empty() and "budget" in compiler.error,"Excessive preparation did not fail within the work budget")
	compiled=compiler.prepare(raw)
	check(not compiled.is_empty() and compiler.error.is_empty(),"Failed preparation contaminated the next request")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	var identifiers := {}
	for variant in bindings.scenery_effects.variants:
		for model in variant.model_ids:identifiers[int(model)]=true
	check(identifiers.size()==7,"Expected all seven distinct effect resources")
	var report := {}
	for identifier in identifiers:
		var path: String = bindings.resolve(identifier,"mesh")
		var reader := AEM.new()
		var decoded := reader.decode(library.read_resource(path,AEM.MAX_BYTES))
		if decoded.is_empty():check(false,reader.error);continue
		var compiler := Keys.new()
		var result := compiler.prepare(decoded.surfaces)
		if result.is_empty():check(false,compiler.error);continue
		check(result.surfaces.size()==decoded.surfaces.size(),"Prepared surface order changed")
		var rows := []
		for table in result.surfaces:
			check(table.values.size()==table.times.size()*Keys.WIDTH,"Incomplete prepared channel record")
			var digest := HashingContext.new();digest.start(HashingContext.HASH_SHA256)
			digest.update(table.times.to_byte_array());digest.update(table.values.to_byte_array())
			rows.append({"times":Array(table.times),"sha256":digest.finish().hex_encode()})
		report[str(identifier)]=rows
	var destination := OS.get_environment("GOF2_KEY_REPORT_DIR")
	if not destination.is_empty():
		var file := FileAccess.open(destination.path_join(library.manifest.profile.edition+"-native-keys.json"),FileAccess.WRITE)
		check(file!=null,"Cannot write native key comparison report")
		if file!=null:file.store_string(JSON.stringify(report,"\t")+"\n")
	print(library.manifest.profile.edition,": seven effect key tables prepared")

func row(result: Dictionary, index: int) -> PackedFloat32Array:
	return result.surfaces[0].values.slice(index*Keys.WIDTH,(index+1)*Keys.WIDTH)

func bits(value: float) -> int:
	return PackedFloat32Array([value]).to_byte_array().decode_u32(0)

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
