load("@com_grail_rules_r//R:defs.bzl", "r_binary", "r_test")

r_binary(
    name = "binary",
    srcs = ["script.R"],
    data = [
        "data.txt",
    ],
    env_vars = {
        "FOO": "bar",
    },
    deps = [
        "//exampleA",
        "@R_testthat//:testthat",
    ],
)

sh_test(
    name = "sh_test",
    size = "small",
    srcs = ["test.sh"],
    data = [":binary"],
)

r_test(
    name = "test",
    size = "small",
    srcs = ["script.R"],
    data = [
        "data.txt",
    ],
    env_vars = {
        "FOO": "bar",
    },
    deps = [
        "//exampleA",
        "@R_testthat//:testthat",
    ],
)
