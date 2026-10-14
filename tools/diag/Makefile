# ROM de diagnostico de la fase 2. Hace falta pasmo (apt install pasmo).
#   make   -> DIAG.ROM (copiar a la SD con ese nombre)

DIAG.ROM: diag.asm font.inc
	pasmo --bin diag.asm DIAG.ROM

font.inc: ../gen_font.py
	python3 ../gen_font.py

clean:
	rm -f DIAG.ROM

.PHONY: clean
