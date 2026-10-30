# =============================================================================
# recreate_project.tcl
# 当 .xpr / cache 损坏时，从源文件干净重建工程（再跑 IP upgrade/generate）
#
# 用法：
#   vivado -mode batch -source recreate_project.tcl
#   vivado -mode batch -source recreate_project.tcl -tclargs -out E:/tmp/guang_new
# =============================================================================

proc guang_puts {msg} { puts "\[GUANG-RECREATE\] $msg" }

proc guang_script_dir {} {
    set s [info script]
    if {$s eq ""} { return [pwd] }
    return [file normalize [file dirname $s]]
}

proc guang_get_arg_value {name} {
    global argv
    if {![info exists argv]} { return "" }
    set idx [lsearch -exact $argv $name]
    if {$idx < 0} { return "" }
    set val_idx [expr {$idx + 1}]
    if {$val_idx >= [llength $argv]} { return "" }
    return [lindex $argv $val_idx]
}

set src_root [file normalize [file join [guang_script_dir] ..]]
set out_dir  [guang_get_arg_value "-out"]
if {$out_dir eq ""} {
    set out_dir [file join $src_root "_recreated"]
}
set out_dir [file normalize $out_dir]
set part    "xc7z020clg484-2"

guang_puts "源工程目录: $src_root"
guang_puts "新建工程到: $out_dir"
guang_puts "Part: $part"

file mkdir $out_dir
cd $out_dir

if {[current_project -quiet] ne ""} {
    close_project
}

# 若已存在同名工程，先关掉再覆盖创建
set proj_name "guang"
set xpr_path [file join $out_dir ${proj_name}.xpr]
if {[file exists $xpr_path]} {
    guang_puts "已存在 $xpr_path，将覆盖创建"
    file delete -force $xpr_path
    catch {file delete -force [file join $out_dir "${proj_name}.srcs"]}
    catch {file delete -force [file join $out_dir "${proj_name}.cache"]}
    catch {file delete -force [file join $out_dir "${proj_name}.runs"]}
    catch {file delete -force [file join $out_dir "${proj_name}.gen"]}
    catch {file delete -force [file join $out_dir "${proj_name}.ip_user_files"]}
    catch {file delete -force [file join $out_dir "${proj_name}.hw"]}
    catch {file delete -force [file join $out_dir "${proj_name}.sim"]}
}

create_project $proj_name $out_dir -part $part -force
set_property target_language Verilog [current_project]

# ---- 添加 HDL ----
set hdl_dir [file join $src_root guang.srcs sources_1 new]
set hdl_files [glob -nocomplain [file join $hdl_dir *.v]]
guang_puts "添加 HDL: $hdl_files"
add_files -norecurse $hdl_files

# ---- 添加约束 ----
set xdc [file join $src_root guang.srcs constrs_1 new pin.xdc]
if {[file exists $xdc]} {
    guang_puts "添加约束: $xdc"
    add_files -fileset constrs_1 -norecurse $xdc
}

# ---- 导入 IP（保留原 .xci 配置）----
set ip_root [file join $src_root guang.srcs sources_1 ip]
set xci_list [list]
foreach ip_name {ila_0 dds_compiler_0 dds_compiler_1 mult_gen_0 div_gen_0 clk_wiz_0} {
    set xci [file join $ip_root $ip_name ${ip_name}.xci]
    if {[file exists $xci]} {
        lappend xci_list $xci
    } else {
        guang_puts "WARNING: 缺少 IP $xci"
    }
}
if {[llength $xci_list] > 0} {
    guang_puts "导入 IP: $xci_list"
    import_ip -files $xci_list
}

# ---- 可选导入 BD（未接入顶层，默认导入）----
set bd [file join $src_root guang.srcs sources_1 bd design_1 design_1.bd]
if {[file exists $bd]} {
    guang_puts "导入 BD: $bd"
    catch {add_files -norecurse $bd}
    # BD 未作为顶层，允许保留但禁用自动综合顶依赖
}

set_property top guang [current_fileset]
update_compile_order -fileset sources_1

# ---- 升级 + 生成 ----
set ips [get_ips -quiet]
guang_puts "upgrade_ip: $ips"
catch {upgrade_ip $ips -log ip_upgrade.log}

foreach f [get_files -quiet *.xci] {
    guang_puts "generate_target: $f"
    catch {generate_target all [get_files $f]}
    catch {export_ip_user_files -of_objects [get_files $f] -no_script -sync -force -quiet}
}

foreach f [get_files -quiet *.bd] {
    guang_puts "generate BD: $f"
    catch {
        open_bd_design $f
        upgrade_bd_cells [get_bd_cells -hierarchical]
        validate_bd_design -force
        save_bd_design
        close_bd_design [current_bd_design]
    }
    catch {generate_target all [get_files $f]}
}

update_compile_order -fileset sources_1
guang_puts "重建完成: $xpr_path"
guang_puts "可继续 source scripts/migrate_and_upgrade_ip.tcl -tclargs -project $out_dir -rebuild"
