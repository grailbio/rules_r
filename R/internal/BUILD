load("//R/internal:context.bzl", "r_context_data")

package(default_visibility = ["//visibility:public"])

# Detect if the build is running under --stamp
config_setting(
    name = "stamp",
    values = {"stamp": "true"},
)

# Modelled after go_context_data from rules_go
# passes config values to starlark via a provider
r_context_data(
    name = "r_context_data",
    stamp = select({
        "@com_grail_rules_r//R/internal:stamp": True,
        "//conditions:default": False,
    }),
)
