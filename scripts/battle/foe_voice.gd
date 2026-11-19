extends "res://scripts/audio/clip_voice.gd"
## Sounds for the robots past the Broken Bot and the three gym bosses, made in code like the Broken
## Bot's. The foe is told apart by its glb's root node; each clip's cues sit on the moments its effects
## show (beam on, crystals out, fireball away, fragments flying). Contract: docs/ui-and-assets.md §2.

const PEAK := 0.8
const CUES := {
	"CrackedSentinel": {
		"EyeBeam_Attack": [[0.1, "servo", 0.5], [0.45, "beam_charge", 0.8], [0.87, "beam", 1.0]],
		"Defeat": [[0.0, "buzz", 0.7], [0.63, "flicker", 0.6], [1.0, "power_down", 0.7], [1.47, "crash", 1.0]],
	},
	"ScrapUnit": {
		"ScrapToss_Attack": [[0.0, "rattle", 0.7], [0.5, "thud", 0.5], [1.3, "whoosh", 0.8], [1.87, "crash", 1.0], [2.63, "clank", 0.4]],
		"Defeat": [[0.33, "flicker", 0.6], [0.6, "power_down", 0.6], [1.4, "crash", 0.9], [1.77, "thud", 0.9]],
	},
	"PorcelainAndroid": {
		"EMP_Attack": [[0.5, "emp_charge", 0.8], [1.53, "emp", 1.0]],
		"Defeat": [[0.3, "flicker", 0.6], [1.1, "power_down", 0.7], [2.57, "porcelain", 1.0]],
	},
	"Frostbreaker": {
		"FrostNova_Attack": [[0.3, "servo", 0.5], [0.8, "frost_charge", 0.8], [0.97, "frost_burst", 1.0], [2.27, "ice_shatter", 0.9]],
		"BoomerangHammer_Attack": [[0.37, "swing", 0.7], [0.83, "whoosh", 1.0], [1.05, "spin", 0.7], [3.4, "clank_heavy", 1.0]],
		"Defeat": [[0.43, "ice_crackle", 0.7], [2.5, "ice_shatter", 1.0], [2.5, "crash", 0.7], [3.13, "slam", 0.8]],
	},
	"InfernoBreaker": {
		"MeteorLeap_Attack": [[0.5, "swing", 0.6], [0.97, "fire_rise", 1.0], [1.7, "slam", 1.0], [1.75, "rumble", 0.8]],
		"MagmaCannon_Attack": [[0.53, "fire_charge", 0.8], [0.93, "fireball", 1.0], [1.8, "explosion", 1.0], [1.85, "sizzle", 0.5]],
		"Defeat": [[0.6, "sizzle", 0.6], [0.83, "crumble", 0.9], [2.23, "fire_rise", 0.6], [4.2, "slam", 0.9], [4.6, "power_down", 0.6]],
	},
	"Voltbreaker": {
		"ThunderStrike_Attack": [[0.3, "swing", 0.7], [0.85, "volt_charge", 0.9], [1.33, "thunder", 1.0]],
		"ScrapBarrage_Attack": [[0.43, "magnet", 0.7], [0.5, "clank", 0.35], [0.63, "clank", 0.3], [0.77, "clank", 0.35], [1.77, "volt_charge", 0.7], [2.3, "barrage", 1.0]],
		"Defeat": [[0.27, "flicker", 0.6], [0.73, "zap", 0.9], [1.87, "power_down", 0.8], [2.57, "slam", 0.8]],
	},
}

func _ready() -> void:
	var root := anim.owner if anim.owner != null else anim.get_parent()
	for model: String in CUES:
		if root.find_child(model, true, false) != null:
			cues = CUES[model]
	for clip: String in cues:
		for cue: Array in cues[clip]:
			if not sounds.has(cue[1]):
				sounds.append(cue[1])
	super()

