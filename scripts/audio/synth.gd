extends RefCounted
## A small port of the WebAudio building blocks the model artifacts synthesise their sounds with:
## oscillator sweeps with vibrato, exponential envelopes, RBJ biquad filters and filtered noise.
## Sounds are built into a Mix, then turned into an AudioStreamWAV. Callers preload this script.
## Contract: docs/ui-and-assets.md §2 Model sounds.

const RATE := 22050

## One sound being built: a mono sample buffer that parts are added into at a start time.
class Mix:
	var buf := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()

	func _init(seed_value := 7) -> void:
		rng.seed = seed_value

	func add(start: float, samples: PackedFloat32Array) -> void:
		var i0 := int(start * RATE)
		if i0 + samples.size() > buf.size():
			buf.resize(i0 + samples.size())
		for k in samples.size():
			buf[i0 + k] += samples[k]

	## Scales the sound so its loudest sample is `peak`: a stand-in for a page's compressor.
	func normalize(peak: float) -> void:
		var top := 0.0
		for x in buf:
			top = maxf(top, absf(x))
		if top > 0.0:
			for i in buf.size():
				buf[i] *= peak / top

	## 16-bit PCM at RATE, scaled by `gain` and clipped.
	func to_stream(gain: float) -> AudioStreamWAV:
		var data := PackedByteArray()
		data.resize(buf.size() * 2)
		for i in buf.size():
			data.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = RATE
		s.data = data
		return s

## RBJ cookbook lowpass / highpass / bandpass (0 dB peak); coefficients follow a swept frequency.
class Biquad:
	var kind: String
	var q: float
	var _f := -1.0
	var _b0 := 0.0
	var _b1 := 0.0
	var _b2 := 0.0
	var _a1 := 0.0
	var _a2 := 0.0
	var _x1 := 0.0
	var _x2 := 0.0
	var _y1 := 0.0
	var _y2 := 0.0

	## `web_q` is WebAudio's Q: a resonance in dB for lowpass / highpass, linear for bandpass.
	func _init(filter_kind: String, web_q := 1.0) -> void:
		kind = filter_kind
		q = web_q if kind == "bandpass" else 0.7071 * pow(10.0, web_q / 20.0)

	func step(x: float, freq: float) -> float:
		if freq != _f:
			_f = freq
			var w := TAU * minf(freq, RATE * 0.45) / RATE
			var cw := cos(w)
			var alpha := sin(w) / (2.0 * q)
			var a0 := 1.0 + alpha
			match kind:
				"lowpass":
					_b0 = (1.0 - cw) / 2.0 / a0
					_b1 = (1.0 - cw) / a0
					_b2 = _b0
				"highpass":
					_b0 = (1.0 + cw) / 2.0 / a0
					_b1 = -(1.0 + cw) / a0
					_b2 = _b0
				_:
					_b0 = alpha / a0
					_b1 = 0.0
					_b2 = -alpha / a0
			_a1 = -2.0 * cw / a0
			_a2 = (1.0 - alpha) / a0
		var y := _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2
		_x2 = _x1
		_x1 = x
		_y2 = _y1
		_y1 = y
		return y

static func wave(kind: String, phase: float) -> float:
	match kind:
		"sine":
			return sin(phase)
		"triangle":
			return 2.0 / PI * asin(sin(phase))
		"sawtooth":
			return 2.0 * fposmod(phase / TAU, 1.0) - 1.0
	return 1.0 if sin(phase) >= 0.0 else -1.0

## WebAudio's exponentialRampToValueAtTime from v0 at t0 to v1 at t1, evaluated at t.
static func ramp(v0: float, v1: float, t0: float, t1: float, t: float) -> float:
	return v0 * pow(v1 / v0, clampf((t - t0) / (t1 - t0), 0.0, 1.0))

## The artifacts' envelope: exponential rise to `vol` over `att`, exponential fall to silence at `dur`.
static func env(t: float, dur: float, vol: float, att: float) -> float:
	vol = maxf(vol, 1e-4)
	if t < att:
		return ramp(1e-4, vol, 0.0, att, t)
	if t < dur:
		return ramp(vol, 1e-4, att, dur, t)
	return 0.0

## An oscillator swept exponentially f0 -> f1 over `dur`, with optional vibrato and lowpass.
static func tone(m: Mix, start: float, dur: float, f0: float, f1: float, kind: String, vol: float,
		att := 0.008, vib := 0.0, vib_rate := 6.0, lowpass := 0.0) -> void:
	var out := PackedFloat32Array()
	out.resize(int((dur + 0.05) * RATE))
	var lp: Biquad = Biquad.new("lowpass") if lowpass > 0.0 else null
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var f := ramp(f0, f1, 0.0, dur, t) if f1 != f0 else f0
		if vib != 0.0:
			f += vib * sin(TAU * vib_rate * t)
		phase += TAU * f / RATE
		var s := wave(kind, phase)
		if lp:
			s = lp.step(s, lowpass)
		out[i] = s * env(t, dur, vol, att)
	m.add(start, out)

## White noise through a filter swept f0 -> f1 over `dur`.
static func noise(m: Mix, start: float, dur: float, vol: float, kind: String, f0: float, f1: float,
		q := 1.0, att := 0.005) -> void:
	var out := PackedFloat32Array()
	out.resize(int((dur + 0.05) * RATE))
	var flt := Biquad.new(kind, q)
	for i in out.size():
		var t := float(i) / RATE
		var f := ramp(f0, f1, 0.0, dur, t) if f1 != f0 else f0
		out[i] = flt.step(m.rng.randf_range(-1.0, 1.0), f) * env(t, dur, vol, att)
	m.add(start, out)

## Short plucked notes, one every `step` seconds.
static func notes(m: Mix, start: float, freqs: Array, step: float, dur: float, vol: float, kind := "triangle") -> void:
	for i in freqs.size():
		tone(m, start + i * step, dur, freqs[i], freqs[i], kind, vol, 0.004)

## The artifacts' noise buffer: white noise fading linearly to silence over `secs`.
static func noise_burst(m: Mix, secs: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(secs * RATE))
	for i in out.size():
		out[i] = m.rng.randf_range(-1.0, 1.0) * (1.0 - float(i) / out.size())
	return out
