// Command extract pulls game-specific data out of International Superstar
// Soccer Deluxe (Mega Drive) in Godot-friendly formats. Run it after
// `sega2asm godot issdeluxe.yaml`; it writes into <godot>/assets/iss:
//
//	players/frames/*.png   every player animation frame, right- and
//	                       left-facing, as CRAM-index images (pixel value =
//	                       palette line * 16 + colour; draw them with
//	                       md/md_indexed.gdshader and a 16x4 palette texture)
//	players/animations.json  74 actions x 8 directions -> frame sequences,
//	                       frame origins and sprite piece lists
//	players/kits.json      first/second kit palettes and head masks, 43 teams
//	players/palette_match.pal.png  representative match palette (home kit on
//	                       line 0, away kit on line 1, officials' kit and skin
//	                       on line 2, stadium / ball / shadows on line 3)
//	ball/                  ball and shadow frames for 5 actions x 8 directions
//	npc/                   referee, linesmen, medics, stretcher and dog frames,
//	                       animations, officials' kit variants
//	flags/                 corner and halfway flags
//	stadiums/*             8 stadiums x snow/fine/rain weather: full renders,
//	                       16x16 metatile atlases, maps, palettes, tile sheets
//	weather/               plane A snow and rain overlays, one image per
//	                       animation state, and their timing
//	hud/                   match HUD: window, team flags and names, digits,
//	                       radar background and per-stadium radar mapping
//
// and GDScript classes plus a demo scene into <godot>/iss.
//
//	go run ./example/issdeluxe/extract -rom <rom> -out example/issdeluxe/out/godot
package main

import (
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	"image/color"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"sega2asm/compress"
	"sega2asm/types"
)

// ROM addresses (see issdeluxe_symbols.txt).
const (
	resDirectory   = 0x05DB50 // resource archive directory
	frameTable     = 0x0210DE // player animations: [action][direction][frame] -> descriptor
	attrRight      = 0x020F5E // sprite attribute words, right-facing
	attrLeft       = 0x02101E // sprite attribute words, left-facing (h-flip toggled)
	headMaskHome   = 0x037402 // per-team AND masks applied to head tiles (home)
	headMaskAway   = 0x037458 // (away)
	numTeams       = 43
	grpSprites     = 0  // res00: uncompressed player body tiles (long offsets)
	grpPlayers     = 6  // res06: kit tiles, heads, hair, kit palettes
	entKitTiles1   = 3  // 7 tiles per team, first kit
	entHeads       = 5  // face tiles (packed)
	entHair        = 9  // hair tiles, $260 bytes per style (raw)
	entKitPalette1 = 12 // 16 colours per team, first kit
	entKitPalette2 = 13 // 16 colours per team, second kit
	grpMatchPal    = 17 // res17 entry 2: palette line 2 during a match
	grpStadium0    = 7  // res07..res14: stadium sets
	numStadiums    = 8
	tblPlayerNames = 0x035916 // 43 pointers -> 20 x 8-character player names
	tblPlayerData  = 0x038140 // 43 pointers -> 20 x 12-byte player records
	tblTeamRatings = 0x03AB82 // 5 bytes per team
	tblKitClash    = 0x0374AE // word per team: equal values force the away team's second kit
	tblPitchBounds = 0x016E62 // per stadium: left, right, top, bottom
	playersPerTeam = 20
)

var rom []byte

// Godot scripts and the demo scene copied into <out>/iss.
//
//go:embed godot
var godotFiles embed.FS

func be16(a uint32) uint32 { return uint32(rom[a])<<8 | uint32(rom[a+1]) }
func be32(a uint32) uint32 { return be16(a)<<16 | be16(a+2) }
func s16(a uint32) int     { return int(int16(be16(a))) }

func group(g int) uint32 { return resDirectory + be32(resDirectory+uint32(4*g)) }

// entry returns the address of entry e of group g.
func entry(g, e int) uint32 {
	ga := group(g)
	if be16(ga) == 0 {
		return ga + be32(ga+uint32(4*e))
	}
	return ga + be16(ga+uint32(2*e))
}

