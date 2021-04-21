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
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

func parseDCFFromPath(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	fields, err := parseDCF(f)
	if err != nil {
		return fields, fmt.Errorf("parsing %q: %w", path, err)
	}
	return fields, nil
}

// Parses the DESCRIPTION file of R packages, which are formatted as Debian
// Control Files. In R, the relevant function to parse these files is read.dcf.
func parseDCF(r io.Reader) (map[string]string, error) {
	fields := make(map[string]string)
	s := bufio.NewScanner(r)
	var key, value string
	for s.Scan() {
		line := s.Text()
		if line == "" {
			// R only allows one DCF paragraph, so we can safely skip any blank lines
			// as leading or trailing lines.
			continue
		}
		if line[0] == ' ' || line[0] == '\t' {
			// Continuation line.
			if key == "" {
				// Can not have a continuation line without a key.
				return fields, fmt.Errorf("can not start file with a continuation line")
			}
			// Standardize all continuation space as ' '.
			line = strings.TrimSpace(line)
			if value != "" {
				value += " " + line
			} else {
				value = line
			}
		} else {
			// New key.
			if key != "" {
				fields[key] = value
			}
			elements := strings.SplitN(line, ":", 2)
			if len(elements) != 2 {
				return fields, fmt.Errorf("bad line: %q has no ':'", line)
			}
			key, value = strings.TrimSpace(elements[0]), strings.TrimSpace(elements[1])
			if key == "" {
				return fields, fmt.Errorf("bad line: %q has an empty key", line)
			}
		}
	}
	if key != "" {
		fields[key] = value
	}
	if s.Err() != nil {
		return fields, fmt.Errorf("scanning lines: %w", s.Err())
	}
	return fields, nil
}

var pkgRexp = regexp.MustCompilePOSIX("^[[:space:]]*([^[:space:]]+)([[:space:]]+\\(.*\\))?[[:space:]]*$")

func parseDeps(depsLine string) ([]string, error) {
	var deps []string
	for _, dep := range strings.Split(depsLine, ",") {
		if dep == "" {
			continue
		}
		matches := pkgRexp.FindStringSubmatch(dep)
		if len(matches) == 0 {
			return nil, fmt.Errorf("unable to parse R package dependency %q", dep)
		}
		dep = matches[1]
		if dep != "" {
			deps = append(deps, matches[1])
		}
	}
	return deps, nil
}

func readExcludePatterns(paths []string) ([]*regexp.Regexp, error) {
	var patterns []*regexp.Regexp
	for _, path := range paths {
		pats, err := readLinesFromPath(path)
		if err != nil {
			return nil, err
		}
		for _, pat := range pats {
			pat = strings.TrimSpace(pat)
			if pat == "" {
				continue
			}
			r, err := regexp.Compile(`(?i)` + pat)
			if err != nil {
				return nil, fmt.Errorf("in %q, can not compile regular expression %q", path, pat)
			}
			patterns = append(patterns, r)
		}
	}
	return patterns, nil
}

func readLinesFromPath(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	lines, err := readLines(f)
	if err != nil {
		return lines, fmt.Errorf("reading %q: %w", path, err)
	}
	return lines, err
}

func readLines(r io.Reader) ([]string, error) {
	s := bufio.NewScanner(r)
	var lines []string
	for s.Scan() {
		lines = append(lines, s.Text())
	}
	return lines, s.Err()
}

func listFiles(dirPath string) ([]string, error) {
	dirPath = filepath.Clean(dirPath)
	var paths []string
	err := filepath.Walk(dirPath,
		func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.IsDir() {
				return nil
			}
			if strings.HasPrefix(path, dirPath+string(filepath.Separator)) {
				path = path[(len(dirPath) + 1):]
			}
			paths = append(paths, path)
			return nil
		})
	return paths, err
}
