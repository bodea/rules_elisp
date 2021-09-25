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

#ifndef PHST_RULES_ELISP_ELISP_ALGORITHM_H
#define PHST_RULES_ELISP_ELISP_ALGORITHM_H

#include <vector>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#pragma GCC diagnostic ignored "-Woverflow"
#include "absl/algorithm/container.h"
#include "absl/container/flat_hash_set.h"
#pragma GCC diagnostic pop

namespace phst_rules_elisp {

template <typename T>
std::vector<T> Sort(const absl::flat_hash_set<T>& set) {
  std::vector<T> result(set.begin(), set.end());
  absl::c_sort(result);
  return result;
}

template <typename T>
typename T::mapped_type Find(const T& map, const typename T::key_type& key) {
  const auto it = map.find(key);
  return it == map.end() ? typename T::mapped_type() : it->second;
}

}  // namespace phst_rules_elisp

#endif