// unpack decodes a packed entry ("P1"/"P2"/"P3").
func unpack(a uint32) []byte {
	d, err := compress.DecompressLZFactor5(rom[a:])
	if err != nil {
		fail(err)
	}
	return d
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "extract:", err)
	os.Exit(1)
}

func main() {
	romPath := flag.String("rom", "", "ROM file")
	out := flag.String("out", "out/godot", "Godot project directory")
	flag.Parse()
	var err error
	if rom, err = os.ReadFile(*romPath); err != nil {
		fail(err)
	}
	dir := filepath.Join(*out, "assets", "iss", "players")
	if err := os.MkdirAll(filepath.Join(dir, "frames"), 0755); err != nil {
		fail(err)
	}
	kits := exportKits(dir)
	exportMatchPalette(dir, kits)
	exportAnimations(dir)
	exportBall(filepath.Join(*out, "assets", "iss", "ball"))
	exportNPCs(filepath.Join(*out, "assets", "iss", "npc"))
	exportFlags(filepath.Join(*out, "assets", "iss", "flags"))
	exportStadiums(filepath.Join(*out, "assets", "iss", "stadiums"))
	exportWeather(filepath.Join(*out, "assets", "iss", "weather"))
	exportHUD(filepath.Join(*out, "assets", "iss", "hud"))
	exportTeams(filepath.Join(*out, "assets", "iss"))
	writeScripts(*out)
}

// writeScripts copies the embedded GDScript classes and demo scene.
func writeScripts(out string) {
	must(fs.WalkDir(godotFiles, "godot", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := godotFiles.ReadFile(p)
		if err != nil {
			return err
		}
		t := filepath.Join(out, filepath.FromSlash(strings.TrimPrefix(p, "godot/")))
		if err := os.MkdirAll(filepath.Dir(t), 0755); err != nil {
			return err
		}
		return os.WriteFile(t, b, 0644)
	}))
	fmt.Println("scripts: iss/ (ISSPitch, ISSWeather, ISSFlags, ISSHud, ISSPlayerSprite, ISSBallSprite, ISSNPCSprite, ISSProjection, iss_demo.tscn)")
}

// ---------------------------------------------------------------------------
// Kits
// ---------------------------------------------------------------------------

type teamKit struct {
	Team         int      `json:"team"`
	FirstKit     []uint16 `json:"first_kit"`
	SecondKit    []uint16 `json:"second_kit"`
	HeadMaskHome uint16   `json:"head_mask_home"`
	HeadMaskAway uint16   `json:"head_mask_away"`
}

func exportKits(dir string) []teamKit {
	p1 := entry(grpPlayers, entKitPalette1)
	p2 := entry(grpPlayers, entKitPalette2)
	var kits []teamKit
	for t := 0; t < numTeams; t++ {
		k := teamKit{Team: t, HeadMaskHome: uint16(be16(headMaskHome + uint32(2*t))), HeadMaskAway: uint16(be16(headMaskAway + uint32(2*t)))}
		for i := 0; i < 16; i++ {
			k.FirstKit = append(k.FirstKit, uint16(be16(p1+uint32(t*32+i*2))))
			k.SecondKit = append(k.SecondKit, uint16(be16(p2+uint32(t*32+i*2))))
		}
		kits = append(kits, k)
	}
	writeJSON(filepath.Join(dir, "kits.json"), map[string]any{
		"description": "Kit palettes (CRAM words) per team: the home team uses palette line 0, the away team line 1. " +
			"Head tiles are ANDed with the team's head mask to select skin and hair colours.",
		"teams": kits,
	})
	return kits
}

// exportMatchPalette writes a representative match palette: home and away
// first kits on lines 0 and 1, line 2 as loaded from res17 entry 2 with the
// officials' first kit in colours 0-7, line 3 = stadium 0 in fine weather
// (g_weather 1)
// (the pitch, the ball and all shadows).
func exportMatchPalette(dir string, kits []teamKit) {
	line2 := unpack(entry(grpMatchPal, 2))
	img := image.NewRGBA(image.Rect(0, 0, 16, 4))
	setLine(img, 0, kits[0].FirstKit)
	setLine(img, 1, kits[1].FirstKit)
	var words []uint16
	for i := 0; i+1 < len(line2) && i < 32; i += 2 {
		words = append(words, uint16(line2[i])<<8|uint16(line2[i+1]))
	}
	setLine(img, 2, words)
	setLine(img, 2, officialKit(0))
	setLine(img, 3, stadiumLine(0, 1))
	if err := types.WritePNG(filepath.Join(dir, "palette_match.pal.png"), img); err != nil {
		fail(err)
	}
}

