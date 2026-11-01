#!/bin/sh
# lx/build.sh - Compila la BIOS del Aleste LX (submodulo aleste-xi-bios de hww,
# sin tocar) con los parches de lx/patches y monta lx/build/LX.ROM (64 KB).
#
# Necesita z88dk (zcc en el PATH). Sin instalarlo, con Docker:
#   docker run --rm -v "$PWD":/src -w /src/lx z88dk/z88dk sh build.sh
#
# Despues, el ALESTE.ROM del core con el modo LX:
#   python3 tools/make_rom.py AL512.BIN --lx lx/build/LX.ROM
set -e
cd "$(dirname "$0")"
rm -rf build/src
mkdir -p build
cp -r aleste-xi-bios build/src
rm -rf build/src/.git build/src/build build/src/output
for p in patches/*.patch; do
    echo "== $p"
    (cd build/src && patch -p1 -s < "../../$p")
done
cd build/src
mkdir -p build
zcc +z80 -vn -O3 --no-crt -m -Iinclude -I. -s -clib=sdcc_iy -o build/aleste \
    asm/sections.asm asm/crt0_aleste.asm fonts/font_win1252.asm \
    bios/errors.asm bios/undefined_method.asm \
    drivers/mmu/mmu.asm drivers/mmu/mmu_mem.asm drivers/crtc/crtc.asm \
    drivers/palette/palette.asm drivers/palette/palette_12b.asm \
    drivers/vbuf/vbuf_16k1b.asm drivers/vbuf/vbuf.asm \
    drivers/audio/aduio_ay8910.asm drivers/audio/audio.asm \
    src/drivers/mmu.c src/drivers/mmu_mem.c src/drivers/crtc.c src/drivers/palette.c \
    src/drivers/vbuf.c src/drivers/audio.c main.c
# LX.ROM: 64 KB con cada seccion en su direccion (sin Python: vale en la
# imagen de Docker de z88dk)
head -c 65536 /dev/zero > build/LX.ROM
put() { dd if="build/aleste_$1.bin" of=build/LX.ROM bs=1 seek=$(($2)) conv=notrunc 2>/dev/null; }
put code_crt_start 0x0000
put code_compiler  0x0200
put DRV_CODE       0xC000
put FONT_DATA      0xE000
put DRV_DATA       0xF000
put DRV_VTABLE     0xFD00
[ "$(wc -c < build/LX.ROM)" -eq 65536 ] || { echo "LX.ROM no mide 64 KB: alguna seccion se sale"; exit 1; }
cp build/LX.ROM ../LX.ROM
echo "lx/build/LX.ROM"
