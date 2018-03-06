# Copyright 2018 The R Rule Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load(
    "@io_bazel_rules_docker//lang:image.bzl",
    "app_layer",
    "dep_layer",
)
load(":defs.bzl", "r_binary")
load(
    "@io_bazel_rules_docker//container:container.bzl",
    _container = "container",
)

DEFAULT_IMAGE_BASE = "@r_base//image"

def r_image(name, base=None, deps=[], layers=[], binary=None, **kwargs):
    """Constructs a container image wrapping an r_binary target.

    Args:
        base: Base container image.
        deps: r_binary deps.
        layers: Augments "deps" with dependencies that should be put into
            their own layers, or pick dependencies from the r_binary "binary" to be
            put into their own layers.
        binary: Specify the r_binary instead of having the rule as part of the r_image macro.
        **kwargs: See r_binary.
    """

    if not binary:
        binary = name + ".binary"
        r_binary(name=binary, deps=deps + layers, **kwargs)
    elif deps:
        fail("kwarg does nothing when binary is specified", "deps")

    base = base or DEFAULT_IMAGE_BASE
    for index, dep in enumerate(layers):
        this_name = "%s.%d" % (name, index)
        dep_layer(name=this_name, base=base, dep=dep)
        base = this_name
    
    visibility = kwargs.get('visibility', None)
    tags = kwargs.get('tags', None)
    testonly = kwargs.get('testonly', None)
    app_layer(name=name, base=base,
              binary=binary, lang_layers=layers, visibility=visibility,
              tags=tags)