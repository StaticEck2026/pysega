// Command generate builds the sega2asm segment map for
// International Superstar Soccer Deluxe (Europe) for the Sega Mega Drive.
//
//	go run ./example/issdeluxe/generate -rom <path to ROM> -o example/issdeluxe/issdeluxe.yaml
//
// It traces the 68000 code with the analysis package, carves the Factor 5
// resource archives entry by entry (typed as tiles / tilemaps / palettes)
// and describes the sound banks. The generated YAML is then refined by hand
// (names, descriptions) and fed to sega2asm.
package main

import (
	"bytes"
	"crypto/sha1"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"

	"sega2asm/analysis"
	"sega2asm/compress"
	"sega2asm/types"
)

const romSHA1 = "CCC60352B43F8C3D536267DD05A8F2C0F3B73DF6"

// ROM map (see README.md for the full description).
const (
	archiveStart = 0x05DB50 // main resource archive (87 groups)
	archiveEnd   = 0x144318
	bootStart    = 0x144318 // boot / logo module (Konami, Factor 5, ... screens)
	bootCodeEnd  = 0x14A150
	bootDataEnd  = 0x1613EC
	samplesStart = 0x1613EC // 8-bit PCM sample bank
	musicStart   = 0x1EB45C // music bank: 3 tables + 26 songs
	soundStart   = 0x1FD954 // 68000 sound driver (jump table API)
	z80Start     = 0x1FDC06 // Z80 PCM driver uploaded to $A00000
	z80End       = 0x1FDCFE
	romEnd       = 0x200000
)

var rom []byte

func be16(a uint32) uint32 { return uint32(rom[a])<<8 | uint32(rom[a+1]) }
func be32(a uint32) uint32 { return be16(a)<<16 | be16(a+2) }

func main() {
	romPath := flag.String("rom", "", "ROM file")
	out := flag.String("o", "issdeluxe.yaml", "output YAML")
	report := flag.String("report", "", "write the trace report here")
	flag.Parse()
	var err error
	if rom, err = os.ReadFile(*romPath); err != nil {
		fail(err)
	}
	if sum := fmt.Sprintf("%X", sha1.Sum(rom)); sum != romSHA1 {
		fail(fmt.Errorf("unexpected ROM SHA-1 %s (want %s)", sum, romSHA1))
	}

	res := analysis.Trace(rom, traceOptions())
	if *report != "" {
		f, err := os.Create(*report)
		if err != nil {
			fail(err)
		}
		res.WriteReport(f)
		f.Close()
	}

	segs := []types.Segment{{Name: "header", Type: "header", Start: 0, End: 0x200}}
	text := analysis.SegOptions{IsText: isText, TextEnd: 0xFF}

	o := text
	o.Prefix, o.DataPrefix, o.SubDir = "main", "main_data", "main"
	segs = append(segs, res.Segments(0x200, archiveStart, o)...)

	segs = append(segs, archiveSegments(archiveStart, archiveEnd, "res", "archive")...)

	o = text
	o.Prefix, o.DataPrefix, o.SubDir = "boot", "boot_data", "boot"
	segs = append(segs, res.Segments(bootStart, bootCodeEnd, o)...)
	segs = append(segs, bootDataSegments()...)

	segs = append(segs, soundDataSegments()...)

	o = text
	o.Prefix, o.DataPrefix, o.SubDir = "sound", "sound_data", "sound"
	for _, s := range res.Segments(soundStart, romEnd, o) {
		// The sound driver points a6 at its own RAM block.
		s.BaseRegs = map[string]types.HexInt{"a6": 0}
		segs = append(segs, splitZ80(s)...)
	}

	sort.SliceStable(segs, func(i, j int) bool { return segs[i].Start < segs[j].Start })
	check(segs)
	if err := os.WriteFile(*out, []byte(writeYAML(segs)), 0644); err != nil {
		fail(err)
	}
	c, d, u := res.Stats()
	fmt.Fprintf(os.Stderr, "segments=%d  code=%d data=%d unknown=%d functions=%d\n", len(segs), c, d, u, len(res.Entries))
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "generate:", err)
	os.Exit(1)
}

