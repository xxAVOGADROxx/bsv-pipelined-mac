# Build and test with the open-source Bluespec compiler (bsc):
#   make test      compile, link and run every Bluesim testbench
#   make verilog   generate Verilog for the synthesizable instances
#   make report    synthesize them with Yosys; print cells and flops

BSC   ?= bsc
YOSYS ?= yosys

BUILD   := build
VERILOG := verilog

TESTS   := TbMac TbDotProduct
MODULES := mkMac_8x32 mkDotProduct_8x8x32

BSC_FLAGS := -aggressive-conditions -check-assert -p src:test:+

# bsc's Verilog primitives (FIFO2.v, ...) live next to its bin/ directory.
BSC_VLIB := $(dir $(shell which $(BSC)))../lib/Verilog

SRCS := $(wildcard src/*.bs) test/TbUtils.bs

.PHONY: all test verilog synth report clean
.DELETE_ON_ERROR:
.PRECIOUS: $(BUILD)/sim/%.exe

all: test report

test: $(TESTS:%=$(BUILD)/%.log)

# A test passes only if the simulation printed a line that is exactly PASS.
$(BUILD)/%.log: $(BUILD)/sim/%.exe
	./$< | tee $@
	@grep -qx PASS $@

$(BUILD)/sim/%.exe: test/%.bs $(SRCS)
	@mkdir -p $(BUILD)/sim
	$(BSC) -u -sim $(BSC_FLAGS) -bdir $(BUILD)/sim -simdir $(BUILD)/sim -info-dir $(BUILD)/sim -g mk$* $<
	$(BSC) -sim -e mk$* -o $@ $(BSC_FLAGS) -bdir $(BUILD)/sim -simdir $(BUILD)/sim

verilog: $(MODULES:%=$(VERILOG)/%.v)

$(VERILOG)/%.v: $(SRCS)
	@mkdir -p $(BUILD)/v $(VERILOG)
	$(BSC) -u -verilog $(BSC_FLAGS) -bdir $(BUILD)/v -info-dir $(BUILD)/v -vdir $(VERILOG) src/MacSynth.bs

synth: $(MODULES:%=$(BUILD)/%.stat)

$(BUILD)/%.stat: $(VERILOG)/%.v
	$(YOSYS) -q -p "read_verilog -D BSV_NO_INITIAL_BLOCKS $< $(BSC_VLIB)/FIFO2.v; \
	                synth -flatten -top $*; tee -o $@ stat"

# One line per module: total generic cells and flip-flops after synthesis.
report: synth
	@printf '%-22s %8s %8s\n' module cells flops
	@for m in $(MODULES); do \
	  awk -v m=$$m '/Number of cells/ {c=$$NF} /DFF/ {f+=$$NF} \
	    END {printf "%-22s %8d %8d\n", m, c, f}' $(BUILD)/$$m.stat; \
	done

clean:
	rm -rf $(BUILD) $(VERILOG)
