class_name ISSScreens
extends RefCounted
## Base of the front-end screen ports: each subclass registers the screen
## handlers it ports (tbl_screen_handlers) and keeps the ROM's structure,
## one function per routine, named after it. Shorthands for the RAM
## (ISSRam), the symbols (S) and the menu engine's helpers (m).

const S := preload("res://iss/iss_sym.gd")
const PAD_UP := 0x01
const PAD_DOWN := 0x02
const PAD_LEFT := 0x04
const PAD_RIGHT := 0x08
const PAD_B := 0x10
const PAD_C := 0x20
const PAD_A := 0x40
const PAD_START := 0x80
const T := ISSMenu.O_TIMER

var m: ISSMenu


func _init(menu: ISSMenu) -> void:
	m = menu


## Override: map screen numbers to their handlers.
func register(_handlers: Dictionary) -> void:
	pass


func w(a: int) -> int:
	return ISSRam.w(a)


func sw(a: int) -> int:
	return ISSRam.sw(a)


func l(a: int) -> int:
	return ISSRam.l(a)


func set_w(a: int, v: int) -> void:
	ISSRam.set_w(a, v)


func set_l(a: int, v: int) -> void:
	ISSRam.set_l(a, v)


func add_w(a: int, v: int) -> void:
	ISSRam.add_w(a, v)


## g_pad_pressed_any & bits.
func pressed(bits: int) -> bool:
	return w(S.g_pad_pressed_any) & bits != 0


func rom(name: String) -> int:
	return ISSRom.addr(name)


## A new object with only an update callback (draw and think -1).
func spawn(update: Callable) -> ISSMenu.Obj:
	var o := m.obj_alloc()
	if o != null:
		o.update = update
	return o


## Leave for screen n of state_menu with the fade, as the screens do.
func goto_screen(n: int) -> void:
	set_l(S.g_next_state, ISSMenu.STATE_MENU)
	set_w(S.g_next_screen, n)
	m.fade_out_start()
