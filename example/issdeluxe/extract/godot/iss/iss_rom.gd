class_name ISSRom
extends RefCounted
## The game's data as its code reads it: the main program's data blocks
## (assets/iss/rom_data.bin, addressed as in the ROM and named by the
## symbols file) and the resource archive (assets/iss/res/gGG_eEE.bin, each
## packed entry unpacked). The front end's screens are ports of the game's
## own code, so they read their tables here by symbol and address, and load
## resources by group and entry as the loaders do.

const DIR := "res://assets/iss/"

static var _data := PackedByteArray()
static var _blocks: Array = []   # [addr, offset, length], sorted by addr
static var _symbols := {}
static var _res := {}


static func ensure_loaded() -> void:
	if not _blocks.is_empty():
		return
	_data = FileAccess.get_file_as_bytes(DIR + "rom_data.bin")
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "rom_data.json"))
	for b: Dictionary in j["blocks"]:
		_blocks.append([int(b["addr"]), int(b["offset"]), int(b["length"])])
	for k: String in j["symbols"]:
		_symbols[k] = int(j["symbols"][k])


## The address of a data symbol (an error when it is not a data block's).
static func addr(name: String) -> int:
	ensure_loaded()
	assert(_symbols.has(name), "ISSRom: no data symbol " + name)
	return int(_symbols.get(name, 0))


static func _offset(a: int) -> int:
	ensure_loaded()
	var lo := 0
	var hi := _blocks.size() - 1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		var b: Array = _blocks[mid]
		if a < b[0]:
			hi = mid - 1
		elif a >= b[0] + b[2]:
			lo = mid + 1
		else:
			return b[1] + a - b[0]
	push_error("ISSRom: $%06X is not in a data block" % a)
	return 0


static func u8(a: int) -> int:
	return _data[_offset(a)]


static func s8(a: int) -> int:
	var v := u8(a)
	return v - 256 if v >= 128 else v


static func u16(a: int) -> int:
	var o := _offset(a)
	return (_data[o] << 8) | _data[o + 1]


static func s16(a: int) -> int:
	var v := u16(a)
	return v - 65536 if v >= 32768 else v


static func u32(a: int) -> int:
	return (u16(a) << 16) | u16(a + 2)


static func bytes(a: int, n: int) -> PackedByteArray:
	var o := _offset(a)
	return _data.slice(o, o + n)


## A string as the text helpers read it: bytes up to the $FF terminator
## (any byte with bit 7 set ends it).
static func string(a: int) -> PackedByteArray:
	var out := PackedByteArray()
	var o := _offset(a)
	while _data[o] < 0x80:
		out.append(_data[o])
		o += 1
	return out


## Entry e of resource group g: unpacked when packed, else its raw bytes
## (empty when there is no such entry).
static func res(g: int, e: int) -> PackedByteArray:
	var key := g * 256 + e
	if not _res.has(key):
		var out := PackedByteArray()
		for ext: String in [".bin", ".raw"]:
			var p := DIR + "res/g%02d_e%02d" % [g, e] + ext
			if FileAccess.file_exists(p):
				out = FileAccess.get_file_as_bytes(p)
				break
		_res[key] = out
	return _res[key]
