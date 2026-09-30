class_name Sfx
extends RefCounted
## Sound effects synthesised in code (no audio files, no licences to track).

const RATE := 22050


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	w.data = data
	return w


static func make(kind: String) -> AudioStreamWAV:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var dur: float = 0.2
	match kind:
		"shot":
			dur = 0.16
		"cannon":
			dur = 0.55
		"boom":
			dur = 1.1
		"click":
			dur = 0.06
		"coin":
			dur = 0.28
		"capture":
			dur = 0.7
		"alarm":
			dur = 0.6
		"ready":
			dur = 0.2
	var n: int = int(dur * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		match kind:
			"shot":
				v = rng.randf_range(-1.0, 1.0) * exp(-t * 30.0) * 0.6 + sin(TAU * 140.0 * t) * exp(-t * 40.0) * 0.5
			"cannon":
				lp = lp + (rng.randf_range(-1.0, 1.0) - lp) * 0.25
				v = lp * exp(-t * 9.0) * 1.2 + sin(TAU * 70.0 * t) * exp(-t * 12.0) * 0.8
			"boom":
				lp = lp + (rng.randf_range(-1.0, 1.0) - lp) * 0.08
				v = lp * exp(-t * 3.2) * 2.2 + sin(TAU * 42.0 * t) * exp(-t * 4.0) * 0.9
			"click":
				v = sin(TAU * 950.0 * t) * exp(-t * 70.0) * 0.5
			"coin":
				var f: float = 1250.0 if t < 0.09 else 1850.0
				v = sin(TAU * f * t) * exp(-t * 11.0) * 0.45
			"capture":
				var f2: float = 440.0 * pow(1.26, floorf(t / 0.16))
				v = sin(TAU * f2 * t) * exp(-fmod(t, 0.16) * 12.0) * 0.45
			"alarm":
				var f3: float = 620.0 if fmod(t, 0.3) < 0.15 else 820.0
				v = signf(sin(TAU * f3 * t)) * 0.22 * (1.0 - t / dur)
			"ready":
				v = sin(TAU * (700.0 + 500.0 * t / dur) * t) * exp(-t * 9.0) * 0.4
		out[i] = v
	return _wav(out)
