Gazelle Extension for R
=====

The Go library in this directory provides an extension to the
[Gazelle][gazelle] build file generator. This can be used in lieu of the [razel
R script][scripts] for generating BUILD files for individual packages in your
repo.

`r_repository` and `r_repository_list` continue to use razel for generating
BUILD files as the Gazelle extension is tuned more towards the end user.

Please see the [Extending Gazelle][gazelle-extending] guide on how to integrate
this with your Gazelle binary.

When integrated, the Gazelle binary will have additional flags that will
control the global behavior for this extension. These flags are:
<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Flags</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>r_generate_rules</code></td>
      <td>
        <p><code>Bool, default true</code></p>
        <p>Enable rule generation for R language.</p>
      </td>
    </tr>
    <tr>
      <td><code>r_external_dep_prefix</code></td>
      <td>
        <p><code>String; default "R_"</code></p>
        <p>Prefix to append to repo names of external packages.</p>
      </td>
    </tr>
    <tr>
      <td><code>r_add_test_rules</code></td>
      <td>
        <p><code>Bool; default true</code></p>
        <p>Whether to add r_unit_test and r_pkg_test rules.</p>
      </td>
    </tr>
    <tr>
      <td><code>r_installed_pkgs</code></td>
      <td>
        <p><code>String; default "base,compiler,datasets,graphics,grDevices,grid,methods,parallel,splines,stats,stats4,tcltk,tools,translations,utils"</code></p>
        <p>R packages that are to be assumed installed on the build machine (comma-separated).</p>
      </td>
    </tr>
    <tr>
      <td><code>r_srcs_use_globs</code></td>
      <td>
        <p><code>Bool; default false</code></p>
        <p>Whether to use glob expressions for the srcs attribute.</p>
      </td>
    </tr>
    <tr>
      <td><code>r_roclets</code></td>
      <td>
        <p><code>String; ""</code></p>
        <p>The roclets to run for building the source archive (comma-separated).</p>
      </td>
    </tr>
    <tr>
      <td><code>r_roclets_deps</code></td>
      <td>
        <p><code>String; "@R_roxygen2"</code></p>
        <p>Additional dependencies for running roclets (comma-separated).</p>
      </td>
    </tr>
    <tr>
      <td><code>r_roclets_include_pkg_deps</code></td>
      <td>
        <p><code>Bool; default true</code></p>
        <p>Whether to also include pkg deps when running roclets.</p>
      </td>
    </tr>
    <tr>
      <td><code>r_delete_assignments</code></td>
      <td>
        <p><code>String; default ""</code></p>
        <p>(in `gazelle fix` mode only) Delete these variable assignments in
        the BUILD files (comma-separated).</p>
      </td>
    </tr>
  </tbody>
</table>

You can override the global behavior specified by the above flags, through
gazelle directives in BUILD files. Any directive in a BUILD file will apply to
that directory and all its subdirectories. The following directives are
available:

- `r_generate_rules`
- `r_external_dep_prefix`
- `r_add_test_rules`
- `r_srcs_use_globs`
- `r_roclets`
- `r_roclets_deps`
- `r_roclets_include_pkg_deps`

[gazelle]: https://github.com/bazelbuild/bazel-gazelle
[gazelle-extending]: https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.rst
[scripts]: ../scripts
