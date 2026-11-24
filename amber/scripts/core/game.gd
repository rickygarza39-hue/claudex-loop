extends Node
## Autoload "Game": settings carried from the menu into a match, plus command-line options.

var config := {
	"seed": 0,
	"side": Defs.Side.SURVIVOR,
	"role": Defs.Role.ENGINEER,
	"killer": Defs.K.TRACKER,
	"card": Defs.Card.PULSE,
	"spectate": false,
}
var args := {}
var last_result := {}
var mouse_sensitivity := 0.0025
var invert_y := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func arg(key: String, default_value: String = "") -> String:
	return args.get(key, default_value)


func has_arg(key: String) -> bool:
	return args.has(key)
