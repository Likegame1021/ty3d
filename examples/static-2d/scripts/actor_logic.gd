extends RefCounted
func direction_for(motion: Vector2, previous: int) -> int:
 if motion.length_squared() < 0.001:
  return previous
 var angle := atan2(motion.x, motion.y)
 var previous_angle := float(previous) * PI / 4.0
 if absf(wrapf(angle - previous_angle, -PI, PI)) < deg_to_rad(29):
  return previous
 return posmod(roundi(angle / (PI / 4.0)), 8)
func frame_at(time: float, count: int, fps: float, looping: bool = true) -> int:
 var frame := floori(time * fps)
 return posmod(frame, count) if looping else mini(frame, count - 1)
