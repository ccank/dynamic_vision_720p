#==============================================================================
# File        : rebuild_project.tcl
# Project     : dynamic_vision_720p
# Device      : xc7k325tffg900-2 (Kintex-7)
# Description :
#   One-click, self-contained project rebuild script. It assembles the 31 RTL
#   sources, the three constraint files and every IP (five packaged .xcix plus
#   the directory-style MIG), sets the top module and generates IP products.
#
#   The script ONLY creates and configures the project. It never launches
#   synthesis, implementation or bitstream generation; run those yourself so
#   every compile stays under your control.
#
# Usage :
#   Batch:  vivado -mode batch -source rebuild_project.tcl
#   GUI:    in the Tcl console,  cd to this build folder then
#           source rebuild_project.tcl
#
#   After the project opens, run synthesis -> implementation -> bitstream, or:
#   launch_runs synth_1 -jobs 4
#   wait_on_run synth_1
#   launch_runs impl_1 -to_step write_bitstream -jobs 4
#==============================================================================

# Resolve paths relative to this script so the package is location independent.
set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]
set proj_name  dynamic_vision_720p
set part       xc7k325tffg900-2
set proj_dir   [file join $script_dir vivado_project]

file mkdir $proj_dir
create_project -force $proj_name $proj_dir -part $part
set_property target_language    Verilog [current_project]
set_property simulator_language Verilog [current_project]

#------------------------------------------------------------------------------
# RTL sources: 31 Verilog files across two directory depths under rtl/.
# rtl/*/*.v      -> top/camera/vip/ddr3/hdmi/algorithm and touch_lcd wrappers
# rtl/*/*/*.v    -> lcd_rgb_char and touch leaf modules
#------------------------------------------------------------------------------
set rtl_files [concat \
    [glob -nocomplain [file join $root rtl */*.v]] \
    [glob -nocomplain [file join $root rtl */*/*.v]]]
add_files -norecurse [lsort -unique $rtl_files]

#------------------------------------------------------------------------------
# Constraints. Order matters: pin.xdc creates the clocks, timing_exceptions.xdc
# adds the asynchronous clock groups, lcd_touch.xdc binds the panel/touch pins.
#------------------------------------------------------------------------------
add_files -fileset constrs_1 [list \
    [file join $root constraints pin.xdc] \
    [file join $root constraints timing_exceptions.xdc] \
    [file join $root constraints lcd_touch.xdc]]

#------------------------------------------------------------------------------
# Packaged, self-contained IP cores (.xcix containers).
#------------------------------------------------------------------------------
set xcix_files [glob -nocomplain [file join $root ip *.xcix]]
if {[llength $xcix_files] > 0} {
    add_files -norecurse $xcix_files
}

#------------------------------------------------------------------------------
# MIG 7-series DDR3 memory controller (directory-style IP). The mig_a/mig_b.prj
# files sit next to the .xci and are referenced automatically.
#------------------------------------------------------------------------------
add_files -norecurse [file join $root ip mig_7series_0 mig_7series_0.xci]

# Generate the output products (synthesis wrappers, targets, etc.) for all IP.
generate_target all [get_ips]

#------------------------------------------------------------------------------
# Top module and automatic compile order.
#------------------------------------------------------------------------------
set_property top dynamic_vision_720p [current_fileset]
update_compile_order -fileset sources_1

puts "===================================================================="
puts "Project '$proj_name' created at: $proj_dir"
puts "Sources / constraints / IP assembled. Open the project and run synthesis."
puts "===================================================================="
