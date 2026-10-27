extends RefCounted
## Short codes for regular puzzles, like "8H-142": the size, the difficulty's
## initial and the puzzle number. Puzzles are generated from those three, so a
## friend who enters the code gets the same board.

const Generator := preload("res://scripts/generator.gd")


static func encode(size: int, difficulty: int, number: int) -> String:
	return "%d%s-%d" % [size, Generator.DIFFICULTY_NAMES[difficulty][0], number]


## {"size", "difficulty", "number"} from the first code found in `text`, so a
## whole pasted message works too; empty when there is none or it's out of range.
static func decode(text: String, sizes: Array) -> Dictionary:
	var regex := RegEx.create_from_string("(\\d{1,2})\\s*([A-Za-z])\\s*[-–—#]?\\s*(\\d{1,6})")
	for found in regex.search_all(text):
		var size := found.get_string(1).to_int()
		var difficulty := -1
		for i in Generator.DIFFICULTY_NAMES.size():
			if Generator.DIFFICULTY_NAMES[i][0] == found.get_string(2).to_upper():
				difficulty = i
		var number := found.get_string(3).to_int()
		if size in sizes and difficulty >= 0 and number >= 1:
			return {"size": size, "difficulty": difficulty, "number": number}
	return {}
