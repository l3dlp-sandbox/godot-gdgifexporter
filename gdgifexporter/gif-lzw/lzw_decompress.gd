@tool
extends RefCounted

var lsbbitunpacker := preload("./lsbbitunpacker.gd")


class CodeEntry:
	var sequence: PackedByteArray
	var raw_array: Array

	func _init(_sequence):
		raw_array = _sequence
		sequence = _sequence

	func add(other):
		return CodeEntry.new(self.raw_array + other.raw_array)

	func _to_string():
		var result: String = ""
		for element in self.sequence:
			result += str(element) + ", "
		return result.substr(0, result.length() - 2)


class CodeTable:
	var entries: Dictionary = {}
	var counter: int = 0
	var lookup: Dictionary = {}

	func add(entry) -> int:
		self.entries[self.counter] = entry
		self.lookup[entry.raw_array] = self.counter
		counter += 1
		return counter

	func find(entry) -> int:
		return self.lookup.get(entry.raw_array, -1)

	func has(entry) -> bool:
		return self.find(entry) != -1

	func get_entry(index) -> CodeEntry:
		return self.entries.get(index, null)

	func _to_string() -> String:
		var result: String = "CodeTable:\n"
		for id in self.entries:
			result += str(id) + ": " + self.entries[id].to_string() + "\n"
		result += "Counter: " + str(self.counter) + "\n"
		return result


func log2(value: float) -> float:
	return log(value) / log(2.0)


func get_bits_number_for(value: int) -> int:
	if value == 0:
		return 1
	return ceili(log2(value + 1))


func initialize_color_code_table(colors: PackedByteArray) -> CodeTable:
	var result_code_table: CodeTable = CodeTable.new()
	for color_id in colors:
		# warning-ignore:return_value_discarded
		result_code_table.add(CodeEntry.new([color_id]))
	# move counter to the first available compression code index
	var last_color_index: int = colors.size() - 1
	var clear_code_index: int = pow(2, get_bits_number_for(last_color_index))
	result_code_table.counter = clear_code_index + 2
	return result_code_table


# compression and decompression done with source:
# http://www.matthewflickinger.com/lab/whatsinagif/lzw_image_data.asp
# gdlint: ignore=max-line-length
func decompress_lzw(code_stream_data: PackedByteArray, min_code_size: int, colors: PackedByteArray) -> PackedByteArray:
	var code_table: CodeTable = initialize_color_code_table(colors)
	var index_stream: PackedByteArray = PackedByteArray([])
	var binary_code_stream = lsbbitunpacker.LSBLZWBitUnpacker.new(code_stream_data)
	var current_code_size: int = min_code_size + 1
	var clear_code_index: int = pow(2, min_code_size)

	# CODE is an index of code table, {CODE} is sequence inside
	# code table with index CODE. The same goes for PREVCODE.

	# Remove first Clear Code from stream. We don't need it.
	binary_code_stream.remove_bits(current_code_size)

	# let CODE be the first code in the code stream
	var code: int = binary_code_stream.read_bits(current_code_size)
	# output {CODE} to index stream
	index_stream.append_array(code_table.get_entry(code).sequence)
	# set PREVCODE = CODE
	var prevcode: int = code
	# <LOOP POINT>
	while true:
		# let CODE be the next code in the code stream
		code = binary_code_stream.read_bits(current_code_size)
		# Detect Clear Code. When detected reset everything and get next code.
		if code == clear_code_index:
			code_table = initialize_color_code_table(colors)
			current_code_size = min_code_size + 1
			code = binary_code_stream.read_bits(current_code_size)
		elif code == clear_code_index + 1:  # Stop when detected EOI Code.
			break
		# is CODE in the code table?
		var code_entry: CodeEntry = code_table.get_entry(code)
		if code_entry != null:  # if YES
			# output {CODE} to index stream
			index_stream.append_array(code_entry.sequence)
			# let k be the first index in {CODE}
			var k: CodeEntry = CodeEntry.new([code_entry.sequence[0]])
			# warning-ignore:return_value_discarded
			# add {PREVCODE} + k to the code table
			code_table.add(code_table.get_entry(prevcode).add(k))
			# set PREVCODE = CODE
			prevcode = code
		else:  # if NO
			# let k be the first index of {PREVCODE}
			var prevcode_entry: CodeEntry = code_table.get_entry(prevcode)
			var k: CodeEntry = CodeEntry.new([prevcode_entry.sequence[0]])
			# output {PREVCODE} + k to index stream
			index_stream.append_array(prevcode_entry.add(k).sequence)
			# add {PREVCODE} + k to code table
			# warning-ignore:return_value_discarded
			code_table.add(prevcode_entry.add(k))
			# set PREVCODE = CODE
			prevcode = code

		# Detect when we should increase current code size and increase it.
		var new_code_size_candidate: int = get_bits_number_for(code_table.counter)
		if new_code_size_candidate > current_code_size:
			current_code_size = new_code_size_candidate

	return index_stream
