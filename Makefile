RTL   = rtl/pe.v rtl/systolic_array.v rtl/controller.v rtl/systolic_top.v rtl/seq_matmul.v
TOPS  = systolic_top seq_matmul
IV    = iverilog -g2012 -Wall -Wno-timescale
SIZES = 2 3 4 8

.PHONY: all lint sim-pe sim sweep synth pnr plots clean
all: lint sim-pe sim sweep synth pnr plots

build:
	mkdir -p build

lint:
	@for t in $(TOPS) pe; do verilator --lint-only -Wall --top-module $$t $(RTL) || exit 1; done
	@echo "lint clean"

sim-pe: | build
	$(IV) -o build/tb_pe tb/tb_pe.v rtl/pe.v
	vvp -n build/tb_pe | tee build/tb_pe.log
	@grep -q "ALL TESTS PASSED" build/tb_pe.log   # vvp exits 0 even when checks fail

sim: | build
	$(IV) -o build/tb_systolic tb/tb_systolic.v $(RTL)
	vvp -n build/tb_systolic +vcd | tee build/tb_systolic.log
	@grep -q "ALL TESTS PASSED" build/tb_systolic.log

# rerun the matmul demo for several N, keep the cycle counts
sweep: | build
	@echo "N,systolic,sequential" > build/sweep.csv
	@for n in $(SIZES); do \
	  $(IV) -P tb_systolic.N=$$n -o build/tb_sweep tb/tb_systolic.v $(RTL) || exit 1; \
	  vvp -n build/tb_sweep > build/sweep_N$$n.log; \
	  grep -q "ALL TESTS PASSED" build/sweep_N$$n.log || { cat build/sweep_N$$n.log; exit 1; }; \
	  grep CYCLES build/sweep_N$$n.log | sed -E 's/.*N=([0-9]+) systolic=([0-9]+) sequential=([0-9]+)/\1,\2,\3/' >> build/sweep.csv; \
	done
	@cat build/sweep.csv

# Xilinx 7-series estimate (LUT/FF/DSP) + iCE40 netlist for nextpnr
synth: | build
	@for t in $(TOPS); do \
	  yosys -q -l build/xilinx_$$t.log -p "read_verilog $(RTL); synth_xilinx -flatten -top $$t; tee -o build/xilinx_$$t.stat stat" || exit 1; \
	  yosys -q -l build/ice40_$$t.log  -p "read_verilog $(RTL); synth_ice40 -top $$t -json build/$$t.json" || exit 1; \
	  awk -v t=$$t '$$2 ~ /^LUT[1-6]$$/ {l+=$$1} $$2 ~ /^FD/ {f+=$$1} $$2 ~ /^DSP48/ {d+=$$1} \
	    END {printf "%-13s synth_xilinx: LUT=%d FF=%d DSP=%d\n", t, l, f, d}' build/xilinx_$$t.stat; \
	done

# iCE40 HX8K (ct256, enough pins for the data interface): LC usage + Fmax
pnr: | build
	@for t in $(TOPS); do \
	  nextpnr-ice40 -q --hx8k --package ct256 --pcf-allow-unconstrained --freq 50 --timing-allow-fail --seed 1 \
	    --json build/$$t.json --report build/$${t}_pnr.json -l build/pnr_$$t.log || exit 1; \
	  echo "== $$t (iCE40 HX8K)"; grep -E "ICESTORM_LC:|ICESTORM_RAM:|SB_IO:" build/pnr_$$t.log | tail -3; \
	  grep "Max frequency" build/pnr_$$t.log | tail -1; \
	done

plots: | build
	python3 scripts/plots.py

clean:
	rm -rf build
