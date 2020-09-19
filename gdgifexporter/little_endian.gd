extends RefCounted


func int_to_word(value: int) -> PackedByteArray:
	return PackedByteArray([value & 255, (value >> 8) & 255])

func word_to_int(value: PackedByteArray) -> int:
	return (value[1] << 8) | value[0]

