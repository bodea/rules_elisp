# Copyright 2020 Google LLC
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

load("@bazel_gazelle//:def.bzl", "gazelle")
load("@pip//:requirements.bzl", "entry_point")
load("@rules_python//python:pip.bzl", "compile_pip_requirements")

compile_pip_requirements(
    name = "requirements",
    extra_args = [
        "--allow-unsafe",  # for setuptools
    ],
    requirements_in = "requirements.in",
    requirements_txt = "requirements.txt",
)

alias(
    name = "pylint",
    actual = entry_point("pylint"),
)

alias(
    name = "pytype",
    actual = entry_point("pytype"),
)

# gazelle:prefix github.com/phst/rules_elisp
gazelle(name = "gazelle")
