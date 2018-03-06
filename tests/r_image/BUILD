load("@com_grail_rules_r//R:image.bzl", "r_image")
load("@io_bazel_rules_docker//contrib:test.bzl", "container_test")

r_image(
    name = "image",
    binary = "//binary",
    # testthat and its dependencies will be included in a separate layer
    layers = [
        "@R_testthat//:testthat",
    ],
)

# Test that testthat and its dependencies are included in a separate layer
container_test(
    name = "structure_tests.0",
    size = "medium",
    configs = ["structure_tests.0.yaml"],
    driver = "tar",
    image = ":image.0",
)
