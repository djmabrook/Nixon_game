class_name SurfInput
extends RefCounted
## What the rider wants, from any device. The Surfer only reads this, never Input directly,
## so a touch layer (iPhone) only has to fill `touch_*` and nothing else changes.
##
## Keyboard + mouse:  A / D carve · W tuck (go faster) · S brake / slide · Space hold to crouch,
##                    release to pop · Shift also tucks · mouse looks around.
## Gamepad:           left stick carve (forward = tuck, back = brake) · A hold and release to pop ·
##                    RT or B tuck · right stick looks around.
## In the air the same controls spin (left/right) and flip (forward/back); tuck grabs the board.

## Carve, -1 (left) to 1 (right). Smoothed for keys, shaped for sticks.
var steer := 0.0
## Forward/back lean, -1 (brake) to 1 (tuck).
var lean := 0.0
## Holding a tuck (lean forward or the tuck button).
var tuck := false
## The pop button is held / was just pressed / was just released this physics frame.
var jump_held := false
var jump_pressed := false
var jump_released := false

## Touch controls write here (see surf/README.md). While `touch_active`, keys and pads still work
## and the larger input wins.
var touch_active := false
var touch_steer := 0.0
var touch_lean := 0.0
var touch_tuck := false
var touch_jump := false

## Seconds for a key press to reach full carve (sticks are immediate).
var key_ramp := 0.12
## Stick response: >1 gives fine control near the centre.
var stick_curve := 1.4

var _was_jump := false
var _key_steer := 0.0
var _key_lean := 0.0


func update(delta: float, enabled := true) -> void:
	if not enabled:
		steer = move_toward(steer, 0.0, delta * 8.0)
		lean = 0.0
		tuck = false
		jump_held = false
		jump_pressed = false
		jump_released = _was_jump
		_was_jump = false
		return
	# Keys: ramp so a tap is a nudge and a hold is a full carve.
	var kx := _key(&"move_right") - _key(&"move_left")
	var ky := _key(&"move_up") - _key(&"move_down")
	_key_steer = move_toward(_key_steer, kx, delta / key_ramp if kx != 0.0 else delta / (key_ramp * 0.6))
	_key_lean = move_toward(_key_lean, ky, delta / key_ramp)
	# Sticks: the raw axis strength, shaped.
	var sx := _stick(&"move_left", &"move_right")
	var sy := _stick(&"move_down", &"move_up")
	steer = _bigger(_key_steer, sx)
	lean = _bigger(_key_lean, sy)
	var j := Input.is_action_pressed(&"interact")
	var tk := Input.is_action_pressed(&"run")
	if touch_active:
		steer = _bigger(steer, touch_steer)
		lean = _bigger(lean, touch_lean)
		tk = tk or touch_tuck
		j = j or touch_jump
	steer = clampf(steer, -1.0, 1.0)
	lean = clampf(lean, -1.0, 1.0)
	tuck = tk or lean > 0.35
	jump_held = j
	jump_pressed = j and not _was_jump
	jump_released = _was_jump and not j
	_was_jump = j


func _key(action: StringName) -> float:
	# Keyboard events only: Input.get_action_strength mixes in the stick, which _stick handles.
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and Input.is_physical_key_pressed((e as InputEventKey).physical_keycode):
			return 1.0
	return 0.0


func _stick(neg: StringName, pos: StringName) -> float:
	var v := 0.0
	for pad in Input.get_connected_joypads():
		for action in [neg, pos]:
			for e in InputMap.action_get_events(action):
				if e is InputEventJoypadMotion:
					var m := e as InputEventJoypadMotion
					var a := Input.get_joy_axis(pad, m.axis)
					if signf(a) == signf(m.axis_value) and absf(a) > InputMap.action_get_deadzone(action):
						var s := (absf(a) - InputMap.action_get_deadzone(action)) / (1.0 - InputMap.action_get_deadzone(action))
						v += pow(clampf(s, 0.0, 1.0), stick_curve) * (1.0 if action == pos else -1.0)
	return clampf(v, -1.0, 1.0)


static func _bigger(a: float, b: float) -> float:
	return a if absf(a) >= absf(b) else b
