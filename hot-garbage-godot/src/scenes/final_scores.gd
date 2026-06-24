extends Control

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "ScoreList"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "GRAND REVEAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var waiting := Label.new()
	waiting.name = "WaitingLabel"
	waiting.text = "Waiting for final scores..."
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(waiting)

func on_show_final_scores(ranking: Array) -> void:
	var vbox: VBoxContainer = $ScrollContainer/ScoreList if has_node("ScrollContainer/ScoreList") else _find_vbox()
	# Remove waiting label
	for child in vbox.get_children():
		if child.name == "WaitingLabel":
			child.queue_free()

	var medals := ["🏆", "2.", "3.", "4.", "5.", "6.", "7.", "8."]
	for i in range(ranking.size()):
		var p: Dictionary = ranking[i]
		var medal: String = medals[i] if i < medals.size() else "%d." % (i + 1)

		var player_vbox := VBoxContainer.new()
		vbox.add_child(player_vbox)

		var header := Label.new()
		header.text = "%s %s — %d pts  (cash §%d)" % [medal, p.id, p.total, p.cash]
		player_vbox.add_child(header)

		for cat in p.breakdown:
			var b: Dictionary = p.breakdown[cat]
			var set_str: String = ("  SET x%.1f" % b.multiplier) if b.completed else ""
			var line := Label.new()
			line.text = "    %s: %d items, raw §%d → §%d%s" % [cat, b.count, b.raw, b.scored, set_str]
			player_vbox.add_child(line)

		var sep := HSeparator.new()
		vbox.add_child(sep)

func _find_vbox() -> VBoxContainer:
	for child in get_children():
		if child is ScrollContainer:
			for grandchild in child.get_children():
				if grandchild is VBoxContainer:
					return grandchild
	return VBoxContainer.new()