// traceOptions returns the tracer configuration: data-only regions are
// forced so pointer candidates never land in graphics or sound data.
func traceOptions() analysis.Options {
	return analysis.Options{
		Orphans: true,
		Data: []analysis.Range{
			{Start: archiveStart, End: archiveEnd},
			{Start: bootCodeEnd, End: soundStart},
			{Start: z80Start, End: z80End},
		},
	}
}

// isText reports whether b is part of the game's text encoding: ASCII with
// '@' ($40) used as the space character.
func isText(b byte) bool { return b >= 0x20 && b <= 0x5F }

// ---------------------------------------------------------------------------
// Resource archives
// ---------------------------------------------------------------------------

// stream decodes the length of a Factor 5 "P1"/"P2"/"P3" packed entry and
// returns (compressed length, decompressed data).
func stream(a uint32) (uint32, []byte, bool) {
	if rom[a] != 'P' || (rom[a+1] != '1' && rom[a+1] != '2' && rom[a+1] != '3') {
		return 0, nil, false
	}
	size := uint32(rom[a+2]) | uint32(rom[a+3])<<8
	if rom[a+1] == '3' {
		return 4 + size, rom[a+4 : a+4+size], true
	}
	// Decompress while measuring the consumed input.
	p := a + 4
	var outLen uint32
	for outLen < size {
		b := rom[p]
		p++
		if b&0x80 != 0 {
			if rom[a+1] == '1' {
				outLen += uint32(b>>3&0xF) + 3
				p++
			} else {
				outLen += uint32(b&0x7F) + 4
				p += 2
			}
		} else {
			n := uint32(b&0x7F) + 1
			outLen += n
			p += n
		}
	}
	dec, err := compress.DecompressLZFactor5(rom[a:p])
	if err != nil {
		return 0, nil, false
	}
	return p - a, dec, true
}

// classify guesses the content of a decoded archive entry.
func classify(data []byte) string {
	n := len(data)
	if n >= 32 && n <= 256 && n%32 == 0 {
		pal := true
		for i := 0; i+1 < n; i += 2 {
			if (uint32(data[i])<<8|uint32(data[i+1]))&0xF111 != 0 {
				pal = false
				break
			}
		}
		if pal && n != 32 {
			return "palette"
		}
	}
	if n == 1024 || n == 2048 || n == 3584 || n == 4096 || n == 8192 {
		ok := true
		hi := map[uint32]bool{}
		for i := 0; i+1 < n; i += 2 {
			w := uint32(data[i])<<8 | uint32(data[i+1])
			if w&0x7FF >= 0x600 {
				ok = false
				break
			}
			hi[w>>11] = true
		}
		if ok && len(hi) <= 8 {
			return "tilemap"
		}
	}
	if n%32 == 0 && n > 0 {
		return "tiles"
	}
	return "data"
}

type group struct {
	addr, end uint32
	long      bool
	entries   []uint32
}

// parseGroup reads a group's offset table. Groups whose first word is zero
// use long offsets, all others word offsets (both relative to the group).
func parseGroup(g, end uint32) group {
	gr := group{addr: g, end: end}
	if be16(g) == 0 {
		gr.long = true
		n := be32(g) / 4
		for i := uint32(0); i < n; i++ {
			gr.entries = append(gr.entries, g+be32(g+4*i))
		}
	} else {
		n := be16(g) / 2
		for i := uint32(0); i < n; i++ {
			gr.entries = append(gr.entries, g+be16(g+2*i))
		}
	}
	return gr
}

