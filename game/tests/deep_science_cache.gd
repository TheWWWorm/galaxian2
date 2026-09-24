extends SceneTree
## Detached cache/restore boundaries. These contexts do not earn a journey,
## profile medal or campaign transition.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/deep_science_stock_definitions.gd")
const Cache=preload("res://src/simulation/lounge_cache.gd")
const Stock=preload("res://src/simulation/station_stock.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const SETTINGS={"difficulty":1.0,"valkyrie_owned":false,"supernova_owned":false,
	"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
var checks:=0
var failures:=0

func _initialize():
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, binding and visual paths")
	else:verify(args)
	print("Deep Science native cache: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var random:=Random.new();random.seed_from(4096)
	var context:={"campaign_cursor":23,"station_id":10,"rank":0,"reputation":{"axes":[0,0],"override":-1}}
	var cache:=Cache.new()
	if not cache.configure(bindings):check(false,cache.error);return
	var empty:=cache.snapshot()
	if not Definitions.available(bindings):
		check(not cache.select_location(bindings,cat,library,context,SETTINGS,random.snapshot(),1789100000) and cache.snapshot()==empty,"Earlier packs invented special station stock")
		return
	for cursor in [23,24]:
		context.campaign_cursor=cursor;cache=Cache.new();check(cache.configure(bindings),cache.error)
		if not cache.select_location(bindings,cat,library,context,SETTINGS,random.snapshot(),1789100000):check(false,cache.error);return
		var saved:=cache.snapshot();var location:=cache.location(10)
		check(location.stock.context.get("all_base_medals_gold")==false and location.stock.context.size()==9,"The native fresh profile did not retain its grounded medal result")
		check(location.stock.random==location.population.initial_random,"Station stock did not precede contact sampling")
		var archive:=Archive.new();var restored: RefCounted=archive._locations(bindings,cat,library,saved)
		check(restored!=null and restored.snapshot()==saved,"Native station10 cache did not restore exactly: "+archive.error)
		var forked: RefCounted=cache.fork()
		check(forked.snapshot()==saved,"Forking changed retained station10 state")
		check(forked.select_location(bindings,cat,library,context,SETTINGS,saved.random,1789100999) and forked.location(10)==location,"A revisit regenerated retained station stock or contacts")
		check(cache.snapshot()==saved,"A forked selection changed the original cache")
		verify_foreign_medals(bindings,cat,library,cache,location)
	# Ordinary contexts remain the prior eight-field schema.
	cache=Cache.new();check(cache.configure(bindings),cache.error)
	context.campaign_cursor=18;context.station_id=98
	if not cache.select_location(bindings,cat,library,context,SETTINGS,random.snapshot(),1789100000):check(false,cache.error);return
	check(cache.location(98).stock.context.size()==8 and not cache.location(98).stock.context.has("all_base_medals_gold"),"Special medal input leaked into ordinary station stock")
	var before:=cache.snapshot();context.station_id=10;context.campaign_cursor=45
	check(not cache.select_location(bindings,cat,library,context,SETTINGS,random.snapshot(),1789100000) and cache.snapshot()==before,"An unsupported later profile changed the current cache")

func verify_foreign_medals(bindings: RefCounted,cat: RefCounted,library: RefCounted,cache: RefCounted,location: Dictionary):
	var stock:=Stock.new();var context: Dictionary=location.stock.context.duplicate(true);context.all_base_medals_gold=true
	if not stock.prepare(bindings,cat,context,location.stock.initial_random,location.stock.unix_seconds):check(false,stock.error);return
	var contacts:=Contacts.new()
	if not contacts.prepare(bindings,cat,library,location.population.context,stock.snapshot().random,location.population.initial_history):check(false,contacts.error);return
	var target:=Cache.new();check(target.configure(bindings),target.error);var before:=target.snapshot()
	check(not target.remember(contacts,stock) and target.error.contains("native career") and target.snapshot()==before,"An original/global all-gold profile entered a fresh native cache")
	var stock_copy:=Stock.new();check(stock_copy.restore(bindings,cat,stock.snapshot()),stock_copy.error)
	var contacts_copy:=Contacts.new();check(contacts_copy.restore(bindings,cat,library,contacts.snapshot()),contacts_copy.error)
	# Each component is source-valid. Only the archive's native profile boundary
	# should refuse this otherwise self-consistent foreign retained medal state.
	var forged: Dictionary=cache.snapshot();var population:=contacts.snapshot();var offers:={}
	for contact in population.contacts:
		if not contact.offer.is_empty():offers[int(contact.contact_id)]={"offer":contact.offer.duplicate(true),"consumed":false}
	forged.locations=[{"station_id":10,"population":population,"offers":offers,"stock":stock.snapshot()}]
	forged.history=population.history.duplicate();forged.random=population.random.duplicate(true)
	var archive:=Archive.new()
	check(archive._locations(bindings,cat,library,forged)==null and archive.error.contains("native career"),"Archive admitted source-valid all-gold stock from an unsupported profile: "+archive.error)

func check(condition: bool,message: String):
	checks+=1
	if not condition:failures+=1;printerr("FAIL: "+message)
