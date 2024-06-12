STEPS = step0_repl

all: $(STEPS)

dist: mal


%: %.zig
	zig build -Doptimize=ReleaseFast
	ln -sf zig-out/bin/$* .

.PHONY: clean

clean:
	rm -f $(STEPS)
