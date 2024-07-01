STEPS = step0_repl step1_read_print step2_eval step3_env

all: $(STEPS)

dist: mal


%: %.zig
	zig build -Doptimize=Debug
	ln -sf zig-out/bin/$* .

.PHONY: clean

clean:
	rm -f $(STEPS)