// groupSegments carves one archive group: its offset table, every entry
// (typed by content) and any padding.
func groupSegments(gr group, name, sub string, palettes map[uint32]string) []types.Segment {
	var segs []types.Segment
	tblSize := uint32(len(gr.entries)) * 2
	format := "word"
	if gr.long {
		tblSize *= 2
		format = "long"
	}
	segs = append(segs, types.Segment{
		Name: name, Type: "table", Format: format, Relative: true,
		Start: types.HexInt(gr.addr), End: types.HexInt(gr.addr + tblSize), SubDir: sub,
	})
	uniq := map[uint32]int{}
	var addrs []uint32
	for i, e := range gr.entries {
		if _, ok := uniq[e]; !ok {
			uniq[e] = i
			addrs = append(addrs, e)
		}
	}
	sort.Slice(addrs, func(i, j int) bool { return addrs[i] < addrs[j] })
	cur := gr.addr + tblSize
	pad := func(a, b uint32) {
		if b > a {
			segs = append(segs, types.Segment{
				Name: fmt.Sprintf("%s_pad_%06X", name, a), Type: "data", Format: "byte",
				Start: types.HexInt(a), End: types.HexInt(b), SubDir: sub,
			})
		}
	}
	for k, e := range addrs {
		next := gr.end
		if k+1 < len(addrs) {
			next = addrs[k+1]
		}
		if e >= gr.end {
			continue // empty slot pointing at the group end
		}
		pad(cur, e)
		idx := uniq[e]
		seg := types.Segment{Start: types.HexInt(e), SubDir: sub}
		length, data, packed := stream(e)
		if packed {
			seg.Compression = "lzfactor5"
		} else {
			length, data = next-e, rom[e:next]
		}
		kind := classify(data)
		if len(data) == 2 && be16(e) == 0xFFFF {
			kind = "empty"
		}
		seg.End = types.HexInt(e + length)
		seg.Name = fmt.Sprintf("%s_%02d_%s", name, idx, kind)
		switch kind {
		case "tiles":
			seg.Type = "gfx"
			if packed {
				seg.Type = "gfxcomp"
			}
			if p, ok := palettes[gr.addr]; ok {
				seg.Palette = p
			}
		case "tilemap":
			seg.Type = "tilemap"
			seg.Width = 64
			if len(data) == 1024 || len(data) == 2048 {
				seg.Width = 32
			}
		case "palette":
			seg.Type = "palette"
		case "empty":
			seg.Type = "data"
			seg.Format = "word"
		default:
			seg.Type = "bin"
		}
		segs = append(segs, seg)
		cur = e + length
	}
	pad(cur, gr.end)
	return segs
}

// archiveSegments carves the main resource archive: a directory of long
// offsets to 87 groups, terminated by $FFFF.
func archiveSegments(start, end uint32, prefix, sub string) []types.Segment {
	n := be32(start) / 4
	var groups []uint32
	for i := uint32(0); i < n; i++ {
		groups = append(groups, start+be32(start+4*i))
	}
	dirEnd := start + n*4
	segs := []types.Segment{
		{Name: prefix + "_directory", Type: "table", Format: "long", Relative: true,
			Start: types.HexInt(start), End: types.HexInt(dirEnd), SubDir: sub,
			Description: "Resource archive directory: offsets of the 87 resource groups"},
		{Name: prefix + "_directory_end", Type: "data", Format: "word",
			Start: types.HexInt(dirEnd), End: types.HexInt(groups[0]), SubDir: sub},
	}
	palettes := map[uint32]string{}
	for i, g := range groups {
		ge := end
		if i+1 < len(groups) {
			ge = groups[i+1]
		}
		gr := parseGroup(g, ge)
		// Colour tile sheets with the group's own palette when it has one.
		for j, e := range gr.entries {
			if l, d, ok := stream(e); ok && l > 0 && classify(d) == "palette" {
				palettes[g] = fmt.Sprintf("%s%02d_%02d_palette", prefix, i, j)
				break
			}
		}
		segs = append(segs, groupSegments(gr, fmt.Sprintf("%s%02d", prefix, i), sub, palettes)...)
	}
	return segs
}

