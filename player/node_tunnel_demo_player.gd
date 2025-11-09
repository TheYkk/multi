extends CharacterBody2D

# Same as any other movement script
# Uses MultiplayerSynchronizer to sync position

const SPEED = 250.0
var message_rect: ColorRect


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


func _physics_process(_delta: float) -> void:
  if !is_multiplayer_authority():
    return
  
  var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
  velocity = input_dir * SPEED
  
  move_and_slide()

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
