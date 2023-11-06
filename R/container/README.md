# Container Support

You can create Docker or OCI images of R packages using Bazel.

In your `WORKSPACE` file, load the Docker rules and specify the base R image.

```python
# Change to the version of these rules you want and use the corresponding sha256.
http_archive(
    name = "io_bazel_rules_docker",
    sha256 = "95d39fd84ff4474babaf190450ee034d958202043e366b9fc38f438c9e6c3334",
    strip_prefix = "rules_docker-0.16.0",
    urls = [
        "https://github.com/bazelbuild/rules_docker/releases/download/v0.16.0/rules_docker-v0.16.0.tar.gz",
    ],
)

load(
    "@io_bazel_rules_docker//container:container.bzl",
    "container_pull",
    container_repositories = "repositories",
)

container_repositories()

container_pull(
    name = "r_base",
    registry = "index.docker.io",
    repository = "rocker/r-base",
    tag = "latest",
)
```

<a name="r_library_image"></a>

## r_library_image

In a `BUILD` file, define your library of R packages and install them
in a Docker image using this rule. Dependencies are installed implicitly
in an efficient layered mechanism.

```python
load("@com_rules_r//R:defs.bzl", "r_library")

r_library(
    name = "my_r_library",
    pkgs = [
        "//path/to/packageA:r_pkg_target",
        "//path/to/packageB:r_pkg_target",
    ],
)

r_library_image(
    name = "my_r_library_image",
    base = "@r_base//image",
    library = "my_r_library",
    library_path = "r-libs",
)
```

The rule takes the same arguments as `container_image`, and
additionally a `library` attribute. For more details on how the rule
works, see the documentation in [library.bzl][library.bzl].

Alternatively, if you want to use `container_image` rule directly for some
reason, you can use the `r_library_tar` rule to provide a tar to the container.

```python
load("@io_bazel_rules_docker//container:container.bzl", "container_image")

load("@com_rules_r//R:defs.bzl", "r_library_tar")

r_library_tar(
    name = "my_r_library_archive",
    library = ":my_r_library",
    library_path = "r-libs",
)

container_image(
    name = "image",
    base = "@r_base//image",
    env = {"R_LIBS_USER": "/r-libs"},
    tars = [":my_r_library_arhive.tar"],
    repository = "my_repo",
)
```

<a name="r_binary_image"></a>

## r_binary_image

This rule wraps an `r_binary` target in a container, ideal for quickly setting
up a containerized application. The collective R library that the binary
depends on is not made available in an easy to use way in the container. Prefer
`r_library_image` for such a use case.

The rule takes the same arguments as `container_image`, and
additionally a `binary` attribute. For more details on how the rule
works, see the documentation in [binary.bzl][binary.bzl].

```python
load("@com_rules_r//R:defs.bzl", "r_library")

r_binary(
    name = "my_r_binary",
    src = "my_r_binary.R",
    deps = [
        "//path/to/packageA:r_pkg_target",
        "//path/to/packageB:r_pkg_target",
    ],
)

r_binary_image(
    name = "my_r_binary_image",
    base = "@r_base//image",
    binary = "my_r_binary",
)
```

[library.bzl]: library.bzl
[binary.bzl]: binary.bzl