// bootDataSegments describes the boot module's data: two palettes followed
// by five word-offset resource groups.
func bootDataSegments() []types.Segment {
	segs := []types.Segment{
		{Name: "boot_palette_a", Type: "palette", Start: 0x14A150, End: 0x14A1B0, SubDir: "boot"},
		{Name: "boot_palette_b", Type: "palette", Start: 0x14A1B0, End: 0x14A1F0, SubDir: "boot"},
	}
	groups := []uint32{0x14A1F0, 0x156CE6, 0x15B298, 0x16049A, 0x160F38, bootDataEnd}
	for i := 0; i+1 < len(groups); i++ {
		gr := parseGroup(groups[i], groups[i+1])
		segs = append(segs, groupSegments(gr, fmt.Sprintf("boot_res%d", i), "boot", map[uint32]string{})...)
	}
	return segs
}

// soundDataSegments describes the PCM sample bank and the music bank.
func soundDataSegments() []types.Segment {
	segs := []types.Segment{
		{Name: "pcm_bank", Type: "pcm", SampleRate: 8000, Start: samplesStart, End: musicStart, SubDir: "sound",
			Description: "8-bit PCM sample bank (addressed as offsets from its start by the sound driver)"},
	}
	// Music bank: 29 long offsets relative to the bank start.
	n := be32(musicStart+4*3) / 4 // first song offset marks the end of the table
	offs := map[uint32]bool{}
	for i := uint32(0); i < n; i++ {
		offs[musicStart+be32(musicStart+4*i)] = true
	}
	segs = append(segs, types.Segment{
		Name: "music_bank", Type: "table", Format: "long", Relative: true,
		Start: musicStart, End: types.HexInt(musicStart + n*4), SubDir: "sound",
		Description: "Music bank: 3 instrument/sample tables followed by 26 songs",
	})
	var addrs []uint32
	for a := range offs {
		addrs = append(addrs, a)
	}
	sort.Slice(addrs, func(i, j int) bool { return addrs[i] < addrs[j] })
	cur := uint32(musicStart + n*4)
	for i, a := range addrs {
		if a > cur {
			segs = append(segs, types.Segment{Name: fmt.Sprintf("music_pad_%06X", cur), Type: "bin",
				Start: types.HexInt(cur), End: types.HexInt(a), SubDir: "sound"})
		}
		end := uint32(soundStart)
		if i+1 < len(addrs) {
			end = addrs[i+1]
		}
		name := fmt.Sprintf("song_%06X", a)
		if i >= len(addrs)-3 {
			name = fmt.Sprintf("music_table%d", i-(len(addrs)-3))
		}
		segs = append(segs, types.Segment{Name: name, Type: "bin", Start: types.HexInt(a), End: types.HexInt(end), SubDir: "sound"})
		cur = end
	}
	return segs
}

// splitZ80 cuts the embedded Z80 driver out of a sound segment.
func splitZ80(s types.Segment) []types.Segment {
	st, en := uint32(s.Start), uint32(s.End)
	if !(st <= z80Start && en >= z80End) {
		return []types.Segment{s}
	}
	var out []types.Segment
	if st < z80Start {
		a := s
		a.End = z80Start
		a.Hints = clipHints(s.Hints, st, st, z80Start)
		out = append(out, a)
	}
	out = append(out, types.Segment{Name: "z80_driver", Type: "bin", Start: z80Start, End: z80End, SubDir: "sound",
		Description: "Z80 PCM driver, copied to Z80 RAM $0000 by the sound driver"})
	if en > z80End {
		b := s
		b.Name = fmt.Sprintf("%s_%06X", strings.SplitN(s.Name, "_", 2)[0], z80End)
		b.Start = z80End
		b.Hints = clipHints(s.Hints, st, z80End, en)
		out = append(out, b)
	}
	return out
}

