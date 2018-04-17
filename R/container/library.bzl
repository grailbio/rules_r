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

load(
    "@io_bazel_rules_docker//container:container.bzl",
    _container_image = "container_image",
)
load(
    "@io_bazel_rules_docker//container:layer.bzl",
    _layer = "layer",
)
load("@com_grail_rules_r//R:providers.bzl", "RLibrary")

def _library_layer_impl(ctx):
    provider = ctx.attr.library[RLibrary]
    file_map = provider.container_file_map[ctx.attr.layer_type]
    lib_path = ctx.attr.directory + "/" + provider.container_library_path
    lib_path = lib_path if lib_path.startswith("/") else "/" + lib_path
    return _layer.implementation(ctx, file_map=file_map, env={"R_LIBS_USER": lib_path})

_r_library_layer = rule(
    attrs = _layer.attrs + {
        "library": attr.label(
            providers = [RLibrary],
            doc = "The r_library target that this layer will capture.",
        ),
        "layer_type": attr.string(
            doc = "The output group type of the files that this layer will capture.",
        ),
    },
    executable = False,
    outputs = _layer.outputs,
    implementation = _library_layer_impl,
)

def r_library_image(**kwargs):
    """Container image containing an R library.

    The library is installed at the location specified in the
    container_library_path attribute of the r_library target, relative to the
    directory attribute of the image.

    The library files are partitioned into different layers based on the tag
    'r-external-repo' on the r_pkg target. This tag is automatically set by
    razel when the value of the 'external' argument to `buildify` is true,
    which is the default behavior of r_repository and r_repository_list rules.

    The idea is that external repo targets will be relatively slow changing
    than your own targets, and so should get a layer of their own.

    Args:
        library: An r_library target.
        **kwargs: same as container_image.
    """

    if not "library" in kwargs:
        fail("'library' attribute must be specified for r_library_image.")

    name = kwargs["name"]
    _layers = {
        "external": name + "_external",
        "internal": name + "_internal",
        "tools": name + "_tools",
    }
  
    kwargs.setdefault("directory", "")
    [_r_library_layer(
        name = layer,
        library = kwargs["library"],
        layer_type = layer_type,
        directory = kwargs["directory"],
    ) for (layer_type, layer) in _layers.items()]
    kwargs.pop("library")

    kwargs.setdefault("layers", [])
    kwargs["layers"].extend(_layers.values())
    _container_image(**kwargs)
