// Copyright 2020, 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "elisp/binary.h"

#include <cassert>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#pragma GCC diagnostic ignored "-Woverflow"
#include "absl/container/flat_hash_set.h"
#include "absl/random/random.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/string_view.h"
#include "absl/strings/strip.h"
#pragma GCC diagnostic pop

#include "elisp/algorithm.h"
#include "elisp/file.h"
#include "elisp/load.h"
#include "elisp/manifest.h"
#include "elisp/process.h"
#include "elisp/status.h"

namespace phst_rules_elisp {

static std::string RunfilesDir(const Environment& env) {
  const std::string vars[] = {"RUNFILES_DIR", "TEST_SRCDIR"};
  for (const auto& var : vars) {
    auto value = Find(env, var);
    if (!value.empty()) return value;
  }
  return std::string();
}

static absl::StatusOr<std::vector<std::string>> ArgFiles(
    const BinaryOptions& opts, const std::string& root,
    const absl::flat_hash_set<int>& indices) {
  // The assertion holds because opts.argv was constructed from argc and argv,
  // so it necessarily has fewer than std::numeric_limits<int>::max() elements.
  assert(opts.argv.size() <
         static_cast<unsigned int>(std::numeric_limits<int>::max()));
  const int argc = static_cast<int>(opts.argv.size());
  std::vector<std::string> result;
  for (int i : Sort(indices)) {
    if (i < 0) i += argc;
    if (i >= 0 && i < argc) {
      absl::string_view arg = opts.argv[static_cast<unsigned int>(i)];
      // File arguments are often quoted so that Emacs doesn’t interpret them as
      // special filenames.  Unquote them first.
      absl::ConsumePrefix(&arg, "/:");
      ASSIGN_OR_RETURN(auto file, MakeAbsolute(arg));
      // Make filenames relative if possible.
      if (!root.empty()) {
        ASSIGN_OR_RETURN(file, MakeRelative(file, root));
      }
      result.push_back(std::move(file));
    }
  }
  return result;
}

static absl::StatusOr<int> RunBinaryImpl(const BinaryOptions& opts) {
  const auto orig_env = CopyEnv();
  ASSIGN_OR_RETURN(const auto runfiles, CreateRunfiles(opts.argv.at(0)));
  ASSIGN_OR_RETURN(const auto emacs, Runfile(*runfiles, opts.wrapper));
  std::vector<std::string> args;
  absl::BitGen random;
  ASSIGN_OR_RETURN(auto manifest, AddManifest(opts.mode, args, random));
  args.push_back("--quick");
  args.push_back("--batch");
  RETURN_IF_ERROR(AddLoadPath(*runfiles, args, opts.load_path));
  for (const auto& file : opts.load_files) {
    ASSIGN_OR_RETURN(const auto abs, Runfile(*runfiles, file));
    args.push_back(absl::StrCat("--load=", abs));
  }
  if (manifest) {
    const auto runfiles = RunfilesDir(orig_env);
    ASSIGN_OR_RETURN(auto input_files,
                     ArgFiles(opts, runfiles, opts.input_args));
    ASSIGN_OR_RETURN(auto output_files,
                     ArgFiles(opts, runfiles, opts.output_args));
    RETURN_IF_ERROR(WriteManifest(opts, std::move(input_files),
                                  std::move(output_files), manifest.value()));
  }
  ASSIGN_OR_RETURN(const auto code,
                   Run(opts, orig_env, *runfiles, emacs, args, {}));
  if (manifest) RETURN_IF_ERROR(manifest->Close());
  return code;
}

int RunBinary(const BinaryOptions& opts) {
  const auto status_or_code = RunBinaryImpl(opts);
  if (!status_or_code.ok()) {
    std::clog << status_or_code.status() << std::endl;
    return EXIT_FAILURE;
  }
  return status_or_code.value();
}

}  // namespace phst_rules_elisp
