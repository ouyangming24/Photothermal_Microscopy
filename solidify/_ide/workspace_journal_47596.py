# 2026-10-28T16:44:49.095473
import vitis

client = vitis.create_client()
client.set_workspace(path="solidify")

platform = client.get_component(name="platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../guangre/guangre/design_2_wrapper.xsa")

status = platform.build()