// ---------------------------------------------------------------------------
// Animations
// ---------------------------------------------------------------------------

type piece struct {
	X         int  `json:"x"` // relative to the object position
	Y         int  `json:"y"`
	W         int  `json:"w"` // size in cells
	H         int  `json:"h"`
	Tile      int  `json:"tile"` // tile in the object's VRAM slot
	Line      int  `json:"line"`
	HFlip     bool `json:"hflip"`
	VFlip     bool `json:"vflip"`
	Priority  bool `json:"priority"`
	AttrIndex *int `json:"attr_index,omitempty"` // players: index into the attribute tables
}

type frameOut struct {
	Address    string  `json:"address"`
	BodyEntry  int     `json:"body_entry"`
	BodyOffset int     `json:"body_offset"`
	BodyTiles  int     `json:"body_tiles"`
	HeadOffset int     `json:"head_offset"`
	KitOffset  int     `json:"kit_offset"`
	HairOffset int     `json:"hair_offset"`
	Right      *render `json:"right"`
	Left       *render `json:"left"`
}

type render struct {
	PNG     string  `json:"png"`
	OriginX int     `json:"origin_x"` // object position inside the image
	OriginY int     `json:"origin_y"`
	Pieces  []piece `json:"pieces"`
}

func exportAnimations(dir string) {
	heads := unpack(entry(grpPlayers, entHeads))
	hair := rom[entry(grpPlayers, entHair):]
	kitTiles := unpack(entry(grpPlayers, entKitTiles1))

	// Actions: consecutive pointers from frameTable.
	var actions []uint32
	for a := uint32(frameTable); ; a += 4 {
		v := be32(a)
		if v < 0x20000 || v >= 0x40000 || a >= actions0(actions) {
			break
		}
		actions = append(actions, v)
	}
	frames := map[uint32]*frameOut{}
	type actionOut struct {
		Index      int        `json:"index"`
		Address    string     `json:"address"`
		Directions [][]string `json:"directions"`
	}
	var outActions []actionOut
	for i, ap := range actions {
		ao := actionOut{Index: i, Address: fmt.Sprintf("$%06X", ap)}
		dirs := make([]uint32, 8)
		for k := range dirs {
			dirs[k] = be32(ap + uint32(4*k))
		}
		// Frame lists end where the next list (or the first frame) begins.
		ends := boundaries(dirs)
		for _, dp := range dirs {
			var seq []string
			for fa := dp; fa < ends[dp]; fa += 4 {
				f := be32(fa)
				if f < 0x20000 || f >= 0x40000 {
					break
				}
				if !validFrame(f) {
					break
				}
				seq = append(seq, fmt.Sprintf("$%06X", f))
				if _, ok := frames[f]; !ok {
					frames[f] = decodeFrame(f, dir, heads, hair, kitTiles)
				}
			}
			ao.Directions = append(ao.Directions, seq)
		}
		outActions = append(outActions, ao)
	}
	var addrs []uint32
	for a := range frames {
		addrs = append(addrs, a)
	}
	sort.Slice(addrs, func(i, j int) bool { return addrs[i] < addrs[j] })
	fm := map[string]*frameOut{}
	for _, a := range addrs {
		fm[fmt.Sprintf("$%06X", a)] = frames[a]
	}
	writeJSON(filepath.Join(dir, "animations.json"), map[string]any{
		"action_names": playerActionNames,
		"description": "Player animations: actions[action].directions[d] lists frame addresses. " +
			"Direction d = ((facing + 4) & $38) >> 3 with facing 0-63; directions 5-7 use the left-facing render. " +
			"Frames are rendered with face style 1, hair style 0 and the kit tiles of team 0.",
		"actions": outActions,
		"frames":  fm,
	})
	fmt.Printf("players: %d actions, %d unique frames\n", len(outActions), len(frames))
}

