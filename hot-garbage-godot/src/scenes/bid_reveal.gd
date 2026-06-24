extends Control

var _result_label: Label
var _chaos_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(500, 400)
	add_child(vbox)

	_result_label = Label.new()
	_result_label.text = "Auction resolving..."
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_result_label)

	_chaos_label = Label.new()
	_chaos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chaos_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_chaos_label)

func on_show_bid_result(result: Dictionary) -> void:
	if result.winner == "BANK":
		_result_label.text = "No takers. Bank paid §%d." % result.price
	else:
		var winner_name: String = NetworkManager.player_names.get(
			_peer_id_for_name(result.winner), result.winner)
		_result_label.text = "%s won for §%d!" % [winner_name, result.price]

func on_show_chaos(chaos: Dictionary) -> void:
	if chaos.is_empty():
		return
	if chaos.type == "appraiser":
		_chaos_label.text = "APPRAISER: %s" % chaos.text
	else:
		_chaos_label.text = "EVENT: %s" % chaos.text
		if chaos.extra.has("victim") and chaos.extra.has("lost_name"):
			_chaos_label.text += "\n%s loses \"%s\"!" % [chaos.extra.victim, chaos.extra.lost_name]

func _peer_id_for_name(player_name: String) -> int:
	for pid in NetworkManager.player_names:
		if NetworkManager.player_names[pid] == player_name:
			return pid
	return -1
