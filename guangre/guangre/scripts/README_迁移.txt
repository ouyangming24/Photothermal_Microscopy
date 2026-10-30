Guang 工程迁移脚本说明
======================

目录
  scripts\migrate_and_upgrade_ip.tcl   主脚本：打开工程、升级 IP、重新 generate
  scripts\recreate_project.tcl         备用：.xpr/cache 损坏时从源码重建
  scripts\run_migrate.bat              Windows 一键运行（推荐）
  scripts\run_recreate.bat             Windows 一键重建

新电脑操作步骤
  1. 安装同系列或更新的 Vivado（本工程近期为 2025.1；2020.1+ 一般也可）
  2. 把整个 "guang - guhua" 文件夹拷到新电脑
  3. 确认 PATH 能找到 vivado，或从 "Vivado Tcl Shell" 启动
  4. 双击 scripts\run_migrate.bat
  5. 打开 guang.xpr，检查 Reports -> Report IP Status 是否全部可综合

常用命令
  run_migrate.bat                 升级 IP + generate（不综合）
  run_migrate.bat -rebuild        升级后再综合+实现
  run_migrate.bat -bitstream      升级后综合+实现+生成 bit
  run_migrate.bat -no_bd          跳过 design_1.bd（该 BD 当前未接顶层）
  run_migrate.bat -gui            GUI 模式跑脚本，方便看过程

Vivado Tcl Console
  cd {工程目录}
  source ./scripts/migrate_and_upgrade_ip.tcl
  # 或
  source ./scripts/migrate_and_upgrade_ip.tcl -tclargs -rebuild

注意
  - 器件固定为 xc7z020clg484-2
  - clk_wiz_0 / design_1.bd / da_wave_send.v 当前为 AutoDisabled，不影响顶层 guang
  - 若 upgrade 后 DDS/ILA 端口变化，需人工核对 guang.v 例化
  - 迁移后建议清掉旧路径残留：可删除 *.cache、*.runs 后再跑脚本（脚本会重新 generate）
