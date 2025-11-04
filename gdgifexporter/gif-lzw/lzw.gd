extends RefCounted

var lsbbitpacker := preload("./lsbbitpacker.gd")
var lsbbitunpacker := preload("./lsbbitunpacker.gd")

var code_table: Dictionary[PackedByteArray, int] = {}
var entries_counter := 0


func get_bit_length(value: int) -> int:
	# bitwise or on value does ensure that the function works with value 0
	# long number at the end is log(2.0)
	return ceili(log(value | 0x1 + 1) / 0.6931471805599453)


func initialize_color_code_table(colors: PackedByteArray) -> void:
	code_table.clear()
	entries_counter = 0
	for color_id in colors:
		# warning-ignore:return_value_discarded
		code_table[PackedByteArray([color_id])] = entries_counter
		entries_counter += 1
	# move counter to the first available compression code index
	var last_color_index: int = colors.size() - 1
	var clear_code_index: int = pow(2, get_bit_length(last_color_index))
	entries_counter = clear_code_index + 2


# compression and decompression done with source:
# http://www.matthewflickinger.com/lab/whatsinagif/lzw_image_data.asp


func compress_lzw(index_stream: PackedByteArray, colors: PackedByteArray) -> Array:
	# Initialize code table
	initialize_color_code_table(colors)
	# Clear Code index is 2**<code size>
	# <code size> is the amount of bits needed to write down all colors
	# from color table. We use last color index because we can write
	# all colors (for example 16 colors) with indexes from 0 to 15.
	# Number 15 is in binary 0b1111, so we'll need 4 bits to write all
	# colors down.
	var last_color_index: int = colors.size() - 1
	var clear_code_index: int = pow(2, get_bit_length(last_color_index))
	var current_code_size: int = get_bit_length(clear_code_index)
	var binary_code_stream = lsbbitpacker.LSBLZWBitPacker.new()

	# initialize with Clear Code
	binary_code_stream.write_bits(clear_code_index, current_code_size)

	# Read first index from index stream.
	var index_buffer := PackedByteArray([index_stream[0]])
	var data_index: int = 1
	# <LOOP POINT>
	while data_index < index_stream.size():
		# Get the next index from the index stream.
		var k := index_stream[data_index]
		data_index += 1
		# Is index buffer + k in our code table?
		var new_index_buffer := PackedByteArray(index_buffer)
		new_index_buffer.push_back(k)
		if code_table.has(new_index_buffer):  # if YES
			# Add k to the end of the index buffer
			index_buffer = new_index_buffer
		else:  # if NO
			# Add a row for index buffer + k into our code table
			binary_code_stream.write_bits(code_table.get(index_buffer, -1), current_code_size)

			# We don't want to add new code to code table if we've exceeded 4095
			# index.
			var last_entry_index: int = entries_counter - 1
			if last_entry_index != 4095:
				# Output the code for just the index buffer to our code stream
				# warning-ignore:return_value_discarded
				code_table[new_index_buffer] = entries_counter
				entries_counter += 1
			else:
				# if we exceeded 4095 index (code table is full), we should
				# output Clear Code and reset everything.
				binary_code_stream.write_bits(clear_code_index, current_code_size)
				initialize_color_code_table(colors)
				# get_bits_number_for(clear_code_index) is the same as
				# LZW code size + 1
				current_code_size = get_bit_length(clear_code_index)

			# Detect when you have to save new codes in bigger bits boxes
			# change current code size when it happens because we want to save
			# flexible code sized codes
			var new_code_size_candidate: int = get_bit_length(entries_counter - 1)
			if new_code_size_candidate > current_code_size:
				current_code_size = new_code_size_candidate

			# Index buffer is set to k
			index_buffer = PackedByteArray([k])
	# Output code for contents of index buffer
	binary_code_stream.write_bits(code_table.get(index_buffer, -1), current_code_size)

	# output end with End Of Information Code
	binary_code_stream.write_bits(clear_code_index + 1, current_code_size)

	var min_code_size: int = get_bit_length(clear_code_index) - 1

	return [binary_code_stream.pack(), min_code_size]


# gdlint: ignore=max-line-length


func decompress_lzw(code_stream_data: PackedByteArray, min_code_size: int, colors: PackedByteArray) -> PackedByteArray:
	var index_stream := PackedByteArray()
	var binary_code_stream = lsbbitunpacker.LSBLZWBitUnpacker.new(code_stream_data)

	# Initialize code table
	initialize_color_code_table(colors)

	var current_code_size: int = min_code_size + 1
	var clear_code_index: int = pow(2, min_code_size)

	# Remove first Clear Code from stream (we don’t need it)
	binary_code_stream.remove_bits(current_code_size)

	# Read first code
	var code: int = binary_code_stream.read_bits(current_code_size)
	index_stream.append_array(code_table.keys()[code])
	var prev_code: int = code

	while true:
		code = binary_code_stream.read_bits(current_code_size)

		# Detect Clear Code (reset)
		if code == clear_code_index:
			initialize_color_code_table(colors)
			current_code_size = min_code_size + 1
			code = binary_code_stream.read_bits(current_code_size)
			prev_code = code
			index_stream.append_array(code_table.keys()[code])
			code = binary_code_stream.read_bits(current_code_size)
			continue

		# End of Information code
		elif code == clear_code_index + 1:
			break

		var entry: PackedByteArray = code_table.keys()[code] if code_table.has(code_table.keys()[code]) else null

		if entry != null:
			# output {CODE}
			index_stream.append_array(entry)
			# K is the first element of {CODE}
			var K := PackedByteArray([entry[0]])
			# add {PREVCODE} + K
			var new_entry := PackedByteArray(code_table.keys()[prev_code])
			new_entry.append_array(K)
			code_table[new_entry] = entries_counter
			entries_counter += 1
			prev_code = code
		else:
			# if CODE not in table
			var prev_entry: PackedByteArray = code_table.keys()[prev_code]
			var K := PackedByteArray([prev_entry[0]])
			var new_entry := PackedByteArray(prev_entry)
			new_entry.append_array(K)
			index_stream.append_array(new_entry)
			code_table[new_entry] = entries_counter
			entries_counter += 1
			prev_code = code

		# Update bit length if needed
		var new_size := get_bit_length(entries_counter)
		if new_size > current_code_size and new_size <= 12:
			current_code_size = new_size

	return index_stream
