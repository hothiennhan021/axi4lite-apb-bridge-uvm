
-i ../tb/agents/axi_lite
-i ../tb/agents/apb
-i ../tb/env
-i ../tb/tests

../rtl/axi2apb_bridge.sv

../tb/top/interfaces.sv

../tb/sva/axi_lite_protocol.sv
../tb/sva/apb_protocol.sv
../tb/sva/bridge_protocol.sv

../tb/pkg/axi2apb_pkg.sv

../tb/top/top.sv
