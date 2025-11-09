extends Area2D

var is_on: bool = false
var local_inside: bool = false

@onready var light: PointLight2D = $Light
@onready var range_viz: Polygon2D = $RangeViz


func _ready() -> void:
  body_entered.connect(_on_body_entered)
  body_exited.connect(_on_body_exited)
  _apply_state_local()


func _on_body_entered(body: Node) -> void:
  if body is CharacterBody2D and body.get_multiplayer_authority() == multiplayer.get_unique_id():
    local_inside = true


func _on_body_exited(body: Node) -> void:
  if body is CharacterBody2D and body.get_multiplayer_authority() == multiplayer.get_unique_id():
    local_inside = false


func _unhandled_input(event: InputEvent) -> void:
  if event.is_action_pressed("toggle_switch") and local_inside:
    if multiplayer.is_server():
      request_toggle()
    else:
      rpc_id(1, &"request_toggle")


@rpc("any_peer")
func request_toggle() -> void:
  if !multiplayer.is_server():
    return
  is_on = !is_on
  _apply_state_local()
  rpc(&"apply_state", is_on)


@rpc("any_peer", "call_local")
func apply_state(new_state: bool) -> void:
  is_on = new_state
  _apply_state_local()


func _apply_state_local() -> void:
  if is_instance_valid(light):
    light.enabled = is_on
    light.visible = is_on
  if is_instance_valid(range_viz):
    range_viz.color = Color(0.3, 1.0, 0.3, 0.35) if is_on else Color(1.0, 0.3, 0.3, 0.35)
