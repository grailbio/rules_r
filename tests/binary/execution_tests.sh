#!/bin/bash

set -eou pipefail

# The rule can be executed with bazel run
bazel run //binary | grep -q yDja77yb
bazel run //binary:binary_shebang | grep -q yDja77yb

# Or standalone
bazel-bin/binary/binary | grep -q yDja77yb
bazel-bin/binary/binary_shebang | grep -q yDja77yb

# And arguments can be passed
bazel run //binary:binary_shebang -- hello world | grep "hello world" > /dev/null