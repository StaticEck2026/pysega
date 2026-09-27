package main

import (
	"fmt"
	"image"
	"image/color"
	"os"
	"path/filepath"

	"sega2asm/types"
)

// The match HUD lives in the window plane: res16 entry 3 is its 32x32 map
// over the overlay tiles (res16 entry 5), palette line 2 (colours 0-7 the
// officials' kit, 8-15 res16 entry 9). match_init_hud streams the team flags
// and names into overlay tiles 72-93; the radar is a 10x7-tile bitmap in
// tiles 2-71 redrawn by the hud_update chain; the score and clock are digit
// tiles written into the map.
const (
	entHUDMap      = 3
	entHUDPalette  = 9
	entRadarTiles  = 20      // res04: clean radar bitmap, 10 columns of 7 tiles
	grpTeamGfx     = 6       // res06
	entTeamNames   = 0       // 5 tiles per team
	entTeamFlags   = 2       // 6 tiles per team (3 x 2 cells, column-major)
	tblDigits      = 0x1CD00 // 10 digits x (top, bottom) tile words
	tblTimeUp      = 0x1CD50 // 4 cells shown instead of the clock at time up
	tblRadarMaps   = 0x1BBF0 // per stadium: column table, row table
	tblRadarDots   = 0x1BB90 // 6 dot patterns x 16 bytes
	radarFirstTile = 2
	hudTeams       = 42
)

// hudLine2 returns palette line 2 as used in a match.
func hudLine2() []uint16 {
	line := append([]uint16(nil), officialKit(0)...)
	pal := unpack(entry(grpOverlay, entHUDPalette))
	for i := 0; i+1 < len(pal) && len(line) < 16; i += 2 {
		line = append(line, uint16(pal[i])<<8|uint16(pal[i+1]))
	}
	return line
}

// cellsImage draws a w x h block of 8x8 tiles given as nametable words
// (tile relative to tiles) into a CRAM-index image.
func cellsImage(words []uint16, w, h int, tiles []byte) *image.Gray {
	m := make([]byte, 2*len(words))
	for i, v := range words {
		m[2*i], m[2*i+1] = byte(v>>8), byte(v)
	}
	return renderPlane(m, tiles, w, h)
}

