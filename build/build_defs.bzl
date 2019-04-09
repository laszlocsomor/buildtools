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

def _runfiles_path(f):
    if f.root.path:
        return f.path[len(f.root.path) + 1:]  # generated file
    else:
        return f.path  # source file

def _diff_test_impl(ctx):
    if ctx.attr.is_windows:
        test_bin = ctx.actions.declare_file(ctx.label.name + "-test.bat")
        ctx.actions.write(
            output = test_bin,
            content = r"""@echo off
setlocal enableextensions
set MF=%RUNFILES_MANIFEST_FILE:/=\%
set PATH=%SYSTEMROOT%\system32
for /F "tokens=2* usebackq" %%i in (`findstr.exe /l /c:"%TEST_WORKSPACE%/{file1} " "%MF%"`) do (
  set RF1=%%i
  set RF1=%RF1:/=\%
)
if "%RF1%" equ "" (
  echo>&2 ERROR: {file1} not found
  exit /b 1
)
for /F "tokens=2* usebackq" %%i in (`findstr.exe /l /c:"%TEST_WORKSPACE%/{file2} " "%MF%"`) do (
  set RF2=%%i
  set RF2=%RF2:/=\%
)
if "%RF2%" equ "" (
  echo>&2 ERROR: {file2} not found
  exit /b 1
)
fc.exe 2>NUL 1>NUL /B "%RF1%" "%RF2%"
if %ERRORLEVEL% equ 2 (
  echo FAIL: "{file1}" and/or "{file2}" not found
  exit /b 1
) else (
  if %ERRORLEVEL% equ 1 (
    echo FAIL: files "{file1}" and "{file2}" differ
    exit /b 1
  )
)
""".format(
                file1 = _runfiles_path(ctx.file.file1),
                file2 = _runfiles_path(ctx.file.file2),
            ),
            is_executable = True,
        )
    else:
        test_bin = ctx.actions.declare_file(ctx.label.name + "-test.sh")
        ctx.actions.write(
            output = test_bin,
            content = """#!/bin/bash
set -euo pipefail
if [[ -d "${{RUNFILES_DIR:-/dev/null}}" ]]; then
  RF1="$RUNFILES_DIR/$TEST_WORKSPACE/{file1}"
  RF2="$RUNFILES_DIR/$TEST_WORKSPACE/{file2}"
elif [[ -f "${{RUNFILES_MANIFEST_FILE:-/dev/null}}" ]]; then
  RF1="$(grep -F -m1 '{file1} ' "$RUNFILES_MANIFEST_FILE" | sed 's/^[^ ]* //')"
  RF2="$(grep -F -m1 '{file2} ' "$RUNFILES_MANIFEST_FILE" | sed 's/^[^ ]* //'))"
else
  echo >&2 "ERROR: could not find \"{file1}\" and \"{file2}\""
fi
diff "$RF1" "$RF2"
""".format(
                file1 = _runfiles_path(ctx.file.file1),
                file2 = _runfiles_path(ctx.file.file2),
            ),
            is_executable = True,
        )
    return DefaultInfo(
        executable = test_bin,
        files = depset(direct = [test_bin]),
        runfiles = ctx.runfiles(files = [test_bin, ctx.file.file1, ctx.file.file2]),
    )

_diff_test = rule(
    attrs = {
        "file1": attr.label(
            allow_files = True,
            mandatory = True,
            single_file = True,
        ),
        "file2": attr.label(
            allow_files = True,
            mandatory = True,
            single_file = True,
        ),
        "is_windows": attr.bool(mandatory = True),
    },
    test = True,
    implementation = _diff_test_impl,
)

def diff_test(name, file1, file2, **kwargs):
    _diff_test(
        name = name,
        file1 = file1,
        file2 = file2,
        is_windows = select({
            "@bazel_tools//src/conditions:host_windows": True,
            "//conditions:default": False,
        }),
        **kwargs
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
    native.genrule(
        name = genfile,
        srcs = [genfile + "go"],
        outs = [genfile + ".go"],
        cmd = "cp $< $@",
    )
    genfile_check_test(src, genfile)
