extends "res://scripts/audio/clip_voice.gd"
## Kuiz's sounds, ported from the "KUIZMON Pet Bot 3D – Rigged" artifact: its CUES table per clip,
## and its WebAudio sound recipes rebuilt with synth.gd. peek.gd also plays the move sounds
## (hop, jump, land, whee). Contract: docs/ui-and-assets.md §2 Model sounds.

func _init() -> void:
	gain = 2.0
	cues = {
		"Blink": [[0.13, "blink", 1.0]],
		"Happy": [[0.02, "giggle", 1.0], [0.19, "jump", 1.0]],
		"Sad": [[0.05, "aww", 1.0]],
		"Angry": [[0.05, "grumble", 1.0]],
		"Surprised": [[0.02, "eep", 1.0]],
		"Look_Around": [[0.12, "servo", 1.0], [1.25, "servo", 1.0], [2.55, "servo", 1.0]],
		"Confused": [[0.05, "hmm", 1.0], [0.33, "question", 1.0]],
		"Charging": [[0.26, "blink", 1.0], [0.3, "powerdown", 1.0], [0.55, "power", 1.0], [3.55, "powerup", 1.0]],
		"Wake_Up": [[0.1, "snore", 1.0], [1.2, "snore", 1.0], [2.3, "snore", 1.0], [3.7, "powerup", 1.0]],
		"Greetings": [[0.02, "eep", 0.7], [0.25, "jump", 1.0], [0.43, "twinkle", 1.0], [0.7, "twinkle", 1.0], [0.77, "land", 1.0], [0.85, "hello", 1.0], [1.0, "twinkle", 1.0]],
		"Pet": [[0.35, "purr", 1.0], [0.6, "heart", 1.0], [0.77, "pat", 1.0], [1.2, "heart", 1.0], [1.57, "pat", 1.0], [1.87, "heart", 1.0], [2.37, "pat", 1.0]],
		"Peek_Surprise": [[1.45, "peek", 0.8], [1.76, "blink", 1.0], [1.9, "eep", 0.9], [1.93, "ding", 1.0], [2.35, "jump", 1.0], [2.67, "land", 1.0], [2.82, "eep", 0.6], [3.05, "jump", 1.0], [3.23, "twinkle", 1.0], [3.5, "twinkle", 1.0], [3.57, "land", 1.0], [3.65, "hello", 1.0], [3.8, "twinkle", 1.0], [5.39, "blink", 1.0]],
		"State_Tired": [[0.55, "yawn", 0.6], [3.13, "snore", 0.75], [4.3, "startle", 0.52]],
		"State_Sad": [[0.1, "whimper", 0.52], [0.53, "tear", 0.75], [2.18, "sniffle", 0.6], [2.8, "tear", 0.75]],
		"State_Mid": [[2.95, "sigh", 0.6]],
		"State_Sick": [[0.2, "wobble", 0.6], [1.7, "glitch", 0.6], [2.55, "boing", 0.75], [3.9, "glitch", 0.6]],
		"State_Charging": [[0.0, "hum", 0.6], [1.0, "hum", 0.6], [2.0, "hum", 0.6], [3.0, "hum", 0.6]],
		"State_Hungry": [[0.15, "please", 0.52], [0.63, "drip", 0.75], [2.0, "rumble", 0.75]],
		"Celebrate": [[0.25, "whee", 0.9], [0.5, "shimmer", 1.0], [0.57, "confetti", 1.0], [1.07, "twinkle", 1.0], [1.1, "land", 1.0], [1.29, "hop", 1.0], [1.3, "twinkle", 1.0], [1.57, "twinkle", 1.0], [2.0, "giggle", 1.0]],
		"Learn_Something_New": [[0.2, "page", 1.0], [1.17, "tick", 1.0], [1.8, "tick", 1.0], [2.43, "tick", 1.0], [2.6, "ding", 1.0], [2.6, "shimmer", 1.0], [2.8, "twinkle", 1.0], [3.0, "twinkle", 1.0], [3.1, "giggle", 1.0], [3.2, "twinkle", 1.0], [3.29, "hop", 1.0], [3.75, "hop", 1.0]],
	}
	# The peek's sounds first: they play seconds after the scene opens.
	sounds = ["peek", "blink", "eep", "ding", "jump", "land", "twinkle", "hello", "hop", "whee",
		"giggle", "pat", "heart", "purr", "aww", "whimper", "grumble", "hmm", "question", "shimmer",
		"confetti", "page", "tick", "snore", "yawn", "startle", "tear", "sniffle", "sigh", "glitch",
		"boing", "wobble", "hum", "powerdown", "power", "powerup", "rumble", "drip", "please", "servo"]

