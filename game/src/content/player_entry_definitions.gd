extends RefCounted
## Resolve supported encounter entry differences from validated content.
## Shared player initialization consumes these rules without campaign switches.
const Departure=preload("res://src/content/station_departure_definitions.gd")
const FullHold=preload("res://src/content/full_hold_departure_definitions.gd")
const Pirate=preload("res://src/content/full_hold_pirate_definitions.gd")
const Training=preload("res://src/content/combat_training_weapon_definitions.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const KINDS={0:"opening",1:"arrival",2:"mining",4:"full_hold",7:"training"}
var error:=""
var cursor:=-1
var is_arrival:=false
var is_departure:=false
var uses_equipment:=false
var equipped_entry:={}
var _kind:=""
var _departure:={}
var _training:={}
var _pirate:={}

func configure(bindings: RefCounted, value: int) -> bool:
	error="";cursor=-1;is_arrival=false;is_departure=false;uses_equipment=false
	equipped_entry={};_kind="";_departure={};_training={};_pirate={}
	if bindings==null or not KINDS.has(value):return reject("Unsupported player entry")
	var kind: String=KINDS[value]
	var departure:=kind in ["mining","full_hold","training"]
	if departure and not Departure.parameters(bindings.station_departure):return reject("This profile has no supported first departure")
	if kind=="full_hold" and (not FullHold.parameters(bindings.full_hold_departure) or not FullHold.StationReturn.parameters(bindings.station_return)):return reject("This profile has no supported second mining departure")
	if kind=="training" and not Training.parameters(bindings.combat_training_weapons):return reject("This profile has no supported equipped training entry")
	cursor=value;_kind=kind;is_arrival=kind=="arrival";is_departure=departure;uses_equipment=kind=="training"
	if departure:_departure=(bindings.full_hold_departure if kind=="full_hold" else bindings.station_departure).duplicate(true)
	if uses_equipment:
		_training=bindings.combat_training_weapons.duplicate(true)
		equipped_entry=_training.player_entry.duplicate(true)
	if kind=="full_hold":_pirate=bindings.full_hold_pirate.duplicate(true)
	return true

func player_cache(parameters: Dictionary, seed: Dictionary, hull: int, capacities: Dictionary, reset:=false) -> Dictionary:
	if cursor<0:return {}
	if uses_equipment:return Cache.combat_training_cache(parameters,_training,seed,hull,capacities,reset)
	if is_departure:return Cache.departure_cache(parameters,_departure,seed,hull,capacities,reset)
	if reset:return {}
	return Cache.base_cache(parameters,seed,hull,capacities,cursor)

func contact_weapons(opening_weapon: Dictionary) -> Dictionary:
	if cursor<0:return {}
	var weapon:=opening_weapon
	if _kind=="full_hold" and not _pirate.is_empty():
		if not Pirate.parameters(_pirate):reject("Unsupported second-trip pirate weapon");return {}
		weapon=_pirate.primary_weapon
	return {"candidates":_training.npc_weapons.duplicate(true) if uses_equipment else [weapon.duplicate(true)],
		"enabled":_kind!="full_hold" or not _pirate.is_empty(),
		"context":{"campaign_cursor":cursor,"nonplayer_source":true} if uses_equipment else {}}

func reject(message: String) -> bool:
	error=message
	return false
