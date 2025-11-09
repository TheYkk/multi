extends CharacterBody2D

# Same as any other movement script
# Uses MultiplayerSynchronizer to sync position

const SPEED = 250.0
const PUSH_FORCE = 220.0
const PUSH_DECAY_RATE = 620.0
const MAX_PUSH_SPEED = 300.0
var message_rect: ColorRect
var external_velocity := Vector2.ZERO


func _enter_tree() -> void:
  set_multiplayer_authority(name.to_int())

func _ready() -> void:
  # Resolve UI rectangle after one frame to ensure scene tree is ready
  await get_tree().process_frame
  message_rect = get_node_or_null("../UI/Control/MessageRect")
  if message_rect == null:
    var root := get_tree().root
    message_rect = root.get_node_or_null("NodeTunnelDemo/UI/Control/MessageRect")

  # Only the server (host) broadcasts the message/color every 100ms
  if multiplayer.is_server() and is_multiplayer_authority():
    var t := Timer.new()
    t.wait_time = 0.1
    t.one_shot = false
    t.autostart = true
    add_child(t)
    t.timeout.connect(_broadcast_color_message)


func _physics_process(delta: float) -> void:
  if !is_multiplayer_authority():
    return
  
  var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
  var has_input := input_dir.length_squared() > 0.0
  velocity = input_dir * SPEED + external_velocity
  
  move_and_slide()
  
  if has_input:
    _push_colliding_players()
  
  _decay_external_velocity(delta)


func _push_colliding_players() -> void:
  var pushed_authorities: Dictionary = {}
  
  for i in range(get_slide_collision_count()):
    var collision := get_slide_collision(i)
    if collision == null:
      continue
    
    var collider := collision.get_collider()
    if collider == null or collider == self:
      continue
    if !(collider is CharacterBody2D):
      continue
    if !collider.has_method("receive_external_push"):
      continue
    
    var target_authority: int = collider.get_multiplayer_authority()
    if target_authority == 0 or target_authority == multiplayer.get_unique_id():
      continue
    if pushed_authorities.has(target_authority):
      continue
    
    var push_direction := -collision.get_normal()
    if push_direction.length_squared() == 0.0:
      continue
    
    pushed_authorities[target_authority] = true
    var push_vector := push_direction.normalized() * PUSH_FORCE
    collider.rpc_id(target_authority, &"receive_external_push", push_vector)


func _decay_external_velocity(delta: float) -> void:
  if external_velocity.length_squared() == 0.0:
    return
  
  external_velocity = external_velocity.move_toward(Vector2.ZERO, PUSH_DECAY_RATE * delta)
  if external_velocity.length_squared() < 1.0:
    external_velocity = Vector2.ZERO

func _broadcast_color_message() -> void:
  # Simple time-based varying color; encoded as hex RGB string without '#'
  var t := Time.get_ticks_usec()
  var r := int((t >> 0) & 0xFF)
  var g := int((t >> 8) & 0xFF)
  var b := int((t >> 16) & 0xFF)
  var hex := "%02x%02x%02x" % [r, g, b]
  rpc(&"receive_color_message", hex)

@rpc("any_peer", "unreliable")
func receive_color_message(hex_message: String) -> void:
  # Only clients should handle this
  if multiplayer.is_server():
    return

  # Use built-in HTML hex parsing (adds alpha=1.0 if not present)
  var col := Color.html(hex_message)
  if is_instance_valid(message_rect):
    message_rect.color = col


@rpc("any_peer")
func receive_external_push(push_vector: Vector2) -> void:
  if !is_multiplayer_authority():
    return
  
  external_velocity += push_vector
  if external_velocity.length() > MAX_PUSH_SPEED:
    external_velocity = external_velocity.normalized() * MAX_PUSH_SPEED