// teamNames transcribes the team name plates (res06 entry 0); team 42 is
// the practice side of the training modes and has no plate.
var teamNames = []string{
	"England", "Germany", "Italy", "Wales", "Scotland", "N.Ireland", "France", "Holland", "Norway",
	"Spain", "Ireland", "Portugal", "Sweden", "Czech Rep.", "Denmark", "Austria", "Belgium", "Poland",
	"Romania", "Russia", "Bulgaria", "Swiss", "Croatia", "Greece", "Japan", "Turkey", "S.Korea",
	"Nigeria", "Cameroon", "Morocco", "Brazil", "Argentina", "Columbia", "Mexico", "U.S.A",
	"Uruguay", "All Star", "Eurostar A", "Eurostar B", "Asian Star", "African Star",
	"All Amer.Star", "Practice",
}

// playerActionNames labels obj_action values (tbl_player_anims), from the
// routines that set them and the frames; "(?)" marks a best guess.
var playerActionNames = []string{
	"stand", "ready stance", "jog on the spot", "turn step", "side step", "shuffle step",
	"run", "walk", "run crouched (?)", "sprint (dash)", "pull up", "turn",
	"knee trap", "short poke", "power kick (shot, long ball)", "side-foot pass",
	"kick to the left", "kick to the right", "backheel", "standing header / volley",
	"overhead kick", "jumping header", "diving header", "sliding tackle / stretched kick",
	"sit after a slide", "get up", "stumble", "dejected (hands on head)", "stand still",
	"hands over face", "celebration: fist pump", "celebration: knee slide",
	"celebration: arm up", "celebration: dance", "celebration: jump", "full-length dive",
	"fall backwards (fouled)", "bend down (place the ball)", "defensive wall", "lying injured",
	"lose the ball (stumble forward)", "feint left (?)", "feint right (?)", "arm raised (?)",
	"stop the ball", "leap (?)", "flick the ball up (?)", "chip", "goalkeeper curled on the ball",
	"knock on and run", "wall shuffle", "walk, arms out (?)", "bend over", "celebration: belly slide",
}

// actions0 bounds the action table by the first action list it points to.
func actions0(actions []uint32) uint32 {
	min := uint32(0x40000)
	for _, a := range actions {
		if a < min {
			min = a
		}
	}
	return min
}

// boundaries maps each direction list start to the next list start (or the
// first frame descriptor, whichever comes first).
func boundaries(dirs []uint32) map[uint32]uint32 {
	uniq := map[uint32]bool{}
	for _, d := range dirs {
		uniq[d] = true
	}
	var s []uint32
	for d := range uniq {
		s = append(s, d)
	}
	sort.Slice(s, func(i, j int) bool { return s[i] < s[j] })
	out := map[uint32]uint32{}
	for i, d := range s {
		end := d + 0x400
		if i+1 < len(s) {
			end = s[i+1]
		}
		// A list also ends at its first frame descriptor.
		if f := be32(d); f > d && f < end {
			end = f
		}
		out[d] = end
	}
	return out
}

// validFrame sanity-checks a frame descriptor: body entry within res00,
// at most 20 body tiles, 1-32 pieces with sensible positions and sizes.
func validFrame(f uint32) bool {
	if f&1 != 0 || int(f)+14 > len(rom) {
		return false
	}
	if be16(f)%4 != 0 || be16(f)/4 >= 46 || be16(f+4)%32 != 0 || be16(f+4) > 20*32 {
		return false
	}
	n := be16(f+12) + 1
	if n > 32 {
		return false
	}
	for i := uint32(0); i < n; i++ {
		b := f + 14 + 10*i
		if rom[b+2] > 15 || rom[b+3] >= 0x60 {
			return false
		}
		if y, x := s16(b), s16(b+6); y < 0 || y > 256 || x < 0 || x > 256 {
			return false
		}
	}
	return true
}

