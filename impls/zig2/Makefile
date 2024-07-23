STEPS = step0_repl step1_read_print step2_eval step3_env step4_if_fn_do step5_tco step6_file

all: $(STEPS)

dist: mal


%: %.zig
	zig build -Doptimize=Debug
	ln -sf zig-out/bin/$* .

.PHONY: clean

clean:
	rm -f $(STEPS)
