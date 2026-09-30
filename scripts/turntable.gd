class_name Turntable
extends Node3D
## Slowly spins whatever is attached to it (used for unit portraits).

var speed: float = 0.7


func _process(dt: float) -> void:
	rotation.y += dt * speed
