extends "res://scripts/audio/clip_voice.gd"
## The Broken Bot's sounds (robot_1.glb), ported from its "Broken Bot" artifact: a rising charge as
## the Attack clip braces, the distorted sonic blast while its speaker is out (0.5–1.15 s), and the
## power-down as Defeat starts. Contract: docs/ui-and-assets.md §2 Model sounds.

const CHARGE_TIME := 0.38
const BLAST_START := 0.5
const BLAST_TIME := 0.65
const POWER_DOWN_TIME := 2.2
const PEAK := 0.8

func _init() -> void:
	# The artifact's compressor brings the three to about the same loudness, so each is normalised.
	gain = 1.0
	cues = {
		"Attack": [[0.0, "charge", 1.0], [BLAST_START, "blast", 1.0]],
		"Defeat": [[0.0, "power_down", 1.0]],
	}
	sounds = ["charge", "blast", "power_down"]

func _build(sound: String, m: Synth.Mix) -> void:
	match sound:
		"charge":
			_charge(m)
		"blast":
			_blast(m)
		"power_down":
			_power_down(m)
	m.normalize(PEAK)

# A triangle sweeping 160 -> 880 Hz, swelling until just before the blast.
func _charge(m: Synth.Mix) -> void:
	var d := CHARGE_TIME
	var out := PackedFloat32Array()
	out.resize(int((d + 0.1) * Synth.RATE))
	var phase := 0.0
	for i in out.size():
		var t := float(i) / Synth.RATE
		phase += TAU * Synth.ramp(160, 880, 0, d, t) / Synth.RATE
		var g := Synth.ramp(1e-4, 0.45, 0, d * 0.85, t) if t < d * 0.85 else Synth.ramp(0.45, 1e-4, d * 0.85, d + 0.06, t)
		out[i] = Synth.wave("triangle", phase) * g
	m.add(0.0, out)

# Three detuned oscillators wobbling at 24 Hz, driven through a tanh distortion, plus a noise
# hit, all through a resonant lowpass closing 3200 -> 700 Hz.
func _blast(m: Synth.Mix) -> void:
	var end := BLAST_TIME
	var oscs := [["sawtooth", 110.0], ["square", 166.0], ["sawtooth", 221.0]]
	var phases := [0.0, 0.0, 0.0]
	var hit := Synth.noise_burst(m, 0.35)
	var lp := Synth.Biquad.new("lowpass", 7.0)
	var out := PackedFloat32Array()
	out.resize(int((end + 0.3) * Synth.RATE))
	for i in out.size():
		var t := float(i) / Synth.RATE
		var wob := 55.0 * sin(TAU * 24.0 * t)
		var x := 0.0
		for k in 3:
			var f: float = oscs[k][1]
			phases[k] += TAU * (Synth.ramp(f * 1.5, f, 0, 0.14, t) + wob) / Synth.RATE
			x += Synth.wave(oscs[k][0], phases[k]) * 0.3
		var s := tanh(clampf(x, -1.0, 1.0) * 3.2)
		if i < hit.size():
			s += hit[i] * 0.6
		var g := 0.9
		if t < 0.03:
			g = Synth.ramp(1e-4, 0.9, 0, 0.03, t)
		elif t >= end - 0.05:
			g = Synth.ramp(0.85, 1e-4, end - 0.05, end + 0.25, t)
		out[i] = lp.step(s, Synth.ramp(3200, 700, 0, end + 0.2, t)) * g
	m.add(0.0, out)

# A noise jolt, then a sawtooth sliding 520 -> 32 Hz with a slowing wobble through a closing
# lowpass, and seven random crackles.
func _power_down(m: Synth.Mix) -> void:
	var d := POWER_DOWN_TIME
	var hit := Synth.noise_burst(m, 0.25)
	for i in hit.size():
		hit[i] *= 0.7
	m.add(0.0, hit)
	var lp := Synth.Biquad.new("lowpass")
	var out := PackedFloat32Array()
	out.resize(int((d + 0.3) * Synth.RATE))
	var phase := 0.0
	var lfo_phase := 0.0
	for i in out.size():
		var t := float(i) / Synth.RATE
		lfo_phase += TAU * lerpf(11.0, 3.0, minf(t / d, 1.0)) / Synth.RATE
		# WebAudio's default 440 Hz holds until the slide starts at 0.1 s.
		var f := 440.0 if t < 0.1 else Synth.ramp(520, 32, 0.1, d, t)
		phase += TAU * (f + 40.0 * sin(lfo_phase)) / Synth.RATE
		var g := Synth.ramp(1e-4, 0.35, 0, 0.15, t) if t < 0.15 else Synth.ramp(0.35, 1e-4, 0.15, d + 0.2, t)
		out[i] = lp.step(Synth.wave("sawtooth", phase), Synth.ramp(2200, 180, 0, d, t)) * g
	m.add(0.0, out)
	for c in 7:
		var crackle := Synth.noise_burst(m, 0.05)
		var hp := Synth.Biquad.new("highpass")
		for i in crackle.size():
			crackle[i] = hp.step(crackle[i], 2500.0) * 0.35
		m.add(0.2 + m.rng.randf() * d * 0.8, crackle)
