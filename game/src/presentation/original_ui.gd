extends RefCounted
## Shared original atlas artwork and bitmap glyphs. No replacement UI artwork.
const Atlas=preload("res://src/content/atlas_region.gd")
const Metrics=preload("res://src/content/image_font.gd")
var error:=""
var sprites:={}
var styles:={}
var font: FontFile
var identity:={}

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	if library.manifest.get("content_id")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:return reject("Interface artwork belongs to another content identity")
	var rules: Dictionary=bindings.mido_travel.get("map",{}).get("ui",{})
	if rules.is_empty():return reject("Original interface atlas mappings are unavailable")
	var loaded:=load_sprites(library,bindings,visuals,{"ui":rules,"faction_image_id":int(rules.faction_image_ids[0])})
	if loaded.is_empty():return false
	var metrics:=Metrics.new()
	if not metrics.open_selected(library,bindings):return reject(metrics.error)
	var prepared:=metrics.create_font(visuals)
	if prepared==null:return reject(metrics.error)
	sprites=loaded;font=prepared;styles={}
	for mobile in [false,true]:
		var height:=44 if mobile else 30
		var selected:={"panel":panel_style(sprites,rules,1.0 if mobile else 0.5)}
		for pressed in [false,true]:
			var ids: Array=rules.pressed_button_images if pressed else rules.button_images
			selected["pressed" if pressed else "normal"]=button_style(sprites,ids,height)
			ids=ids.duplicate();ids[0]=rules.pressed_back_image_id if pressed else rules.back_image_id
			selected["back_pressed" if pressed else "back_normal"]=button_style(sprites,ids,height)
		styles[mobile]=selected
	identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	return true

func apply_button(button: Button,mobile: bool,back:=false) -> void:
	var prefix:="back_" if back else ""
	for state in ["normal","hover","disabled","focus"]:button.add_theme_stylebox_override(state,styles[mobile][prefix+"normal"])
	for state in ["pressed","hover_pressed"]:button.add_theme_stylebox_override(state,styles[mobile][prefix+"pressed"])
	button.add_theme_font_size_override("font_size",20 if mobile else 14)
	button.custom_minimum_size.y=44 if mobile else 30

func reject(message: String) -> bool:error=message;return false

func load_sprites(library: RefCounted, bindings: RefCounted, visuals: RefCounted, state: Dictionary) -> Dictionary:
	var ids: Array=state.ui.button_images+state.ui.pressed_button_images
	for key in state.ui:
		if key.ends_with("_image_id"):ids.append(int(state.ui[key]))
	ids.append(state.faction_image_id)
	for row in state.ui.legend:ids.append(int(row.image_id))
	var result:={};var pixels:={};var metadata:={};var atlas:=Atlas.new()
	for value in ids:
		var id:=int(value)
		if result.has(id):continue
		var alias: Dictionary=bindings.resolve_image_region(id)
		if alias.is_empty():reject(bindings.error);return {}
		var resource: String=state.ui.atlas_resources.get(str(int(alias.texture_id)),"")
		if resource.is_empty():reject("Map sprite has no supported display atlas");return {}
		if not pixels.has(resource):
			var bytes: PackedByteArray=library.read_resource(resource,Atlas.MAX_BYTES)
			if bytes.is_empty():reject(library.error);return {}
			var image: Image=visuals.load_image(resource)
			if image==null:reject(visuals.error);return {}
			pixels[resource]=ImageTexture.create_from_image(image);metadata[resource]=bytes
		var region:=atlas.region(metadata[resource],int(alias.region))
		if region.is_empty() or pixels[resource].get_size()!=Vector2(region.get("size",Vector2i.ZERO)):
			reject("Map atlas pixels and source region differ: "+atlas.error);return {}
		var texture:=AtlasTexture.new();texture.atlas=pixels[resource];texture.region=Rect2(region.rect);texture.filter_clip=true
		texture.set_meta("source_image_id",id);texture.set_meta("source_resource",resource);texture.set_meta("source_region",int(alias.region))
		result[id]=texture
	return result

static func button_style(sprites: Dictionary, ids: Array, height: int) -> StyleBoxTexture:
	var pieces: Array=[];var width:=0;var source_height:=0
	for id in ids:
		var image: Image=sprites[int(id)].get_image();pieces.append(image);width+=image.get_width();source_height=maxi(source_height,image.get_height())
	var image:=Image.create(width,source_height,false,Image.FORMAT_RGBA8);var offset:=0
	for piece in pieces:image.blit_rect(piece,Rect2i(Vector2i.ZERO,piece.get_size()),Vector2i(offset,0));offset+=piece.get_width()
	var scale:=float(height)/source_height
	image.resize(roundi(width*scale),height,Image.INTERPOLATE_LANCZOS)
	var style:=StyleBoxTexture.new();style.texture=ImageTexture.create_from_image(image)
	style.texture_margin_left=roundi(pieces[0].get_width()*scale);style.texture_margin_right=roundi(pieces[2].get_width()*scale)
	style.content_margin_left=16;style.content_margin_right=12;style.content_margin_top=3;style.content_margin_bottom=3
	return style

static func panel_style(sprites: Dictionary, rules: Dictionary, scale: float) -> StyleBoxTexture:
	var background: Image=sprites[int(rules.panel_background_image_id)].get_image()
	var corner: Image=sprites[int(rules.panel_corner_image_id)].get_image()
	var edge: Image=sprites[int(rules.panel_edge_image_id)].get_image()
	var width:=corner.get_width();var extent:=width*2+background.get_width()
	var glow:=edge.get_height()
	var assembled:=Image.create(extent,extent,false,Image.FORMAT_RGBA8)
	for y in range(glow,extent-glow,background.get_height()):
		for x in range(glow,extent-glow,background.get_width()):
			var part:=Vector2i(mini(background.get_width(),extent-glow-x),mini(background.get_height(),extent-glow-y))
			assembled.blit_rect(background,Rect2i(Vector2i.ZERO,part),Vector2i(x,y))
	edge.resize(extent-width*2,edge.get_height(),Image.INTERPOLATE_LANCZOS)
	var positions:=[Vector2i.ZERO,Vector2i(extent-width,0),Vector2i(extent-width,extent-width),Vector2i(0,extent-width)]
	var edge_positions:=[Vector2i(width,0),Vector2i(extent-edge.get_height(),width),Vector2i(width,extent-edge.get_height()),Vector2i(0,width)]
	for index in 4:
		assembled.blend_rect(corner,Rect2i(Vector2i.ZERO,corner.get_size()),positions[index])
		assembled.blend_rect(edge,Rect2i(Vector2i.ZERO,edge.get_size()),edge_positions[index])
		corner.rotate_90(CLOCKWISE);edge.rotate_90(CLOCKWISE)
	assembled.resize(roundi(extent*scale),roundi(extent*scale),Image.INTERPOLATE_LANCZOS)
	var style:=StyleBoxTexture.new();style.texture=ImageTexture.create_from_image(assembled)
	style.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,roundi(width*scale));style.set_content_margin(side,12)
		# Source panel type 7 places each border's glow outside its content rect.
		style.set_expand_margin(side,roundi(glow*scale))
	style.set_meta("source_image_ids",[int(rules.panel_background_image_id),int(rules.panel_corner_image_id),int(rules.panel_edge_image_id)])
	return style
