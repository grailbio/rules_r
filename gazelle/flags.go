/*
Copyright 2018 The Bazel Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package razel

import (
	"sort"
	"strings"
)

type StringSet map[string]struct{}

func (set *StringSet) Set(s string) error {
	*set = make(StringSet)
	if s != "" {
		for _, str := range strings.Split(s, ",") {
			(*set)[str] = struct{}{}
		}
	}
	return nil
}

func (set StringSet) Get() map[string]struct{} {
	return set
}

func (set StringSet) Slice() []string {
	slice := make([]string, 0, len(set))
	for s := range set {
		slice = append(slice, s)
	}
	sort.Strings(slice)
	return slice
}

func (set StringSet) String() string {
	return strings.Join(set.Slice(), ",")
}

func (set StringSet) Clone() StringSet {
	cpy := make(StringSet)
	for elem := range set {
		cpy[elem] = struct{}{}
	}
	return cpy
}