# Arguments after the volume: attack, vibrato depth (Hz), vibrato rate, lowpass cutoff.
func _build(sound: String, m: Synth.Mix) -> void:
	match sound:
		"blink":
			Synth.tone(m, 0, .035, 2300, 1900, "sine", .09)
		"peek":
			Synth.tone(m, 0, .11, 480, 700, "sine", .2)
			Synth.tone(m, .12, .12, 700, 620, "sine", .14)
		"jump":
			Synth.tone(m, 0, .18, 320, 980, "sine", .32)
			Synth.tone(m, 0, .12, 640, 1960, "triangle", .06)
		"hop":
			Synth.tone(m, 0, .12, 430, 900, "sine", .24)
		"whee":
			Synth.tone(m, 0, .42, 520, 1500, "sine", .18, .02, 18, 9)
		"land":
			Synth.tone(m, 0, .15, 190, 70, "sine", .38)
			Synth.noise(m, 0, .08, .1, "lowpass", 500, 300)
		"pat":
			Synth.tone(m, 0, .09, 250, 140, "sine", .16)
			Synth.noise(m, 0, .05, .05, "lowpass", 900, 600)
		"giggle":
			for i in 3:
				Synth.tone(m, i * .09, .075, 900 + i * 130, 1300 + i * 160, "sine", .2)
		"hello":
			Synth.tone(m, 0, .12, 640, 720, "sine", .24, .008, 5, 7)
			Synth.tone(m, .14, .22, 880, 1080, "sine", .24, .008, 6, 7)
		"aww":
			Synth.tone(m, 0, .28, 620, 470, "sine", .22, .03, 8, 7)
			Synth.tone(m, .26, .34, 470, 350, "sine", .2, .03, 8, 7)
		"whimper":
			Synth.tone(m, 0, .32, 700, 540, "sine", .11, .04, 12, 9)
		"grumble":
			Synth.tone(m, 0, .45, 118, 88, "sawtooth", .14, .03, 7, 18, 650)
		"eep":
			Synth.tone(m, 0, .12, 700, 1800, "sine", .28)
			Synth.tone(m, .12, .09, 1800, 1500, "sine", .16)
		"hmm":
			Synth.tone(m, 0, .18, 380, 420, "sine", .18, .03, 5, 6)
			Synth.tone(m, .2, .24, 420, 780, "sine", .2, .008, 5, 6)
		"question":
			Synth.tone(m, 0, .07, 900, 320, "sine", .28 * .8)
			Synth.noise(m, 0, .03, .07 * .8, "bandpass", 2000, 2000, 2)
			Synth.tone(m, .06, .2, 560, 900, "sine", .12)
		"heart":
			Synth.tone(m, 0, .1, 660, 990, "sine", .18)
			Synth.tone(m, .09, .14, 990, 1320, "sine", .16)
		"twinkle":
			Synth.notes(m, 0, [2093, 2637, 3136], .055, .2, .11)
		"ding":
			Synth.tone(m, 0, .9, 1318, 1318, "sine", .2, .003)
			Synth.tone(m, 0, .5, 2637, 2637, "sine", .06, .003)
			Synth.tone(m, 0, .3, 3951, 3951, "sine", .025, .003)
		"shimmer":
			Synth.notes(m, 0, [1568, 1976, 2349, 2637, 3136], .04, .26, .075)
		"confetti":
			Synth.notes(m, 0, [523, 659, 784], .09, .16, .13)
			Synth.tone(m, .27, .5, 1047, 1047, "triangle", .13, .004)
			for i in 10:
				Synth.noise(m, .05 + m.rng.randf() * .7, .03, .05, "highpass", 3000, 3000)
		"page":
			Synth.noise(m, 0, .2, .22, "bandpass", 1800, 4200, .8, .02)
			Synth.noise(m, .16, .12, .14, "bandpass", 2500, 4500, .8)
		"tick":
			Synth.tone(m, 0, .03, 1500, 1500, "sine", .1)
		"snore":
			Synth.noise(m, 0, .75, .15, "lowpass", 520, 280, 1, .25)
			Synth.tone(m, 0, .75, 92, 84, "sine", .05, .25)
		"yawn":
			Synth.tone(m, 0, .95, 520, 240, "sine", .16, .12, 10, 5)
		"startle":
			Synth.tone(m, 0, .1, 600, 1400, "sine", .24)
			Synth.tone(m, .1, .1, 1400, 1100, "sine", .14)
		"tear":
			Synth.tone(m, 0, .13, 1600, 1150, "sine", .11)
			Synth.tone(m, 0, .06, 2400, 2400, "sine", .04)
		"sniffle":
			Synth.noise(m, 0, .1, .2, "bandpass", 1200, 2600, 1.5)
			Synth.noise(m, .14, .12, .2, "bandpass", 1300, 2800, 1.5)
		"sigh":
			Synth.noise(m, 0, .95, .14, "bandpass", 950, 380, .6, .22)
			Synth.tone(m, 0, .85, 300, 200, "sine", .035, .2)
		"glitch":
			for i in 6:
				Synth.tone(m, i * .035, .03, 300 + m.rng.randf() * 1500, 300 + m.rng.randf() * 1500, "square", .08, .002)
		"boing":
			Synth.tone(m, 0, .38, 220, 520, "sine", .24, .005, 70, 18)
		"wobble":
			Synth.tone(m, 0, .6, 500, 380, "sine", .09, .05, 25, 4)
		"hum":
			Synth.tone(m, 0, .9, 110, 110, "sine", .08, .25)
			Synth.tone(m, 0, .9, 220, 220, "sine", .035, .25)
		"powerdown":
			Synth.tone(m, 0, .5, 900, 150, "triangle", .13)
		"power":
			Synth.tone(m, 0, .18, 500, 900, "triangle", .08)
			Synth.notes(m, .1, [1568, 1976, 2349, 2637, 3136], .04, .26, .075 * .8)
		"powerup":
			Synth.tone(m, 0, .45, 200, 1200, "triangle", .15)
			Synth.notes(m, .38, [2093, 2637, 3136], .055, .2, .11)
		"rumble":
			Synth.tone(m, 0, .55, 72, 64, "sawtooth", .22, .04, 10, 11, 230)
			Synth.tone(m, 0, .5, 55, 52, "sine", .16, .04)
		"drip":
			Synth.tone(m, 0, .11, 1250, 620, "sine", .11)
		"please":
			Synth.tone(m, 0, .3, 820, 1060, "sine", .1, .04, 10, 8)
		"servo":
			Synth.noise(m, 0, .22, .2, "bandpass", 700, 1150, 3, .03)
			Synth.tone(m, 0, .22, 180, 240, "sawtooth", .07, .03, 0, 6, 900)
		"purr":
			_purr(m)

# A low sawtooth through a lowpass, pulsing at 24 Hz.
func _purr(m: Synth.Mix) -> void:
	var out := PackedFloat32Array()
	out.resize(int(2.6 * Synth.RATE))
	var lp := Synth.Biquad.new("lowpass")
	var phase := 0.0
	for i in out.size():
		var t := float(i) / Synth.RATE
		phase += TAU * 58.0 / Synth.RATE
		var trem := 0.5 + 0.5 * sin(TAU * 24.0 * t)
		out[i] = lp.step(Synth.wave("sawtooth", phase), 210.0) * trem * Synth.env(t, 2.5, 0.16, 0.35)
	m.add(0.0, out)
