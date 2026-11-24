class_name Duo
extends RefCounted
## A survivor pair: shared money pot, scrap stash, base and radio station.

var id := 0
var name := ""
var color := Color.WHITE
var members: Array = []      # Slot
var money := 0
var scrap := 0
var base: Base = null
var known_items := {}        # ItemPickup -> true (discovered by either partner)
var worse_start := false
var cell: Dictionary = {}
var lockdown_used := false
var earned_total := 0


func living() -> Array:
	var out: Array = []
	for s in members:
		if s.outcome == "" and s.side == Defs.Side.SURVIVOR and s.actor != null:
			out.append(s)
	return out


func partner_of(s: Slot) -> Slot:
	for o in members:
		if o != s:
			return o
	return null


func active() -> bool:
	return not living().is_empty()
