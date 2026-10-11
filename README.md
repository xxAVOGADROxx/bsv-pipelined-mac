# bsv-pipelined-mac

[![ci](https://github.com/xxAVOGADROxx/bsv-pipelined-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/xxAVOGADROxx/bsv-pipelined-mac/actions/workflows/ci.yml)

This repo contains a pipelined multiply-accumulate (MAC) unit and an N-lane
dot-product engine, written in **Bluespec Haskell (BH)**. Dot products are the
core operation in ML accelerators.

- Each design is **type-parameterized**. Lane count, operand width and
  accumulator width are type-level numbers, and the type checker rejects
  configurations that would silently overflow.
- **Self-checking Bluesim testbenches** check every result against an
  independent reference model. They also check that the designs sustain one
  input per cycle.
- **CI synthesizes the generated Verilog with Yosys** and reports cell and
  flip-flop counts, so design changes are judged by measured area, not
  intuition.

I'm a Haskell engineer learning hardware design, and this is my first
Bluespec project.

## Designs

### `mkMac` — streaming MAC

```
put(x, y, isLast) --> [inQ] --rl_multiply--> [mulQ] --rl_accumulate--> [outQ] --> get
```

Operand pairs stream in at one per cycle (initiation interval 1). When the
`isLast` flag is set, the current sum is emitted and the accumulator is
cleared. The multiplier is exactly `2 * n_in` bits wide, not accumulator
wide, so it is no bigger than the operands require.

```haskell
interface (Mac_IFC :: # -> # -> *) n_in n_acc =
    put :: Int n_in -> Int n_in -> Bool -> Action
    get :: ActionValue (Int n_acc)
```

### `mkDotProduct` — N-lane dot-product engine

```
put(xs, ys) --> [inQ] --N multipliers--> [prodQ] --adder tree--> [outQ] --> get
```

The engine takes one pair of length-N vectors per cycle. `rl_multiply`
instantiates N multipliers in parallel. `rl_reduce` sums the products with
`Vector.fold (+)`, which elaborates to a balanced adder tree of depth
`log2 N`. The same source builds a 4-lane or a 64-lane engine.

### Correctness from the type system

Both modules carry these provisos:

```haskell
mkMac :: (Add n_in n_in n_prod, Add n_prod n_pad n_acc)
      => Module (Mac_IFC n_in n_acc)
```

They say that a full `2 * n_in`-bit product must fit in the `n_acc`-bit
accumulator. Asking for int16 operands with a 24-bit accumulator is therefore
a compile error, not a silent truncation bug.
[`test/reject/MacTooNarrow.bs`](test/reject/MacTooNarrow.bs) checks this, and
`make test` fails if bsc ever accepts it:

```
Error: "test/reject/MacTooNarrow.bs", line 9, column 0: (T0031)
  The contexts for this expression could not be resolved ...
```

## Verification

| Testbench | Stimulus | Checks |
|---|---|---|
| `TbMac` | 256 dot products × 8 terms | every sum vs. reference; ≤ 1 cycle per term |
| `TbDotProduct` | 512 vector pairs, 8 lanes | every result vs. reference; ≤ 1 cycle per vector |

- **Independent reference models.** The models are written differently from
  the hardware. `TbMac` multiplies directly at accumulator width.
  `TbDotProduct` uses an index loop instead of `zipWith` plus an adder tree.
  This way the model and the design are unlikely to share a bug.
- **Corner cases first, then random inputs.** The tests start with
  `minBound * minBound` (the largest positive product),
  `minBound * maxBound` and all-extreme vectors. After that comes
  deterministic xorshift32 stimulus, so any failure is reproducible.
- **Throughput is asserted, not just observed.** A test fails if it takes
  more than *inputs + 8* cycles, which catches any scheduling conflict that
  would stall the pipeline.

Current results: `TbMac` takes 2051 cycles for 2048 terms, and `TbDotProduct`
takes 515 cycles for 512 vectors.

## Synthesis results

Yosys generic synthesis (`synth -flatten`) of the int8 → int32 instances.
These are technology-independent gate counts. They are useful for comparing
design alternatives, not as absolute silicon area.

| Module | Cells | Flip-flops |
|---|---:|---:|
| `mkMac_8x32` | 1390 | 170 |
| `mkDotProduct_8x8x32` (8 lanes) | 7371 | 577 |

### A measured tradeoff: product width across the pipeline

The first version of `mkDotProduct` sign-extended every product to the 32-bit
accumulator width *before* the `prodQ` pipeline register. Moving the widening
into the adder tree means the products are registered at their natural 16
bits:

| `prodQ` element width | Cells | Flip-flops |
|---|---:|---:|
| `n_acc` (32 bits) | 8410 | 710 |
| `2 * n_in` (16 bits) | **7371** (−12%) | **577** (−19%) |

The change is one type in the FIFO declaration plus a `Vector.map widen`. The
type parameters made it a two-line edit, and CI measured the effect.

## Building

You need [bsc](https://github.com/B-Lang-org/bsc) (tested with 2026.07.1) and
[Yosys](https://github.com/YosysHQ/yosys) on Linux or macOS.

```sh
make test      # Bluesim testbenches + type-level rejection tests
make verilog   # Verilog for mkMac_8x32 and mkDotProduct_8x8x32 in verilog/
make report    # Yosys synthesis, one line per module
```

## Layout

```
src/Mac.bs                  streaming MAC
src/DotProduct.bs           N-lane dot-product engine
src/MacSynth.bs             concrete instances for Verilog generation
test/TbMac.bs               MAC testbench
test/TbDotProduct.bs        dot-product testbench
test/TbUtils.bs             xorshift32 PRNG
test/reject/                designs that must not compile
```

## Next steps

- Register the adder tree every *k* levels and measure the area against
  critical-path tradeoff with a timing tool such as OpenSTA.
- Generalize the operand type behind a typeclass (int8, fixed point,
  bfloat16).
- Build a systolic array out of `mkMac` tiles.

## License

MIT