func exportHUD(dir string) {
	must(os.MkdirAll(filepath.Join(dir, "flags"), 0755))
	must(os.MkdirAll(filepath.Join(dir, "names"), 0755))
	tiles := append([]byte(nil), unpack(entry(grpOverlay, entOverlayTiles))...)
	radar := unpack(entry(grpMisc, entRadarTiles))
	copy(tiles[radarFirstTile*32:], radar)
	window := unpack(entry(grpOverlay, entHUDMap))

	// Palette texture: line 2 = HUD, line 3 = stadium 0 fine (unused here).
	pimg := image.NewRGBA(image.Rect(0, 0, 16, 4))
	setLine(pimg, 2, hudLine2())
	setLine(pimg, 3, stadiumLine(0, 1))
	must(types.WritePNG(filepath.Join(dir, "hud.pal.png"), pimg))

	must(types.WritePNG(filepath.Join(dir, "window.png"), renderPlane(window, tiles, 32, 32)))
	idx, _ := types.TileSheet(tiles, 16, types.GrayPalette(16), false)
	must(types.WritePNG(filepath.Join(dir, "overlay_tiles.png"), grayIndex(idx)))
	var words []int
	for i := 0; i+1 < len(window); i += 2 {
		words = append(words, int(be16s(window, i)))
	}

	// Team flags (3x2 cells) and names (5x1).
	flags := unpack(entry(grpTeamGfx, entTeamFlags))
	names := unpack(entry(grpTeamGfx, entTeamNames))
	for t := 0; t < hudTeams; t++ {
		fw := make([]uint16, 6)
		for c := 0; c < 3; c++ {
			for r := 0; r < 2; r++ {
				fw[r*3+c] = uint16(2<<13 | (c*2 + r))
			}
		}
		must(types.WritePNG(filepath.Join(dir, "flags", fmt.Sprintf("flag_%02d.png", t)),
			cellsImage(fw, 3, 2, flags[t*6*32:t*6*32+6*32])))
		nw := make([]uint16, 5)
		for c := range nw {
			nw[c] = uint16(2<<13 | c)
		}
		must(types.WritePNG(filepath.Join(dir, "names", fmt.Sprintf("name_%02d.png", t)),
			cellsImage(nw, 5, 1, names[t*5*32:t*5*32+5*32])))
	}

	// Digits 0-9 (8x16 each), and the time-up cells.
	var dw []uint16
	for r := 0; r < 2; r++ {
		for d := uint32(0); d < 10; d++ {
			dw = append(dw, uint16(be16(tblDigits+4*d+2*uint32(r)))|2<<13)
		}
	}
	must(types.WritePNG(filepath.Join(dir, "digits.png"), cellsImage(dw, 10, 2, tiles)))
	var tw []uint16
	for r := 0; r < 2; r++ {
		for d := uint32(0); d < 4; d++ {
			tw = append(tw, uint16(be16(tblTimeUp+4*d+2*uint32(r)))|2<<13)
		}
	}
	must(types.WritePNG(filepath.Join(dir, "time_up.png"), cellsImage(tw, 4, 2, tiles)))

	// Radar: background bitmap and the per-stadium pitch -> radar mapping.
	rimg := image.NewGray(image.Rect(0, 0, 80, 56))
	for col := 0; col < 10; col++ {
		for y := 0; y < 56; y++ {
			for x := 0; x < 8; x++ {
				b := radar[col*0xE0+y*4+x/2]
				v := b >> 4
				if x&1 == 1 {
					v = b & 15
				}
				if v != 0 {
					rimg.SetGray(col*8+x, y, color.Gray{Y: 32 + v})
				}
			}
		}
	}
	must(types.WritePNG(filepath.Join(dir, "radar.png"), rimg))
	type radarMap struct {
		Stadium int   `json:"stadium"`
		X       []int `json:"x"` // radar pixel X for (x - pitch_left) / 16
		Y       []int `json:"y"` // radar pixel Y for (y - pitch_top) / 16
	}
	var maps []radarMap
	for st := 0; st < numStadiums; st++ {
		ct, rt := be32(tblRadarMaps+uint32(8*st)), be32(tblRadarMaps+uint32(8*st)+4)
		b := uint32(tblPitchBounds + 8*st)
		w, h := (s16(b+2)-s16(b))/16, (s16(b+6)-s16(b+4))/16
		rm := radarMap{Stadium: st}
		for i := 0; i < w; i++ {
			rm.X = append(rm.X, int(be16(ct+uint32(4*i)+2)))
		}
		for j := 0; j < h; j++ {
			rm.Y = append(rm.Y, int(be16(rt+uint32(2*j)))/4)
		}
		maps = append(maps, rm)
	}
	var dots [][]int
	for p := uint32(0); p < 6; p++ {
		var d []int
		for i := uint32(0); i < 16; i++ {
			d = append(d, int(rom[tblRadarDots+16*p+i]))
		}
		dots = append(dots, d)
	}
	writeJSON(filepath.Join(dir, "hud.json"), map[string]any{
		"description": "Match HUD (window plane, 32x32 cells, palette line 2 = hud.pal.png row 2). Images are CRAM-index. " +
			"Cells are (column, row) of window.png; each HUD item is drawn over it at the given cells.",
		"window_words": words,
		"items": map[string]any{
			"home_flag":  map[string]any{"cells": []int{2, 1}, "size": []int{3, 2}, "images": "flags/flag_NN.png (team)"},
			"away_flag":  map[string]any{"cells": []int{12, 1}, "size": []int{3, 2}},
			"home_name":  map[string]any{"cells": []int{1, 3}, "size": []int{5, 1}, "images": "names/name_NN.png"},
			"away_name":  map[string]any{"cells": []int{11, 3}, "size": []int{5, 1}},
			"home_score": map[string]any{"cells": []int{6, 1}, "digits": 2, "note": "tens digit blank when 0"},
			"away_score": map[string]any{"cells": []int{9, 1}, "digits": 2},
			"clock":      map[string]any{"cells": []int{27, 1}, "format": "M:SS, minutes at column 27, colon at 28, seconds at 29-30; time_up.png at 27-30 when the clock is 0"},
			"half":       map[string]any{"cells": []int{25, 1}, "tiles": "$6C first half, $64 second half"},
			"radar":      map[string]any{"cells": []int{11, 20}, "size_px": []int{80, 56}},
			"banner":     map[string]any{"cells": []int{0, 24}, "size": []int{32, 2}, "note": "banner_draw text (THROW IN, ...)"},
		},
		"digits": "digits.png: 10 digits of 8x16 pixels",
		"radar": map[string]any{
			"background": "radar.png (index 32 + colour, line 2)",
			"mapping":    maps,
			"dots": map[string]any{
				"order":       []string{"home", "away", "flagged player", "controlled home", "controlled away", "ball"},
				"patterns":    dots,
				"format":      "raw patterns plotted by sub_01BAD0: 2x2 dots for players (home colour $D, away $A, flagged $C), 4x4 markers with a colour $F outline for the controlled players (home 9, away 8) and the ball (1)",
				"update_rate": "one step of the hud_update chain per frame (clear, home, away, controlled, ball, DMA)",
			},
		},
	})
	fmt.Printf("hud: window, %d flags and names, radar maps for %d stadiums\n", hudTeams, len(maps))
}