func clipHints(hs []types.Hint, segStart, a, b uint32) []types.Hint {
	var out []types.Hint
	for _, h := range hs {
		ha := segStart + h.Offset
		he := ha + uint32(h.Length)
		if ha >= a && he <= b {
			h.Offset = ha - a
			out = append(out, h)
		}
	}
	return out
}

// check verifies that segments tile the ROM exactly.
func check(segs []types.Segment) {
	cur := uint32(0)
	for _, s := range segs {
		if uint32(s.Start) != cur {
			fail(fmt.Errorf("segment %s starts at $%06X, expected $%06X", s.Name, uint32(s.Start), cur))
		}
		cur = uint32(s.End)
	}
	if cur != romEnd {
		fail(fmt.Errorf("segments end at $%06X", cur))
	}
}

// ---------------------------------------------------------------------------
// YAML output
// ---------------------------------------------------------------------------

func writeYAML(segs []types.Segment) string {
	var b bytes.Buffer
	b.WriteString(yamlHeader)
	for _, s := range segs {
		fmt.Fprintf(&b, "\n  - name: %s\n    type: %s\n    start: 0x%06X\n    end:   0x%06X\n", s.Name, s.Type, uint32(s.Start), uint32(s.End))
		if s.SubDir != "" {
			fmt.Fprintf(&b, "    subdir: %s\n", s.SubDir)
		}
		if s.Compression != "" && s.Compression != "none" {
			fmt.Fprintf(&b, "    compression: %s\n", s.Compression)
		}
		if s.Format != "" {
			fmt.Fprintf(&b, "    format: %s\n", s.Format)
		}
		if s.Relative {
			b.WriteString("    relative: true\n")
		}
		if s.Width != 0 {
			fmt.Fprintf(&b, "    width: %d\n", s.Width)
		}
		if s.Palette != "" {
			fmt.Fprintf(&b, "    palette: %s\n", s.Palette)
		}
		for _, k := range []string{"a0", "a1", "a2", "a3", "a4", "a5", "a6"} {
			if v, ok := s.BaseRegs[k]; ok {
				fmt.Fprintf(&b, "    base_regs: {%s: 0x%X}\n", k, uint32(v))
			}
		}
		if s.SampleRate != 0 {
			fmt.Fprintf(&b, "    sample_rate: %d\n", s.SampleRate)
		}
		if s.Description != "" {
			fmt.Fprintf(&b, "    description: %q\n", s.Description)
		}
		if len(s.Hints) > 0 {
			b.WriteString("    hints:\n")
			for _, h := range s.Hints {
				fmt.Fprintf(&b, "      - {offset: 0x%04X, type: %s, length: %d", h.Offset, h.Type, h.Length)
				if h.Base != 0 {
					fmt.Fprintf(&b, ", base: 0x%06X", uint32(h.Base))
				}
				b.WriteString("}\n")
			}
		}
	}
	return b.String()
}

const yamlHeader = `name: issdeluxe
# International Superstar Soccer Deluxe (Europe) — Sega Mega Drive
# (C) 1996 Konami, developed by Factor 5. Serial GM T-95196-50, 16 Mbit.
#
# Generated by example/issdeluxe/generate, then refined by hand.
# See example/issdeluxe/README.md for the ROM map and how to build.
sha1: "CCC60352B43F8C3D536267DD05A8F2C0F3B73DF6"

options:
  platform: genesis
  region: pal
  basename: issdeluxe
  base_path: ./out
  target_path: "./International Superstar Soccer Deluxe (Europe).md"
  asm_path: asm
  asset_path: assets
  build_path: build
  symbols_path: ./issdeluxe_symbols.txt
  charmap_path: ./issdeluxe.tbl
  header_output: true
  heuristics: false          # segment map comes from a control-flow trace
  base_regs:
    a6: 0xFF0000             # the game keeps its globals block in a6

segments:
`
