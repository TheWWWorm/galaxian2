extends RefCounted
## Shared preparation for the recovered opening's baseline radio layout.
## This is an explicit verified fixture, not automatic source device detection.
const Metrics = preload("res://src/content/image_font.gd")
const Layout = preload("res://src/presentation/source_text_layout.gd")
const Definitions = preload("res://src/content/dialogue_definitions.gd")
const Portraits = preload("res://src/presentation/portrait_compositor.gd")
var error := ""
var line_counts := []
var speakers := {}
var portrait_diagnostics := {}

func prepare(library: RefCounted, bindings: RefCounted, visuals: RefCounted = null, campaign_cursor: int = 0) -> bool:
	error="";line_counts=[];speakers={};portrait_diagnostics={}
	if library==null or bindings==null:return fail("Open imported content and resource bindings first")
	var dialogue: Dictionary=Definitions.select(bindings,campaign_cursor)
	if not Definitions.valid_parameters(dialogue,campaign_cursor):return fail("Scene radio declarations are unavailable")
	var metrics := Metrics.new()
	if not metrics.open_selected(library,bindings,0):return fail(metrics.error)
	var layout := Layout.new()
	var margin := 15 if library.active_language in ["ja","zs","zt"] else 5
	if not layout.configure_from_bindings(metrics,350,margin,bindings):return fail(layout.error)
	var counts := [];var resolved := {};var diagnostics := {}
	var composer := Portraits.new()
	for event in dialogue.events:
		var text_id := int(event.text_id)
		if text_id<0 or text_id>=library.strings.size():return fail("Opening text is outside the selected language")
		var lines := layout.wrap(library.strings[text_id])
		if not layout.error.is_empty():return fail(layout.error)
		counts.append(lines.size())
		var id := int(event.speaker_id)
		if resolved.has(id) or bindings.speaker_bindings.is_empty():continue
		var speaker_name: String = bindings.resolve_speaker_name(id,library)
		if not bindings.error.is_empty():return fail(bindings.error)
		resolved[id]={"name":speaker_name}
		if visuals!=null and not visuals.base_content_id.is_empty() and not bindings.portrait_layers.is_empty():
			var portrait := composer.compose(library,bindings,visuals,id,"baseline")
			if portrait.is_empty():diagnostics[id]=composer.error
			else:resolved[id].portrait=ImageTexture.create_from_image(portrait.image)
	line_counts=counts;speakers=resolved;portrait_diagnostics=diagnostics
	return true

func fail(message: String) -> bool:
	error=message;line_counts=[];speakers={};portrait_diagnostics={}
	return false
