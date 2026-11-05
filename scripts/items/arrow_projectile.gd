extends CharacterBody3D

## Flèche balistique à gravité sphérique ; se plante sur impact (hors créatures).

const GRAVITY := 18.0
const FLY_LIFE := 8.0
const PLANTED_LIFE := 90.0
const EMBED := 0.12

var power: float = 1.0
var damage_mult: float = 1.0
var shooter: Node

var _planet: Node3D
var _flying := true
var _planted := false
var _life := FLY_LIFE
var _last_dir := Vector3.FORWARD


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 8
	_planet = get_tree().get_first_node_in_group(&"planet") as Node3D
	if shooter is CollisionObject3D:
		add_collision_exception_with(shooter)


func launch(origin: Vector3, direction: Vector3, speed: float) -> void:
	global_position = origin
	var dir := direction.normalized()
	if dir.length_squared() < 0.001:
		dir = Vector3.FORWARD
	_last_dir = dir
	velocity = dir * speed
	_flying = true
	_planted = false
	_life = FLY_LIFE
	_orient_along(dir)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _planted or not _flying:
		return
	var up := _surface_up()
	velocity += -up * GRAVITY * delta
	if velocity.length_squared() > 0.0001:
		_last_dir = velocity.normalized()
	var hit := move_and_collide(velocity * delta)
	_orient_along(_last_dir)
	if hit == null:
		return
	_on_hit(hit)


func _on_hit(hit: KinematicCollision3D) -> void:
	if not _flying:
		return
	var node := hit.get_collider() as Node
	var creature := _creature_from(node)
	if creature != null and creature != shooter:
		if creature.has_method(&"receive_hit"):
			creature.call(&"receive_hit", "wooden_arrow", damage_mult)
		queue_free()
		return
	_plant(hit)


func _plant(hit: KinematicCollision3D) -> void:
	_flying = false
	_planted = true
	_life = PLANTED_LIFE
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	var dir := _last_dir
	if dir.length_squared() < 0.001:
		dir = -hit.get_normal()
	if dir.length_squared() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	# Pointe modèle en −Y ; avec basis_y = −dir la pointe avance selon dir.
	const TIP := 0.36
	global_position = hit.get_position() - dir * (TIP - EMBED)
	_orient_along(dir)
	var host := hit.get_collider() as Node3D
	if host != null and is_instance_valid(host):
		var gt := global_transform
		var parent := get_parent()
		if parent != null:
			parent.remove_child(self)
		host.add_child(self)
		global_transform = gt


func _creature_from(node: Node) -> Node:
	var current := node
	while current != null:
		if current.is_in_group(&"creature"):
			return current
		current = current.get_parent()
	return null


func _orient_along(forward: Vector3) -> void:
	if forward.length_squared() < 0.0001:
		return
	var dir := forward.normalized()
	var up := _surface_up()
	var right := dir.cross(up)
	if right.length_squared() < 0.0001:
		right = dir.cross(Vector3.RIGHT)
	right = right.normalized()
	# wooden_arrow.glb : pointe en −Y.
	var basis_y := -dir
	var basis_z := right.cross(basis_y).normalized()
	var basis_x := basis_y.cross(basis_z).normalized()
	global_transform.basis = Basis(basis_x, basis_y, basis_z)


func _surface_up() -> Vector3:
	if _planet == null:
		return Vector3.UP
	var offset := global_position - _planet.global_position
	if offset.length_squared() < 0.001:
		return Vector3.UP
	return offset.normalized()
