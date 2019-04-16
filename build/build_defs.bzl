"""Provides go_yacc and genfile_check_test

Copyright 2016 Google Inc. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
"""

load("@bazel_skylib//rules:copy_file.bzl", "copy_file")
load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load(
    "@io_bazel_rules_go//go/private:providers.bzl",
    "GoSource",
)

_GO_YACC_TOOL = "@org_golang_x_tools//cmd/goyacc"

def go_yacc(src, out, visibility = None):
    """Runs go tool yacc -o $out $src."""
    native.genrule(
        name = src + ".go_yacc",
        srcs = [src],
        outs = [out],
        tools = [_GO_YACC_TOOL],
        cmd = ("export GOROOT=$$(dirname $(location " + _GO_YACC_TOOL + "))/..;" +
               " $(location " + _GO_YACC_TOOL + ") " +
               " -o $(location " + out + ") $(SRCS) > /dev/null"),
        visibility = visibility,
        local = 1,
    )

def _extract_go_src(ctx):
    """Thin rule that exposes the GoSource from a go_library."""
    return [DefaultInfo(files = depset(ctx.attr.library[GoSource].srcs))]

extract_go_src = rule(
    implementation = _extract_go_src,
    attrs = {
        "library": attr.label(
            providers = [GoSource],
        ),
    },
)

def genfile_check_test(src, gen):
    """Asserts that any checked-in generated code matches bazel gen."""
    if not src:
        fail("src is required", "src")
    if not gen:
        fail("gen is required", "gen")
    diff_test(
        name = src + "_checkshtest",
        file1 = src,
        file2 = gen,
    )

    # magic copy rule used to update the checked-in version
    native.genrule(
        name = src + "_copysh",
        srcs = [gen],
        outs = [src + "copy.sh"],
        cmd = "echo 'cp $${BUILD_WORKSPACE_DIRECTORY}/$(location " + gen +
              ") $${BUILD_WORKSPACE_DIRECTORY}/" + native.package_name() + "/" + src + "' > $@",
    )
    native.sh_binary(
        name = src + "_copy",
        srcs = [src + "_copysh"],
        data = [gen],
    )

def go_proto_checkedin_test(src, proto = "go_default_library"):
    """Asserts that any checked-in .pb.go code matches bazel gen."""
    genfile = src + "_genfile"
    extract_go_src(
        name = genfile + "go",
        library = proto,
    )

    # TODO(pmbethe09): why is the extra copy needed?
    copy_file(
        name = genfile,
        src = genfile + "go",
        out = genfile + ".go",
    )
    genfile_check_test(src, genfile)
