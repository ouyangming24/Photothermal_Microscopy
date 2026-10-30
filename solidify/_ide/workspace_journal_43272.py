# 2026-09-21T10:09:16.917189900
import vitis

client = vitis.create_client()
client.set_workspace(path="solidify")

advanced_options = client.create_advanced_options_dict(dt_overlay="0")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../guangre/guangre/design_2_wrapper.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",generate_dtb = False,advanced_options = advanced_options,compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

vitis.dispose()

vitis.dispose()

