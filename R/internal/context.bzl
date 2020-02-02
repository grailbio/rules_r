"r_context_data rule"

load("@com_grail_rules_r//R:providers.bzl", "RContextInfo")

_DOC = """r_context_data gathers information about the build configuration.
It is a common dependency of all binary targets."""

def _impl(ctx):
    return [RContextInfo(stamp = ctx.attr.stamp)]

# Modelled after go_context_data in rules_go
# Works around github.com/bazelbuild/bazel/issues/1054
r_context_data = rule(
    implementation = _impl,
    attrs = {
        "stamp": attr.bool(mandatory = True),
    },
    doc = _DOC,
)
