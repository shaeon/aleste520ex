# Se ejecuta antes de compilar (PRE_FLOW_SCRIPT_FILE en el .qsf):
#  1. genera build_id.v con fecha y version (de ../core.definition)
#  2. copia al proyecto las tablas .mem de la paleta del Aleste LX: Quartus
#     busca los $readmemh relativos a la carpeta del proyecto, no a la del
#     fuente, y sin ellas la paleta sale a cero.

proc generateBuildID_Verilog {} {
	set buildDate [ clock format [ clock seconds ] -format %y%m%d ]
	set buildTime [ clock format [ clock seconds ] -format %H%M%S ]

	set version {}
	if { ![catch {open "../core.definition" r} coreDefinitionFile] } {
		while {[gets $coreDefinitionFile data] >= 0} {
			if { [regexp {VERSION=(.*)} "$data" all version] == 1 } {
				break
			}
		}
		close $coreDefinitionFile
	}

	set outputFile [open "build_id.v" "w"]
	puts $outputFile "`define BUILD_DATE \"$buildDate\""
	puts $outputFile "`define BUILD_TIME \"$buildTime\""
	puts $outputFile "`define BUILD_VERSION \"mist-$version\""
	close $outputFile

	post_message "Generated build identification Verilog module: [pwd]/build_id.v"
	post_message "Version: $version  Date: $buildDate $buildTime"
}

proc copyPaletteTables {} {
	foreach f [concat [glob -nocomplain ../aleste-lx/src/components/video/palette/*.mem] [glob -nocomplain ../rtl/*.mem]] {
		file copy -force $f .
		post_message "Copiado [file tail $f]"
	}
}

generateBuildID_Verilog
copyPaletteTables
