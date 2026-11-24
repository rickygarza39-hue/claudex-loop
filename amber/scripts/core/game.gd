class_name Game
extends RefCounted
## Settings carried from the menu into a match, plus command-line options.
## Everything is static, so this works as a global without an autoload: the game
## still runs when its files are copied into another Godot project.

static var config := {
	"seed": 0,
	"side": Defs.Side.SURVIVOR,
	"role": Defs.Role.ENGINEER,
	"killer": Defs.K.TRACKER,
	"card": Defs.Card.PULSE,
	"spectate": false,
}
static var args := {}
static var last_result := {}
static var mouse_sensitivity := 0.0025
static var invert_y := false


static func _static_init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"


static func arg(key: String, default_value: String = "") -> String:
	return args.get(key, default_value)


static func has_arg(key: String) -> bool:
	return args.has(key)
