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
	"flag"
	"log"
	"strconv"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

type rConfig struct {
	generateRules         bool
	externalDepPrefix     string
	addTestRules          bool
	installedPkgs         StringSet
	srcsUseGlobs          bool
	roclets               StringSet
	rocletsDeps           StringSet
	rocletsIncludePkgDeps bool
	deleteAsgnmts         StringSet
}

func newRConfig() *rConfig {
	return &rConfig{
		installedPkgs: map[string]struct{}{
			"base":         {},
			"compiler":     {},
			"datasets":     {},
			"graphics":     {},
			"grDevices":    {},
			"grid":         {},
			"methods":      {},
			"parallel":     {},
			"splines":      {},
			"stats":        {},
			"stats4":       {},
			"tcltk":        {},
			"tools":        {},
			"translations": {},
			"utils":        {},
		},
		rocletsDeps: map[string]struct{}{
			"@R_roxygen2": {},
		},
	}
}

func (rLang) RegisterFlags(fs *flag.FlagSet, cmd string, c *config.Config) {
	rc := newRConfig()
	switch {
	case cmd == "update" || cmd == "fix":
		// TODO: Remove this option when minimum gazelle version is 0.21, at which
		// point one can use the lang directive and flag in gazelle.
		fs.BoolVar(&rc.generateRules,
			"r_generate_rules", true, "Enable rule generation for R language.")
		fs.StringVar(&rc.externalDepPrefix,
			"r_external_dep_prefix", "R_", "Prefix to append to repo names of external packages.")
		fs.BoolVar(&rc.addTestRules,
			"r_add_test_rules", true, "Whether to add r_unit_test and r_pkg_test rules.")
		fs.Var(&rc.installedPkgs,
			"r_installed_pkgs", "R packages that are to be assumed installed on the build machine (comma-separated).")
		fs.BoolVar(&rc.srcsUseGlobs,
			"r_srcs_use_globs", false, "Whether to use glob expressions for the srcs attribute.")
		fs.Var(&rc.roclets,
			"r_roclets", "The roclets to run for building the source archive (comma-separated).")
		fs.Var(&rc.rocletsDeps,
			"r_roclets_deps", "Additional dependencies for running roclets (comma-separated).")
		fs.BoolVar(&rc.rocletsIncludePkgDeps,
			"r_roclets_include_pkg_deps", true, "Whether to also include pkg deps when running roclets.")
		fallthrough
	case cmd == "fix":
		fs.Var(&rc.deleteAsgnmts, "r_delete_assignments", "Delete these variable assignments in the BUILD files (comma-separated).")
	}
	c.Exts[rName] = rc
}

func (rLang) CheckFlags(_ *flag.FlagSet, c *config.Config) error {
	return validateConfig(getRConfig(c))
}

func (rLang) KnownDirectives() []string {
	return []string{
		"r_generate_rules",
		"r_external_dep_prefix", "r_add_test_rules", "r_srcs_use_globs",
		"r_roclets", "r_roclets_deps", "r_roclets_include_pkg_deps"}
}

func (rLang) Configure(c *config.Config, rel string, f *rule.File) {
	if f == nil {
		return
	}
	var rCfg *rConfig
	if raw, ok := c.Exts[rName]; !ok {
		rCfg = newRConfig()
	} else {
		cpy := *raw.(*rConfig)
		// Create copies of slices and maps.
		cpy.roclets = cpy.roclets.Clone()
		cpy.rocletsDeps = cpy.rocletsDeps.Clone()
		rCfg = &cpy
	}
	c.Exts[rName] = rCfg
	for _, d := range f.Directives {
		switch d.Key {
		case "r_generate_rules":
			rCfg.generateRules = parseBoolDirective(d, f.Path)
		case "r_external_dep_prefix":
			rCfg.externalDepPrefix = d.Value
		case "r_add_test_rules":
			rCfg.addTestRules = parseBoolDirective(d, f.Path)
		case "r_srcs_use_globs":
			rCfg.srcsUseGlobs = parseBoolDirective(d, f.Path)
		case "r_roclets":
			rCfg.roclets.Set(d.Value)
		case "r_roclets_deps":
			rCfg.rocletsDeps.Set(d.Value)
		case "r_roclets_include_pkg_deps":
			rCfg.rocletsIncludePkgDeps = parseBoolDirective(d, f.Path)
		}
	}
	err := validateConfig(rCfg)
	if err != nil {
		log.Printf("configuration directives in file %q: %v", f.Path, err)
	}
	return
}

func getRConfig(cfg *config.Config) *rConfig {
	return cfg.Exts[rName].(*rConfig)
}

func validateConfig(rCfg *rConfig) error {
	return nil
}

func parseBoolDirective(d rule.Directive, path string) bool {
	val, err := strconv.ParseBool(d.Value)
	if err != nil {
		log.Printf("in %q, unable to parse bool value for %s: %q", path, d.Key, d.Value)
	}
	return val
}
