# Build and test with the open-source Bluespec compiler (bsc):
#   make test      compile, link and run every Bluesim testbench

BSC   ?= bsc

BUILD   := build

TESTS   := TbMac

BSC_FLAGS := -aggressive-conditions -check-assert -p src:test:+

SRCS := $(wildcard src/*.bs) test/TbUtils.bs

.PHONY: all test clean
.DELETE_ON_ERROR:
.PRECIOUS: $(BUILD)/sim/%.exe

all: test

test: $(TESTS:%=$(BUILD)/%.log)

# A test passes only if the simulation printed a line that is exactly PASS.
$(BUILD)/%.log: $(BUILD)/sim/%.exe
	./$< | tee $@
	@grep -qx PASS $@

$(BUILD)/sim/%.exe: test/%.bs $(SRCS)
	@mkdir -p $(BUILD)/sim
	$(BSC) -u -sim $(BSC_FLAGS) -bdir $(BUILD)/sim -simdir $(BUILD)/sim -info-dir $(BUILD)/sim -g mk$* $<
	$(BSC) -sim -e mk$* -o $@ $(BSC_FLAGS) -bdir $(BUILD)/sim -simdir $(BUILD)/sim

clean:
	rm -rf $(BUILD)
