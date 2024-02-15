# Copyright 2018 The Bazel Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# TODO: Move r_binary_image related definitions to rules_docker.
# https://github.com/bazelbuild/rules_docker/issues/193

load(
    "@io_bazel_rules_docker//container:layer.bzl",
    _layer = "layer",
)
load(
    "@io_bazel_rules_docker//lang:image.bzl",
    _app_layer = "app_layer",
    _layer_file_path = "layer_file_path",
)
load("@com_grail_rules_r//R:providers.bzl", "RBinary")

# Similar to dep_layer_impl, but with output group files.
# We expect to capture any empty files in the app layer.
def _binary_layer_impl(ctx):
    return _layer.implementation(
        ctx,
        # We use all absolute paths.
        directory = "/",
        file_map = {
            _layer_file_path(ctx, f): f
            for f in ctx.attr.binary[OutputGroupInfo][ctx.attr.layer_type].to_list()
        },
    )

_binary_layer_attrs = dict(_layer.attrs)

_binary_layer_attrs.update({
    "binary": attr.label(
        providers = [RBinary],
        doc = "The r_binary target that this layer will capture.",
    ),
    "layer_type": attr.string(
        doc = "The output group type of the files that this layer will capture.",
    ),
    # Override the defaults as in dep_layer.
    "data_path": attr.string(default = "."),
    "directory": attr.string(default = "/app"),
})

_r_binary_layer = rule(
    attrs = _binary_layer_attrs,
    executable = False,
    outputs = _layer.outputs,
    toolchains = ["@io_bazel_rules_docker//toolchains/docker:toolchain_type"],
    implementation = _binary_layer_impl,
)

def _r_binary_image_by_deps(**kwargs):
    name = kwargs["name"]
    layers = kwargs.pop("layers")
    for index, dep in enumerate(layers):
        this_name = "%s.%d" % (name, index)
        _app_layer(name = this_name, base = kwargs["base"], dep = dep, tags = ["manual"])
        kwargs["base"] = this_name

    # Also create an empty directory for the workspace of the binary so that
    # relative symlinks to external repos constructed from short_path (in the
    # form of 'workspace_name/../...') makes sense. See
    # https://github.com/bazelbuild/rules_docker/issues/161.
    _app_layer(create_empty_workspace_dir = True, **kwargs)

def _r_binary_image_by_repo_type(**kwargs):
    name = kwargs["name"]
    layers = {
        "external": name + "_external_filegroup",
        "internal": name + "_internal_filegroup",
        "tools": name + "_tools_filegroup",
    }

    for (layer_type, layer) in layers.items():
        this_name = layer
        _r_binary_layer(
            name = this_name,
            binary = kwargs["binary"],
            layer_type = layer_type,
            tags = ["manual"],
        )

    kwargs["layers"] = layers.values()
    _app_layer(**kwargs)

def r_binary_image(**kwargs):
    """Constructs a container image wrapping an r_binary target.
    Args:
        layers: Optional list of binary deps whose runfiles should be
            factored out into their own layers. If absent, transitive
            dependencies of type r_pkg will be partitioned into layers,
            similar to r_library_image.
        **kwargs: same as container_image.
    """

    # Reset cmd in the base R image.
    if not kwargs.get("cmd"):
        kwargs.setdefault("null_cmd", True)

    # Set "manual" by default to not build images in CI, etc.
    kwargs.setdefault("tags", [])
    kwargs["tags"].append("manual")

    if "layers" in kwargs:
        _r_binary_image_by_deps(**kwargs)
    else:
        _r_binary_image_by_repo_type(**kwargs)
