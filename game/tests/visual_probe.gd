extends SceneTree
const Library = preload("res://src/content/library.gd")
const VisualLibrary = preload("res://src/content/visual_library.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Supply base and visual directories")
		quit(2)
		return
	var library := Library.new()
	var visuals := VisualLibrary.new()
	if not library.open(args[0]) or not visuals.open(args[1], library.manifest):
		push_error(library.error + visuals.error)
		quit(1)
		return
	var errors: Array = []
	var levels := 0
	for name in visuals.textures:
		var image := visuals.load_image(name)
		if image == null:
			errors.append({"path": name, "error": visuals.error})
		else:
			levels += image.get_mipmap_count() + 1
	print(JSON.stringify({"edition": library.manifest.profile.edition, "textures": visuals.textures.size(),
		"decoded_levels": levels, "errors": errors}, "  "))
	quit(0 if errors.is_empty() else 1)
