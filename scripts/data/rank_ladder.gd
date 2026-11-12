class_name RankLadder
extends Resource
## Kuiz's school title for each band of levels: titles[i] is held from level from_levels[i] up to the
## next band. One ladder, assets/data/ranks.tres. Contract: docs/systems/companion-care.md §3.

@export var from_levels: Array[int] = []
@export var titles: Array[String] = []

## The title held at `level` (the last band has no end).
func title(level: int) -> String:
	var t := ""
	for i in from_levels.size():
		if level >= from_levels[i]:
			t = titles[i]
	return t
