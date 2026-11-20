# Enzyme-CIR-bench

This is the benchmark repository for running [ADBench](https://github.com/microsoft/ADBench) with [Enzyme-CIR](https://github.com/Ringo-Leo/Enzyme-CIR). The full source code of Enzyme-CIR is available [here](https://github.com/Ringo-Leo/Enzyme-CIR).

Notice that Enzyme-CIR requires some changes to upstream LLVM. Some of them are brought from upstream, while others are implemented by ourselves. All of these changes are collected into a single branch [here](https://github.com/Ringo-Leo/llvm-project/tree/cir).

# Code

Besides the changes in the Enzyme-CIR repository, we need some glue code (Module) to attach Enzyme semantics to ADBench. The glue code is located in `adbench/modules/enzyme`.

This code is finally linked with the ADBench runner helper, which calls `get_*_test` in our glue code to execute the differentiated code.

# Build and Run

```bash
./setup.sh
./run.sh
```

## ./setup.sh

The setup script does four things:

1. Download and build our LLVM fork at the correct commit, including checking whether CIR is included. For those interested in the LLVM configuration, please take a look at `build_llvm()` in `./setup.sh`.
2. Download and build Enzyme with CIR and LLVM support from our repository.
3. Copy the Enzyme driver, set up ADBench, and build it.
4. Set up the Python environment for running Autograd.

## ./run.sh

This script runs benchmarks and generates plots for all supported AD tools. The available tools are `Manual`, `ManualEigen`, `ManualEigenVector`, `Finite`, `FiniteEigen`, `Tapenade`, `EnzymeCIR`, and `EnzymeLLVM`.

The differentiated binaries for EnzymeLLVM and EnzymeCIR are built through `adbench/build_enzyme.sh`. The `clang++` parameters used for differentiation are also defined there.

We run multiple tests from ADBench, including GMM, LSTM, bundle adjustment, and hand tracking. Notice that not all tools can run every test. Please take a look at `TOOLS` in `adbench/run_bench.py` for the supported combinations.

After running the benchmarks, the generated plots will be available in `results/`, showing the runtime under different benchmark parameters.
