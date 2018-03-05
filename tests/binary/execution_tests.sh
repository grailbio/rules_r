#!/bin/bash

set -eou pipefail

# The rule can be executed with bazel run
bazel run //binary | grep -q yDja77yb

# Or standalone
bazel-bin/binary/binary | grep -q yDja77yb