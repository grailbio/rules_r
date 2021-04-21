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
	"log"
	"path"
	"sort"
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/repo"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

const rName = "R"

type pkgImports struct {
	pkgName                   string
	pkgDeps, pkgSuggestedDeps []string
}

func (rLang) Name() string {
	return rName
}

func (rLang) Imports(_ *config.Config, r *rule.Rule, f *rule.File) []resolve.ImportSpec {
	if r.Kind() != "r_pkg" {
		return nil
	}
	pkgName := pkgName(r, f)
	return []resolve.ImportSpec{{
		Lang: rName,
		Imp:  pkgName,
	}}
}

func (rLang) Embeds(*rule.Rule, label.Label) []label.Label {
	return nil
}

func (rLang) Resolve(c *config.Config, ix *resolve.RuleIndex, _ *repo.RemoteCache,
	r *rule.Rule, imports interface{}, from label.Label) {
	pkgImports := imports.(pkgImports)
	pkgLabels := resolveRDeps(c, ix, from, []string{pkgImports.pkgName})
	pkgDeps := resolveRDeps(c, ix, from, pkgImports.pkgDeps)
	pkgSuggestedDeps := resolveRDeps(c, ix, from, pkgImports.pkgSuggestedDeps)

	if len(pkgLabels) != 1 {
		panic(fmt.Sprintf("package %q must have exactly 1 label, but got %#v", pkgImports.pkgName, pkgLabels))
	}
	pkgLabel := pkgLabels[0]

	switch r.Kind() {
	case "r_pkg":
		// Do nothing.
	case "r_unit_test", "r_pkg_test":
		r.SetAttr("pkg", pkgLabel)
	case "r_library":
		switch r.Name() {
		case "library":
			r.SetAttr("pkgs", []string{pkgLabel})
		case "deps":
			if len(pkgDeps) > 0 {
				r.SetAttr("pkgs", pkgDeps)
			} else {
				r.DelAttr("pkgs")
			}
		case "suggested_deps":
			if len(pkgSuggestedDeps) > 0 {
				r.SetAttr("pkgs", pkgSuggestedDeps)
			} else {
				r.DelAttr("pkgs")
			}
		}
	default:
		log.Printf("unknown rule kind %s for resolve step", r.Kind())
	}
}

func resolveRDeps(c *config.Config, ix *resolve.RuleIndex, from label.Label, deps []string) []string {
	var labels []string
	rCfg := getRConfig(c)
	for _, dep := range deps {
		// TODO: Use FindRulesByImportWithConfig when we update minimum gazelle version.
		res := ix.FindRulesByImport(resolve.ImportSpec{Lang: rName, Imp: dep}, rName)
		if len(res) == 0 {
			// External dependency.
			labels = append(labels, "@"+rCfg.externalDepPrefix+strings.ReplaceAll(dep, ".", "_"))
			continue
		}
		if len(res) > 1 {
			log.Printf("multiple resolutions found for R package %q: %#v", dep, res)
		}
		label := res[0].Label
		if label.Name == "" {
			// This can happen when the label name is not a string constant in the
			// BUILD file. So let's use a heuristic to guess the label name.
			label.Name = path.Base(label.Pkg)
		}
		labels = append(labels, label.Rel(from.Repo, from.Pkg).String())
	}
	sort.Strings(labels)
	return labels
}
