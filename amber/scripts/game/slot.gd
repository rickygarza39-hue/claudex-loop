class_name Slot
extends RefCounted
## One participant (human or bot) for the whole match, across survivor and elite lives.

var id := 0
var name := ""
var is_human := false
var side := Defs.Side.SURVIVOR
var duo: Duo = null
var role := Defs.Role.ENGINEER
var ktype := Defs.K.TRACKER
var elite := false
var actor: Actor = null
var outcome := ""        # "", "escaped", "caught", "turned"
var outcome_time := 0.0
var elite_level := 0
var elite_xp := 0
var perks := {}          # branch name -> rank
var pending_perk := false
var thief := false
var respawn_at := -1.0
var stats := {"catches": 0, "stuns": 0, "parries": 0, "earned": 0, "assists": 0, "elite_catches": 0}


func display_name() -> String:
	return name


func is_playing_survivor() -> bool:
	return side == Defs.Side.SURVIVOR and outcome == ""


func perk(branch: String) -> int:
	return perks.get(branch, 0)
