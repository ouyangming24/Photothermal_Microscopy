# =============================================================================
# regenerate_dds_phase.tcl
# After Phase_offset -> Programmable, regenerate both DDS IPs (config bus 96-bit).
#
# Usage in Vivado Tcl Console (project already open):
#   source {..../scripts/regenerate_dds_phase.tcl}
# =============================================================================

puts "\[DDS-PHASE\] Upgrading/regenerating dds_compiler_0 / dds_compiler_1 ..."

set ips [get_ips -quiet dds_compiler_0 dds_compiler_1]
if {[llength $ips] == 0} {
    # try by file
    set xci0 [get_files -quiet */dds_compiler_0.xci]
    set xci1 [get_files -quiet */dds_compiler_1.xci]
    if {$xci0 ne ""} { read_ip $xci0 }
    if {$xci1 ne ""} { read_ip $xci1 }
    set ips [get_ips -quiet dds_compiler_0 dds_compiler_1]
}

foreach ip $ips {
    puts "\[DDS-PHASE\] IP: $ip"
    # Ensure programmable phase offset
    catch {set_property CONFIG.Phase_offset Programmable [get_ips $ip]}
    catch {upgrade_ip [get_ips $ip]}
    generate_target all [get_files [get_property IP_FILE [get_ips $ip]]]
    catch {export_ip_user_files -of_objects [get_ips $ip] -no_script -sync -force -quiet}
}

update_compile_order -fileset sources_1
puts "\[DDS-PHASE\] Done. Re-run Synthesis. CONFIG TDATA should be 96-bit {POFF,PINC}."
