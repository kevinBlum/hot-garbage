extends Control

var _artifact_label: Label
var _value_label: Label
var _bid_count_label: Label
var _force_btn: Button
var _expected_bids: int = 0
var _received_bids: int = 0

func _ready() -> void:
	_build_ui()
	# Count expected bids = all peers minus self
	_expected_bids = NetworkManager.get_peer_ids().size()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(500, 400)
	add_child(vbox)

	var role_lbl := Label.new()
	role_lbl.text = "YOU ARE THE AUCTIONEER"
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(role_lbl)

	_artifact_label = Label.new()
	_artifact_label.text = "Waiting for auction to start..."
	_artifact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artifact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_artifact_label)

	_value_label = Label.new()
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_value_label)

	_bid_count_label = Label.new()
	_bid_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_bid_count_label)

	if NetworkManager.is_host():
		_force_btn = Button.new()
		_force_btn.text = "Force Resolve (host escape hatch)"
		_force_btn.pressed.connect(func(): GameServer.force_resolve())
		vbox.add_child(_force_btn)

func on_auctioneer_reveal(artifact: Dictionary) -> void:
	_received_bids = 0
	_artifact_label.text = "%s\n%s\n\n\"%s\"" % [artifact.name, artifact.category.to_upper(), artifact.flavor]
	_value_label.text = "TRUE VALUE: §%d" % artifact.value
	_bid_count_label.text = "Bids received: 0 / %d" % _expected_bids
	NetworkManager.bid_received.connect(_on_bid_count_update)

func _on_bid_count_update(_peer_id: int, _amount: int) -> void:
	_received_bids += 1
	_bid_count_label.text = "Bids received: %d / %d" % [_received_bids, _expected_bids]
