extends Node

var master_volume: float = 0.5
var sfx_volume:    float = 0.5
var music_volume:  float = 0.5

var _player_ui:      AudioStreamPlayer
var _player_bid:     AudioStreamPlayer
var _player_open:    AudioStreamPlayer
var _player_resolve: AudioStreamPlayer

func _ready() -> void:
    _ensure_buses()
    _player_ui      = _make_player(_make_beep(880.0, 0.06, 8.0))
    _player_bid     = _make_player(_make_beep(550.0, 0.12, 8.0))
    _player_open    = _make_player(_make_beep(660.0, 0.20, 4.0))
    _player_resolve = _make_player(_make_beep(440.0, 0.35, 4.0))
    load_settings()

func play_ui()      -> void: _player_ui.play()
func play_bid()     -> void: _player_bid.play()
func play_open()    -> void: _player_open.play()
func play_resolve() -> void: _player_resolve.play()

func apply_volumes() -> void:
    AudioServer.set_bus_volume_db(
        AudioServer.get_bus_index("Master"), linear_to_db(master_volume))
    var sfx_idx: int = AudioServer.get_bus_index("SFX")
    if sfx_idx >= 0:
        AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))
    var music_idx: int = AudioServer.get_bus_index("Music")
    if music_idx >= 0:
        AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))

func save_settings() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("audio", "master", master_volume)
    cfg.set_value("audio", "sfx",    sfx_volume)
    cfg.set_value("audio", "music",  music_volume)
    cfg.save("user://settings.cfg")

func load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load("user://settings.cfg") != OK:
        apply_volumes()
        return
    master_volume = cfg.get_value("audio", "master", 0.5)
    sfx_volume    = cfg.get_value("audio", "sfx",    0.5)
    music_volume  = cfg.get_value("audio", "music",  0.5)
    apply_volumes()

# ---- private ----

func _ensure_buses() -> void:
    if AudioServer.get_bus_index("SFX") < 0:
        AudioServer.add_bus()
        var idx: int = AudioServer.get_bus_count() - 1
        AudioServer.set_bus_name(idx, "SFX")
        AudioServer.set_bus_send(idx, "Master")
    if AudioServer.get_bus_index("Music") < 0:
        AudioServer.add_bus()
        var idx: int = AudioServer.get_bus_count() - 1
        AudioServer.set_bus_name(idx, "Music")
        AudioServer.set_bus_send(idx, "Master")

func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
    var p := AudioStreamPlayer.new()
    p.stream = stream
    p.bus = "SFX"
    add_child(p)
    return p

static func _make_beep(freq: float, duration: float, decay: float) -> AudioStreamWAV:
    var sample_rate: int = 44100
    var n: int = int(sample_rate * duration)
    var data := PackedByteArray()
    data.resize(n * 2)
    for i in n:
        var t: float = float(i) / float(sample_rate)
        var v: int = int(sin(TAU * freq * t) * 16383.0 * exp(-t * decay))
        data.encode_s16(i * 2, clampi(v, -32768, 32767))
    var wav := AudioStreamWAV.new()
    wav.format   = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = sample_rate
    wav.stereo   = false
    wav.data     = data
    return wav
