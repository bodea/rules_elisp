# Copyright 2020, 2021, 2022, 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Contains workspace functions to use Emacs Lisp rules."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//private:repositories.bzl", "HTTP_ARCHIVE_ATTRS", "HTTP_ARCHIVE_DOC", "non_module_deps")

def rules_elisp_dependencies():
    """Installs necessary dependencies for Emacs Lisp rules.

    Call this function in your `WORKSPACE` file.
    """
    maybe(
        http_archive,
        name = "platforms",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/platforms/releases/download/0.0.8/platforms-0.0.8.tar.gz",
            "https://github.com/bazelbuild/platforms/releases/download/0.0.8/platforms-0.0.8.tar.gz",
        ],
        sha256 = "8150406605389ececb6da07cbcb509d5637a3ab9a24bc69b1101531367d89d74",
    )
    maybe(
        http_archive,
        name = "bazel_skylib",
        sha256 = "cd55a062e763b9349921f0f5db8c3933288dc8ba4f76dd9416aac68acee3cb94",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz",
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz",
        ],
    )
    maybe(
        http_archive,
        name = "rules_license",
        sha256 = "4531deccb913639c30e5c7512a054d5d875698daeb75d8cf90f284375fe7c360",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/rules_license/releases/download/0.0.7/rules_license-0.0.7.tar.gz",
            "https://github.com/bazelbuild/rules_license/releases/download/0.0.7/rules_license-0.0.7.tar.gz",
        ],
    )
    maybe(
        http_archive,
        name = "rules_python",
        sha256 = "e85ae30de33625a63eca7fc40a94fea845e641888e52f32b6beea91e8b1b2793",
        strip_prefix = "rules_python-0.27.1",
        url = "https://github.com/bazelbuild/rules_python/releases/download/0.27.1/rules_python-0.27.1.tar.gz",
    )
    maybe(
        http_archive,
        name = "com_google_absl",
        sha256 = "2942db09db29359e0c1982986167167d226e23caac50eea1f07b2eb2181169cf",
        strip_prefix = "abseil-cpp-20230802.0/",
        urls = [
            "https://github.com/abseil/abseil-cpp/archive/refs/tags/20230802.0.zip",  # 2023-08-07
        ],
    )
    maybe(
        http_archive,
        name = "com_google_protobuf",
        sha256 = "e13ca6c2f1522924b8482f3b3a482427d0589ff8ea251088f7e39f4713236053",
        strip_prefix = "protobuf-21.7/",
        urls = [
            "https://github.com/protocolbuffers/protobuf/archive/refs/tags/v21.7.zip",  # 2022-09-29
        ],
    )
    maybe(
        http_archive,
        name = "upb",
        patches = ["@//:upb.patch"],
        sha256 = "0d6af8c8c00b3d733721f8d890ef43dd40f537c2e815b529085c1a6c30a21084",
        strip_prefix = "upb-a5477045acaa34586420942098f5fecd3570f577/",
        urls = [
            "https://github.com/protocolbuffers/upb/archive/a5477045acaa34586420942098f5fecd3570f577.zip",  # 2022-09-23
        ],
    )
    non_module_deps()

# buildifier: disable=unnamed-macro
def rules_elisp_toolchains():
    """Registers the default toolchains for Emacs Lisp."""
    native.register_toolchains("@phst_rules_elisp//elisp:hermetic_toolchain")

def _elisp_http_archive_impl(repository_ctx):
    """Implementation of the `elisp_http_archive` repository rule."""
    repository_ctx.download_and_extract(
        url = repository_ctx.attr.urls,
        integrity = repository_ctx.attr.integrity or fail("missing archive checksum"),
        stripPrefix = repository_ctx.attr.strip_prefix,
    )
    defs_bzl = str(repository_ctx.attr._defs_bzl)
    if not defs_bzl.startswith("@"):
        # Work around https://github.com/bazelbuild/bazel/issues/15916.
        defs_bzl = "@" + defs_bzl
    repository_ctx.template(
        "WORKSPACE.bazel",
        Label("//elisp:WORKSPACE.template"),
        {
            "[[name]]": repr(repository_ctx.attr.name),
        },
        executable = False,
    )
    repository_ctx.template(
        "BUILD.bazel",
        Label("//elisp:BUILD.template"),
        {
            "[[defs_bzl]]": repr(defs_bzl),
        },
        executable = False,
    )

elisp_http_archive = repository_rule(
    doc = HTTP_ARCHIVE_DOC.format(kind = "repository rule"),
    attrs = dict(
        HTTP_ARCHIVE_ATTRS,
        _defs_bzl = attr.label(default = Label("//elisp:defs.bzl")),
    ),
    implementation = _elisp_http_archive_impl,
)
