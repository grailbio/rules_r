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
	"fmt"
	"strings"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestParseDCF(t *testing.T) {
	testCases := []struct {
		name    string
		dcf     string
		want    map[string]string
		wantErr error
	}{
		{
			"EmptyFile",
			"",
			map[string]string{},
			nil,
		},
		{
			"SingleField",
			"A: 1",
			map[string]string{"A": "1"},
			nil,
		},
		{
			"MultipleFields",
			"A: 1\nB: 2",
			map[string]string{"A": "1", "B": "2"},
			nil,
		},
		{
			"ContinuationLines",
			"A: 1\nB: 2a\n 2b\n\t2c\n\t\t2d",
			map[string]string{"A": "1", "B": "2a 2b 2c 2d"},
			nil,
		},
		{
			"ContinuationLinesWithEmptyFirstLine",
			"A: 1\nB:\n 2a\n\t2b",
			map[string]string{"A": "1", "B": "2a 2b"},
			nil,
		},
		{
			"EmptyLine",
			"A: 1\n\n",
			map[string]string{"A": "1"},
			nil,
		},
		{
			"ContinuationWithoutKey",
			" 1",
			map[string]string{},
			fmt.Errorf("can not start file with a continuation line"),
		},
		{
			"EmptyKey",
			": 1",
			map[string]string{},
			fmt.Errorf(`bad line: ": 1" has an empty key`),
		},
		{
			"InvalidKV",
			"A 1",
			map[string]string{},
			fmt.Errorf(`bad line: "A 1" has no ':'`),
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			got, gotErr := parseDCF(strings.NewReader(testCase.dcf))
			if diff := cmp.Diff(gotErr, testCase.wantErr, cmp.Comparer(compareErrs)); diff != "" {
				t.Fatalf("unexpected error (-got, +want):\n%s", diff)
			}
			if diff := cmp.Diff(got, testCase.want); diff != "" {
				t.Fatalf("unexpected fields (-got, +want):\n%s", diff)
			}
		})
	}
}

func TestParseDeps(t *testing.T) {
	testCases := []struct {
		text string
		want []string
	}{
		{"R ", []string{"R"}},
		{" R", []string{"R"}},
		{" R ", []string{"R"}},
		{"R (>3.4)", []string{"R"}},
	}

	for i, testCase := range testCases {
		got, err := parseDeps(testCase.text)
		if err != nil {
			t.Errorf("test %d: unexpected error: %v", i, err)
		}
		if diff := cmp.Diff(got, testCase.want); diff != "" {
			t.Errorf("test %d: (-got, +want):\n%s", i, diff)
		}
	}
}

func compareErrs(e1, e2 error) bool {
	if (e1 == nil) != (e2 == nil) {
		return false
	}
	return e1 == nil || e1.Error() == e2.Error()
}