# Arguments after the volume: attack, vibrato depth (Hz), vibrato rate, lowpass cutoff.
func _build(sound: String, m: Synth.Mix) -> void:
	match sound:
		"servo":
			Synth.tone(m, 0, .28, 300, 520, "square", .1, .02, 30, 40, 1200)
		"thud":
			Synth.tone(m, 0, .35, 120, 45, "sine", .9)
			Synth.noise(m, 0, .15, .4, "lowpass", 600, 200)
		"slam":
			Synth.tone(m, 0, .9, 95, 30, "sine", 1.0)
			Synth.noise(m, 0, .4, .7, "lowpass", 1400, 150)
			_ring(m, 0.0, [233.0, 517.0, 811.0], .25, .6)
		"rumble":
			Synth.noise(m, 0, 1.3, .6, "lowpass", 260, 90, 1.0, .05)
		"clank":
			_ring(m, 0.0, [1180.0, 2650.0, 4110.0], .2, .25)
			Synth.noise(m, 0, .04, .4, "bandpass", 3000, 3000, 2.0)
		"clank_heavy":
			_ring(m, 0.0, [620.0, 1390.0, 2210.0], .45, .5)
			Synth.noise(m, 0, .06, .5, "bandpass", 2000, 2000, 1.5)
			Synth.tone(m, 0, .2, 140, 70, "sine", .5)
		"crash":
			Synth.noise(m, 0, .5, .7, "bandpass", 3200, 1100, 1.5)
			_ring(m, 0.0, [523.0, 1187.0, 1873.0], .3, .6)
			for i in 5:
				_ring(m, .08 + m.rng.randf() * .35, [m.rng.randf_range(1500, 4000)], .12, .12)
			Synth.tone(m, 0, .3, 110, 50, "sine", .6)
		"rattle":
			for i in 7:
				_ring(m, i * .07 + m.rng.randf() * .03, [m.rng.randf_range(900, 3500)], .14, .1)
		"whoosh":
			Synth.noise(m, 0, .38, .6, "bandpass", 400, 2200, 1.2, .12)
		"swing":
			Synth.noise(m, 0, .45, .5, "bandpass", 250, 900, 1.0, .2)
		"spin":
			for i in 8:
				var near := 1.0 - absf(i - 3.5) / 3.5
				Synth.noise(m, i * .19, .2, .2 + .3 * near, "bandpass", 500 + 700 * near, 900 + 900 * near, 1.5, .06)
		"flicker":
			for t in [0.0, .06, .14]:
				Synth.tone(m, t, .04, 1250, 1100, "square", .12, .002, 0, 6, 3000)
		"buzz":
			Synth.tone(m, 0, .35, 150, 120, "square", .25, .01, 25, 30, 1500)
		"power_down":
			Synth.tone(m, 0, 1.3, 600, 50, "sawtooth", .3, .02, 30, 8, 1200)
		"beam_charge":
			Synth.tone(m, 0, .42, 200, 1400, "triangle", .35, .3, 8, 18)
		"beam":
			Synth.tone(m, 0, 1.05, 230, 210, "sawtooth", .3, .01, 25, 30, 2600)
			Synth.tone(m, 0, 1.05, 345, 330, "square", .15, .01, 30, 31, 2600)
			Synth.noise(m, 0, 1.05, .15, "bandpass", 2400, 1800, 3.0, .01)
		"emp_charge":
			Synth.tone(m, 0, 1.0, 120, 900, "sine", .4, .8, 20, 14)
			Synth.noise(m, .4, .6, .1, "highpass", 3000, 6000, 1.0, .5)
		"emp":
			Synth.tone(m, 0, .7, 900, 40, "sine", .8)
			Synth.tone(m, 0, .6, 80, 60, "square", .3, .005, 30, 12, 700)
			Synth.noise(m, 0, .25, .4, "highpass", 4000, 1500)
		"porcelain":
			Synth.noise(m, 0, .3, .5, "highpass", 3000, 2000)
			for i in 12:
				_ring(m, m.rng.randf() * .5, [m.rng.randf_range(2200, 5200)], .18, .09)
			Synth.tone(m, 0, .25, 160, 60, "sine", .5)
		"frost_charge":
			for f in [1568.0, 2093.0, 2637.0]:
				Synth.tone(m, 0, .3, f * .9, f, "sine", .1, .2, 12, 9)
			Synth.noise(m, 0, .3, .15, "highpass", 4000, 8000, 1.0, .25)
		"frost_burst":
			_ring(m, 0.0, [1568.0, 2093.0, 2637.0, 3136.0], 1.1, .35)
			Synth.noise(m, 0, .5, .3, "highpass", 6000, 3000)
			Synth.tone(m, 0, .45, 180, 60, "sine", .6)
		"ice_crackle":
			for i in 10:
				Synth.noise(m, i * .1 + m.rng.randf() * .06, .03, .3, "highpass", 5000, 5000)
		"ice_shatter":
			Synth.noise(m, 0, .45, .6, "highpass", 5000, 2500)
			for i in 14:
				_ring(m, m.rng.randf() * .45, [m.rng.randf_range(2500, 6000)], .25, .1)
		"fire_rise":
			Synth.noise(m, 0, .7, .7, "lowpass", 300, 2600, 1.0, .4)
			Synth.tone(m, 0, .7, 60, 120, "sawtooth", .2, .3, 0, 6, 500)
		"fire_charge":
			Synth.noise(m, 0, .45, .5, "bandpass", 200, 900, 1.0, .35)
			Synth.tone(m, 0, .45, 55, 110, "sawtooth", .25, .3, 4, 9, 450)
		"fireball":
			Synth.tone(m, 0, .4, 220, 60, "sine", .8)
			Synth.noise(m, 0, .35, .6, "lowpass", 2500, 400)
		"explosion":
			Synth.tone(m, 0, 1.0, 85, 28, "sine", 1.0)
			Synth.noise(m, 0, .9, .8, "lowpass", 3000, 120)
			for i in 6:
				Synth.noise(m, .1 + m.rng.randf() * .6, .03, .25, "highpass", 2500, 2500)
		"sizzle":
			Synth.noise(m, 0, 1.5, .2, "highpass", 3500, 5000, 1.0, .2)
			for i in 14:
				Synth.noise(m, m.rng.randf() * 1.4, .015, .3, "highpass", 4000, 4000)
		"crumble":
			for i in 6:
				var t := i * .13 + m.rng.randf() * .04
				Synth.tone(m, t, .2, m.rng.randf_range(110, 160), 50, "sine", .5)
				Synth.noise(m, t, .12, .35, "lowpass", 900, 250)
		"volt_charge":
			Synth.tone(m, 0, .5, 100, 420, "sawtooth", .3, .3, 60, 50, 2400)
			for i in 9:
				Synth.noise(m, m.rng.randf() * .48, .012, .35, "highpass", 3000, 3000)
		"thunder":
			Synth.noise(m, 0, .12, 1.0, "highpass", 1500, 800)
			Synth.tone(m, 0, 1.3, 80, 26, "sine", .9, .01)
			Synth.noise(m, .05, 1.4, .6, "lowpass", 900, 90, 1.0, .02)
		"zap":
			for i in 6:
				var f := m.rng.randf_range(300, 1500)
				Synth.tone(m, i * .06, .05, f, f * .6, "square", .2, .002, 0, 6, 3500)
			Synth.noise(m, 0, .35, .3, "highpass", 3000, 1500)
		"magnet":
			Synth.tone(m, 0, 1.3, 110, 110, "sine", .35, .2, 2, 11)
			Synth.tone(m, 0, 1.3, 221, 221, "triangle", .12, .2, 3, 7)
		"barrage":
			for i in 6:
				var t := i * .07
				Synth.noise(m, t, .12, .35, "bandpass", 700, 2000, 1.2, .02)
				_ring(m, t + .05, [m.rng.randf_range(900, 2800), m.rng.randf_range(3000, 4500)], .15, .2)
	m.normalize(PEAK)

# Struck metal or glass: sine partials ringing down over `dur`.
func _ring(m: Synth.Mix, start: float, freqs: Array, dur: float, vol: float) -> void:
	for f: float in freqs:
		Synth.tone(m, start, dur, f, f * 0.995, "sine", vol / freqs.size(), 0.002)
