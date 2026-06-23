extends Control

var _artifact_label: Label
var _cash_label: Label
var _bid_input: SpinBox
var _submit_btn: Button
var _status_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(500, 400)
	add_child(vbox)

	_artifact_label = Label.new()
	_artifact_label.text = "Waiting for auction..."
	_artifact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artifact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_artifact_label)

	_cash_label = Label.new()
	_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_cash_label)

	var bid_row := HBoxContainer.new()
	vbox.add_child(bid_row)

	var bid_lbl := Label.new()
	bid_lbl.text = "Your bid: §"
	bid_row.add_child(bid_lbl)

	_bid_input = SpinBox.new()
	_bid_input.min_value = 0
	_bid_input.max_value = 99999
	_bid_input.step = 1
	bid_row.add_child(_bid_input)

	_submit_btn = Button.new()
	_submit_btn.text = "Submit Bid"
	_submit_btn.pressed.connect(_on_submit_pressed)
	vbox.add_child(_submit_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

func on_start_bidding(artifact: Dictionary) -> void:
	_artifact_label.text = "%s\n%s\n\n\"%s\"" % [artifact.name, artifact.category.to_upper(), artifact.flavor]
	var my_name := NetworkManager.player_names.get(multiplayer.get_unique_id(), "?")
	# Show cash if we can find it — GameServer holds this; for now show a placeholder
	_cash_label.text = "Place your bid"
	_bid_input.value = 0
	_submit_btn.disabled = false
	_status_label.text = ""

func _on_submit_pressed() -> void:
	_submit_btn.disabled = true
	_status_label.text = "Bid submitted. Waiting for others..."
	NetworkManager.submit_bid(int(_bid_input.value))
