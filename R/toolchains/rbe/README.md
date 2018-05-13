Remote Build Execution
======================

[Remote Build Execution](https://docs.bazel.build/versions/master/remote-caching.html) is a
work-in-progress Bazel feature to allow the execution of actions (build, test, run, ...) on a
remote worker.  It can be used not only to distribute the build process using a [build farm](https://github.com/bazelbuild/bazel-buildfarm) but also to avoid the painful definition of
cross-compilers, as workers can have a different architecture than the Bazel instance.  In particular,
with RBE one can build a Docker image in Bazel without leaving Mac OSX.  The procedure is as follows:

1. Install Docker for Mac OSX.

2. Compile Bazel at HEAD to benefit from the
[Docker spawn strategy](https://github.com/bazelbuild/bazel/commit/ff726ffa222594b9aa2b9b518ac8453763f8432a).

3. Build the Remote Build Execution image containing the basic toolchain needed by Bazel and the R toolchain:
```bash
docker build -t rbe_r_jessie:latest R/toolchains/rbe/rbe_r_jessie
```

4. Invoke `bazel_k8` (definition below) instead of `bazel` to seamlessly switch to compiling
and running on a Linux architecture:
```bash
# The Remote Build Execution image to use
RBE_IMAGE=rbe_r_jessie:latest

# The CROSSTOOL configuration to use.  It must match what's within the RBE_IMAGE.
CROSSTOOL_TOP=@bazel_toolchains//configs/debian8_clang/0.3.0/bazel_0.13.0/default:toolchain

# Invoke `bazel_k8` instead of bazel to seamlessly switch to compiling native code for Linux.
bazel_k8() {
  bazel $1 \
    --spawn_strategy=docker \
    --genrule_strategy=docker \
    --cpu=k8 \
    --host_cpu=k8 \
    --extra_toolchains=@com_grail_rules_r//R/toolchains/rbe:toolchain \
    --crosstool_top=$CROSSTOOL_TOP \
    --define=EXECUTOR=remote \
    --experimental_docker_use_customized_images=false \
    --experimental_docker_image=$RBE_IMAGE \
    "${@:2}"
}

# Go to the test workspace
cd tests

# Compile and execute a test on the k8 architecture.
bazel_k8 test //exampleC:test

# Compiles the `binary_image` Docker image and loads it onto the local Docker daemon.
bazel_k8 run //:binary_image -- --norun

# Execute the `/app/binary` R script living within the `binary_image` Docker image.
docker run --entrypoint= bazel:binary_image /app/binary

# Whereas both `bazel test //exampleC:test` and `bazel_k8 test //exampleC:test` succeed,
# only `bazel_k8 build //:binary_image`, not `bazel build //:binary_image`, builds a
# Docker image that can be executed: in the latter case, all the binary code has been
# compiled for Mac OSX, not Linux.
```