// decodeFrame renders one frame descriptor in both facings.
func decodeFrame(f uint32, dir string, heads, hair, kit []byte) *frameOut {
	fo := &frameOut{
		Address:    fmt.Sprintf("$%06X", f),
		BodyEntry:  int(be16(f)) / 4,
		BodyOffset: int(be16(f + 2)),
		BodyTiles:  int(be16(f+4)) / 32,
		HeadOffset: s16(f + 6),
		KitOffset:  s16(f + 8),
		HairOffset: s16(f + 10),
	}
	// VRAM slot contents (as uploaded by the player draw routine at
	// $020BF0): body tiles from 0, tile 20 = head or kit tile, tile 21 = hair.
	fillSlot := func(left bool) []byte {
		slot := make([]byte, 32*32)
		body := entry(grpSprites, fo.BodyEntry) + uint32(fo.BodyOffset)
		copy(slot, rom[body:body+uint32(fo.BodyTiles*32)])
		if fo.HeadOffset >= 0 {
			off := fo.HeadOffset
			switch {
			case off > 0x40:
				off += 0x9A0
			case off == 0x20 && left:
				off = 0x60 // head turned the other way
			}
			if off+32 <= len(heads) {
				copy(slot[20*32:], heads[off:off+32])
			}
		}
		if fo.KitOffset >= 0 && fo.KitOffset+32 <= len(kit) {
			copy(slot[20*32:], kit[fo.KitOffset:fo.KitOffset+32])
		}
		if fo.HairOffset >= 0 && fo.HairOffset+32 <= len(hair) {
			copy(slot[21*32:], hair[fo.HairOffset:fo.HairOffset+32])
		}
		return slot
	}
	name := fmt.Sprintf("f_%06X", f)
	fo.Right = renderFrame(f, fillSlot(false), false, filepath.Join(dir, "frames", name+"_r.png"))
	fo.Left = renderFrame(f, fillSlot(true), true, filepath.Join(dir, "frames", name+"_l.png"))
	return fo
}

func renderFrame(f uint32, slot []byte, left bool, path string) *render {
	n := int(be16(f+12)) + 1
	attr := uint32(attrRight)
	if left {
		attr = attrLeft
	}
	var ps []piece
	for i := 0; i < n; i++ {
		b := f + 14 + uint32(10*i)
		size := int(rom[b+2])
		ai := int(rom[b+3])
		aw := be16(attr + uint32(ai))
		x := s16(b + 6)
		if left {
			x = s16(b + 8)
		}
		ps = append(ps, piece{
			X: x - 128, Y: s16(b) - 128, W: (size>>2)&3 + 1, H: size&3 + 1,
			Tile: s16(b + 4), Line: int(aw>>13) & 3, HFlip: aw&0x800 != 0, VFlip: aw&0x1000 != 0,
			Priority: aw&0x8000 != 0, AttrIndex: &ai,
		})
	}
	return drawPieces(ps, slot, path)
}

// drawPieces renders sprite pieces, their tiles taken from slot, into a
// CRAM-index image (pixel = line * 16 + colour) written to path.
func drawPieces(ps []piece, slot []byte, path string) *render {
	minX, minY, maxX, maxY := 1<<30, 1<<30, -(1 << 30), -(1 << 30)
	for _, p := range ps {
		minX, minY = imin(minX, p.X), imin(minY, p.Y)
		maxX, maxY = imax(maxX, p.X+p.W*8), imax(maxY, p.Y+p.H*8)
	}
	img := image.NewGray(image.Rect(0, 0, maxX-minX, maxY-minY))
	// Pieces are drawn in reverse so the first piece ends up on top, like
	// the VDP's sprite priority order.
	for i := len(ps) - 1; i >= 0; i-- {
		p := ps[i]
		for cx := 0; cx < p.W; cx++ {
			for cy := 0; cy < p.H; cy++ {
				t := p.Tile + cx*p.H + cy // tiles are column-major
				if t < 0 || t*32+32 > len(slot) {
					continue
				}
				tx, ty := cx, cy
				if p.HFlip {
					tx = p.W - 1 - cx
				}
				if p.VFlip {
					ty = p.H - 1 - cy
				}
				for y := 0; y < 8; y++ {
					for x := 0; x < 8; x++ {
						b := slot[t*32+y*4+x/2]
						v := b >> 4
						if x&1 == 1 {
							v = b & 15
						}
						if v == 0 {
							continue
						}
						px, py := x, y
						if p.HFlip {
							px = 7 - x
						}
						if p.VFlip {
							py = 7 - y
						}
						img.SetGray(p.X-minX+tx*8+px, p.Y-minY+ty*8+py, color.Gray{Y: uint8(p.Line*16) + v})
					}
				}
			}
		}
	}
	if err := types.WritePNG(path, img); err != nil {
		fail(err)
	}
	return &render{PNG: resPath(path), OriginX: -minX, OriginY: -minY, Pieces: ps}
}

