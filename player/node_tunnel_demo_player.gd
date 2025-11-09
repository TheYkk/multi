extends CharacterBody2D

# Same as any other movement script
# Uses MultiplayerSynchronizer to sync position

const SPEED = 250.0
const PUSH_FORCE = 220.0
const PUSH_DECAY_RATE = 620.0
const MAX_PUSH_SPEED = 300.0
const DEFAULT_SPRITE_COLOR = Color(1, 1, 1, 1)
const DEFAULT_LABEL_COLOR = Color(1, 1, 1, 1)
const LABEL_LIGHTEN = 0.35
var message_rect: ColorRect
var external_velocity := Vector2.ZERO
@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel


func _connect_once(source_signal: Signal, target_callable: Callable) -> void:
  if !source_signal.is_connected(target_callable):
    source_signal.connect(target_callable)


func _enter_tree() -> void:
  set_multiplayer_authority(name.to_int())

func _ready() -> void:
  _initialize_identity()

  # Resolve UI rectangle after one frame to ensure scene tree is ready
  await get_tree().process_frame
  message_rect = get_node_or_null("../UI/Control/MessageRect")
  if message_rect == null:
    var root := get_tree().root
    message_rect = root.get_node_or_null("NodeTunnelDemo/UI/Control/MessageRect")

  # Only the server (host) broadcasts the message/color every 100ms
  # if multiplayer.is_server() and is_multiplayer_authority():
  #   var t := Timer.new()
  #   t.wait_time = 0.1
  #   t.one_shot = false
  #   t.autostart = true
  #   add_child(t)
  #   t.timeout.connect(_broadcast_color_message)


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
  var pushed: Dictionary = {}
  for i in range(get_slide_collision_count()):
    var collision := get_slide_collision(i)
    if collision == null:
      continue
    var collider := collision.get_collider()
    if collider == null or collider == self or !(collider is CharacterBody2D) or !collider.has_method("receive_external_push"):
      continue
    var target: int = collider.get_multiplayer_authority()
    if target == 0 or target == multiplayer.get_unique_id() or pushed.has(target):
      continue
    var normal := -collision.get_normal()
    if normal.length_squared() == 0.0:
      continue
    pushed[target] = true
    collider.rpc_id(target, &"receive_external_push", normal.normalized() * PUSH_FORCE)


func _decay_external_velocity(delta: float) -> void:
  if external_velocity.length_squared() == 0.0:
    return
  
  external_velocity = external_velocity.move_toward(Vector2.ZERO, PUSH_DECAY_RATE * delta)
  if external_velocity.length_squared() < 1.0:
    external_velocity = Vector2.ZERO


func _initialize_identity() -> void:
  if is_instance_valid(sprite):
    sprite.modulate = DEFAULT_SPRITE_COLOR
  if is_instance_valid(name_label):
    name_label.add_theme_color_override("font_color", DEFAULT_LABEL_COLOR)
    name_label.text = str(_get_authority_id())

  var peer := _get_node_tunnel_peer()
  if peer != null:
    var peer_changed := Callable(self, "_on_peer_identity_peer_changed")
    _connect_once(peer.peer_connected, peer_changed)
    _connect_once(peer.peer_disconnected, peer_changed)

    var state_changed := Callable(self, "_on_peer_identity_state_changed")
    _connect_once(peer.hosting, state_changed)
    _connect_once(peer.joined, state_changed)
    _connect_once(peer.room_left, state_changed)

  if multiplayer is MultiplayerAPI:
    var auth_changed := Callable(self, "_on_authority_changed")
    _connect_once(multiplayer.peer_connected, auth_changed)
    _connect_once(multiplayer.peer_disconnected, auth_changed)

  _refresh_identity()


func _refresh_identity() -> void:
  var authority_id := _get_authority_id()
  if authority_id == 0:
    return

  var online_id := _get_online_id_for_authority(authority_id)
  var has_online := !online_id.is_empty()
  var color := _color_from_online_id(online_id) if has_online else DEFAULT_SPRITE_COLOR

  if is_instance_valid(sprite):
    sprite.modulate = color
  if is_instance_valid(name_label):
    name_label.text = online_id if has_online else str(authority_id)
    name_label.add_theme_color_override("font_color", color.lightened(LABEL_LIGHTEN) if has_online else DEFAULT_LABEL_COLOR)


func _on_peer_identity_peer_changed(_peer_id: int) -> void:
  _refresh_identity()


func _on_peer_identity_state_changed() -> void:
  _refresh_identity()


func _on_authority_changed(_peer_id: int) -> void:
  _refresh_identity()


func _get_node_tunnel_peer() -> NodeTunnelPeer:
  var current_peer := multiplayer.multiplayer_peer
  if current_peer == null:
    return null
  if current_peer is NodeTunnelPeer:
    return current_peer
  return null


func _get_authority_id() -> int:
  var authority_id := get_multiplayer_authority()
  if authority_id != 0:
    return authority_id
  return name.to_int()


func _color_from_online_id(online_id: String) -> Color:
  var hash_value: int = 2166136261
  var bytes := online_id.to_utf8_buffer()
  for byte in bytes:
    hash_value = int((hash_value ^ byte) * 16777619) & 0xFFFFFFFF
  
  var hue := float(hash_value & 0xFFFF) / 65535.0
  var saturation := 0.6 + float((hash_value >> 16) & 0xFF) / 1020.0
  var value := 0.75 + float((hash_value >> 24) & 0xFF) / 1020.0
  return Color.from_hsv(hue, clampf(saturation, 0.0, 1.0), clampf(value, 0.0, 1.0), 1.0)


func _get_online_id_for_authority(authority_id: int) -> String:
  var peer := _get_node_tunnel_peer()
  if peer == null:
    return ""
  
  if peer.unique_id == authority_id:
    return peer.online_id
  
  var mapping := peer._numeric_to_online_id
  if mapping is Dictionary and mapping.has(authority_id):
    return mapping[authority_id]
  
  return ""

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
