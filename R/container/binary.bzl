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
    "@io_bazel_rules_docker//container:container.bzl",
    _container = "container",
)
load(
    "@io_bazel_rules_docker//lang:image.bzl",
    _app_layer = "app_layer",
    _dep_layer = "dep_layer",
    _layer_file_path = "layer_file_path",
)
load("@com_grail_rules_r//R:providers.bzl", "RBinary")

# Similar to dep_layer_impl, but with output group files.
# We expect to capture any empty files in the app layer.
def _binary_layer_impl(ctx):
    return _container.image.implementation(
        ctx,
        # We use all absolute paths.
        directory = "/",
        file_map = {
            _layer_file_path(ctx, f): f
            for f in ctx.attr.binary[OutputGroupInfo][ctx.attr.layer_type]
        },
    )

_r_binary_layer = rule(
    attrs = _container.image.attrs + {
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
    },
    executable = True,
    outputs = _container.image.outputs,
    implementation = _binary_layer_impl,
)

def _r_binary_image_by_deps(**kwargs):
    name = kwargs["name"]
    layers = kwargs.pop("layers")
    for index, dep in enumerate(layers):
        this_name = "%s.%d" % (name, index)
        _dep_layer(name = this_name, base = kwargs["base"], dep = dep, tags = ["manual"])
        kwargs["base"] = this_name

    kwargs["lang_layers"] = layers
    _app_layer(**kwargs)

def _r_binary_image_by_repo_type(**kwargs):
    name = kwargs["name"]
    layers = {
        "external": name + "_external_filegroup",
        "internal": name + "_internal_filegroup",
        "tools": name + "_tools_filegroup",
    }

    base = kwargs["base"]
    for index, (layer_type, layer) in enumerate(layers.items()):
        this_name = "%s.%d" % (name, index)
        _r_binary_layer(
            name = this_name,
            base = base,
            binary = kwargs["binary"],
            layer_type = layer_type,
            tags = ["manual"],
        )
        base = this_name
    kwargs["base"] = base

    kwargs["lang_layers"] = layers.values()
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

    if "lang_layers" in kwargs:
        fail("lang_layers is not allowed for r_binary_image")

    # Reset cmd in the base R image.
    if not kwargs.get("cmd"):
        kwargs.setdefault("null_cmd", True)

    if "layers" in kwargs:
        _r_binary_image_by_deps(**kwargs)
    else:
        _r_binary_image_by_repo_type(**kwargs)