func imin(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func imax(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func writeJSON(p string, v any) {
	b, err := json.MarshalIndent(v, "", " ")
	if err != nil {
		fail(err)
	}
	if err := os.WriteFile(p, b, 0644); err != nil {
		fail(err)
	}
}

// ---------------------------------------------------------------------------
// Stadiums
// ---------------------------------------------------------------------------

// Stadium group entries (see load_stadium_tiles / the pitch scroller):
//
//	1  map: width, height (in 16x16 metatiles), then width*height metatile words
//	2  metatile table: 4 nametable words per metatile (TL, TR, BL, BR),
//	   tile numbers relative to the stadium's first VRAM tile
//	3  tiles loaded at the stadium's VRAM base, 4 tiles loaded after them
//	5  18 tiles replacing tiles 238-255 (the snow clumps) in fine and rain
//	6  palette line 3 for g_weather 0 (snow), 7 fine, 8 rain
func exportStadiums(dir string) {
	if err := os.MkdirAll(dir, 0755); err != nil {
		fail(err)
	}
	type stadiumOut struct {
		Index      int            `json:"index"`
		Group      int            `json:"group"`
		Width      int            `json:"width_metatiles"`
		Height     int            `json:"height_metatiles"`
		Metatiles  int            `json:"metatile_count"`
		Pitch      map[string]int `json:"pitch_bounds"`
		Map        string         `json:"map"`
		Renders    []string       `json:"renders"`
		Atlases    []string       `json:"metatile_atlases"`
		Palettes   []string       `json:"palettes"`
		TileSheets []string       `json:"tile_sheets"`
	}
	var all []stadiumOut
	for st := 0; st < numStadiums; st++ {
		g := grpStadium0 + st
		m := unpack(entry(g, 1))
		blocks := unpack(entry(g, 2))
		base := append(unpack(entry(g, 3)), unpack(entry(g, 4))...)
		w, h := int(be16s(m, 0)), int(be16s(m, 2))
		nb := len(blocks) / 8
		so := stadiumOut{Index: st, Group: g, Width: w, Height: h, Metatiles: nb}
		// tbl_pitch_bounds: left, right, top, bottom (signed, pitch coordinates).
		b := uint32(tblPitchBounds + 8*st)
		so.Pitch = map[string]int{"left": s16(b), "right": s16(b + 2), "top": s16(b + 4), "bottom": s16(b + 6)}

		cells := make([]int, w*h)
		for i := range cells {
			cells[i] = int(be16s(m, 4+2*i))
		}
		mp := filepath.Join(dir, fmt.Sprintf("stadium%d_map.json", st))
		writeJSON(mp, map[string]any{
			"stadium": st, "width": w, "height": h, "metatile_size": 16,
			"metatiles": cells,
			"format":    "row-major metatile indices; metatile i = cells i*4..i*4+3 of stadiumN_metatiles.json",
		})
		so.Map = resPath(mp)
		var mt []int
		for i := 0; i < nb*4; i++ {
			mt = append(mt, int(be16s(blocks, 2*i)))
		}
		writeJSON(filepath.Join(dir, fmt.Sprintf("stadium%d_metatiles.json", st)), map[string]any{
			"stadium": st, "count": nb, "words": mt,
			"format": "4 VDP nametable words per 16x16 metatile (top-left, top-right, bottom-left, bottom-right); " +
				"tile numbers are relative to the stadium tile sheet",
		})

		for tod, name := range weatherNames {
			tiles := append([]byte(nil), base...)
			if tod > 0 {
				patch := unpack(entry(g, 5))
				copy(tiles[0x1DC0:], patch)
			}
			pal := unpack(entry(g, 6+tod))
			line := make([]color.RGBA, 16)
			for i := range line {
				line[i] = types.MDColor(uint16(be16s(pal, 2*i)))
			}
			// Palette texture (16x4, the pitch only uses line 3).
			pimg := image.NewRGBA(image.Rect(0, 0, 16, 4))
			for i, c := range line {
				pimg.SetRGBA(i, 3, c)
			}
			pp := filepath.Join(dir, fmt.Sprintf("stadium%d_%s.pal.png", st, name))
			must(types.WritePNG(pp, pimg))
			so.Palettes = append(so.Palettes, resPath(pp))
			if tod <= 1 { // snow uses the base tiles; fine and rain share the patched tiles
				idx, _ := types.TileSheet(tiles, 32, types.GrayPalette(16), false)
				tp := filepath.Join(dir, fmt.Sprintf("stadium%d_%s_tiles.png", st, map[bool]string{true: "snow", false: "grass"}[tod == 0]))
				must(types.WritePNG(tp, grayIndex(idx)))
				so.TileSheets = append(so.TileSheets, resPath(tp))
			}
			// Metatile atlas (32 metatiles per row) and full render.
			full := make([]color.RGBA, 64)
			copy(full[48:], line)
			atlas := image.NewRGBA(image.Rect(0, 0, 32*16, ((nb+31)/32)*16))
			for b := 0; b < nb; b++ {
				drawMetatile(atlas, (b%32)*16, (b/32)*16, blocks, b, tiles, full)
			}
			ap := filepath.Join(dir, fmt.Sprintf("stadium%d_%s_metatiles.png", st, name))
			must(types.WritePNG(ap, atlas))
			so.Atlases = append(so.Atlases, resPath(ap))
			img := image.NewRGBA(image.Rect(0, 0, w*16, h*16))
			for i, b := range cells {
				drawMetatile(img, (i%w)*16, (i/w)*16, blocks, b, tiles, full)
			}
			rp := filepath.Join(dir, fmt.Sprintf("stadium%d_%s.png", st, name))
			must(types.WritePNG(rp, img))
			so.Renders = append(so.Renders, resPath(rp))
		}
		all = append(all, so)
	}
	writeJSON(filepath.Join(dir, "stadiums.json"), map[string]any{
		"description": "Stadium maps built from 16x16 metatiles. Renders and metatile atlases are pre-coloured " +
			"per g_weather (0 snow, 1 fine, 2 rain); tile sheets are index images (colour 0-15) for use with md_indexed.gdshader.",
		"stadiums": all,
	})
	fmt.Printf("stadiums: %d x 3 weathers\n", len(all))
}

func be16s(b []byte, o int) uint32 { return uint32(b[o])<<8 | uint32(b[o+1]) }

func resPath(p string) string {
	i := strings.Index(filepath.ToSlash(p), "/assets/")
	return "res:/" + filepath.ToSlash(p)[i:]
}

func must(err error) {
	if err != nil {
		fail(err)
	}
}

// grayIndex converts a paletted image to a greyscale index image.
func grayIndex(p *image.Paletted) *image.Gray {
	g := image.NewGray(p.Rect)
	for i, v := range p.Pix {
		g.Pix[i] = v
	}
	return g
}

// weatherNames names the g_weather values: the front end defaults to 1;
// weather 0 keeps the snow clumps of the base tiles and animates falling
// snow on plane A (res04 entry 7), weather 2 animates rain (res04 entry 8).
var weatherNames = []string{"snow", "fine", "rain"}

// backdrop is the CRAM index of the backdrop colour below the HUD during a
// match: the HBlank chain installed by sub_01ACCA switches VDP register 7
// from line 2 colour 0 to line 3 colour 0 (the stadium's grass) at the
// HUD split ($01CEF0).
const backdrop = 3 * 16

// drawMetatile draws metatile b at (ox,oy) using a 64-colour palette;
// colour 0 pixels get the backdrop colour, as on the Mega Drive.
func drawMetatile(img *image.RGBA, ox, oy int, blocks []byte, b int, tiles []byte, pal []color.RGBA) {
	if b*8+8 > len(blocks) {
		return
	}
	for q := 0; q < 4; q++ {
		w := be16s(blocks, b*8+2*q)
		t := int(w & 0x7FF)
		if t*32+32 > len(tiles) {
			continue
		}
		line := int(w>>13) & 3
		hf, vf := w&0x800 != 0, w&0x1000 != 0
		cx, cy := ox+(q&1)*8, oy+(q>>1)*8
		for y := 0; y < 8; y++ {
			for x := 0; x < 8; x++ {
				v := tiles[t*32+y*4+x/2]
				if x&1 == 0 {
					v >>= 4
				}
				v &= 15
				c := pal[line*16+int(v)]
				if v == 0 {
					c = pal[backdrop] // transparent: the backdrop shows through
				}
				px, py := x, y
				if hf {
					px = 7 - x
				}
				if vf {
					py = 7 - y
				}
				img.SetRGBA(cx+px, cy+py, c)
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Teams
// ---------------------------------------------------------------------------

type playerOut struct {
	Slot       int    `json:"slot"`
	Name       string `json:"name"`
	Attributes []int  `json:"attributes"` // record bytes 0-7 (object +$5A..+$61)
	Body       int    `json:"body"`       // record byte 8 (object +$62)
	Face       int    `json:"face"`       // record byte 9 (object +$63): head tiles (face-1)*$80
	Hair       int    `json:"hair"`       // record byte 10 (object +$64): hair tiles hair*$260
	Extra      int    `json:"extra"`      // record byte 11 (object +$65)
	Record     string `json:"record"`     // raw 12 bytes
}

func exportTeams(dir string) {
	type teamOut struct {
		Team      int         `json:"team"`
		Name      string      `json:"name"`
		Flag      string      `json:"flag,omitempty"`
		NamePlate string      `json:"name_plate,omitempty"`
		Ratings   []int       `json:"ratings"`
		KitClash  int         `json:"kit_clash"`
		Players   []playerOut `json:"players"`
	}
	var teams []teamOut
	for t := 0; t < numTeams; t++ {
		to := teamOut{Team: t, Name: teamNames[t], KitClash: int(be16(tblKitClash + uint32(2*t)))}
		if t < hudTeams {
			to.Flag = fmt.Sprintf("res://assets/iss/hud/flags/flag_%02d.png", t)
			to.NamePlate = fmt.Sprintf("res://assets/iss/hud/names/name_%02d.png", t)
		}
		for i := 0; i < 5; i++ {
			to.Ratings = append(to.Ratings, int(rom[tblTeamRatings+uint32(5*t+i)]))
		}
		names := be32(tblPlayerNames + uint32(4*t))
		recs := be32(tblPlayerData + uint32(4*t))
		for p := 0; p < playersPerTeam; p++ {
			nb := rom[names+uint32(8*p) : names+uint32(8*p+8)]
			name := make([]byte, 0, 8)
			for _, c := range nb {
				switch {
				case c == '@':
					name = append(name, ' ')
				case c == '`':
					name = append(name, '\'')
				default:
					name = append(name, c)
				}
			}
			r := rom[recs+uint32(12*p) : recs+uint32(12*p+12)]
			po := playerOut{Slot: p, Name: strings.TrimSpace(string(name)), Body: int(r[8]), Face: int(r[9]),
				Hair: int(r[10]), Extra: int(r[11]), Record: fmt.Sprintf("% X", r)}
			for i := 0; i < 8; i++ {
				po.Attributes = append(po.Attributes, int(r[i]))
			}
			to.Players = append(to.Players, po)
		}
		teams = append(teams, to)
	}
	writeJSON(filepath.Join(dir, "teams.json"), map[string]any{
		"description": "43 teams x 20 players. Names from $035916, records from $038140 (copied to player " +
			"object +$5A..+$65), 5 team ratings from $03AB82. Attribute meanings are not decoded yet. " +
			"Team names are graphics in the ROM (name_plate, res06 entry 0); the name strings here were read off them. " +
			"Team 42 is the practice side used by the training modes.",
		"teams": teams,
	})
	fmt.Printf("teams: %d x %d players\n", len(teams), playersPerTeam)
}
