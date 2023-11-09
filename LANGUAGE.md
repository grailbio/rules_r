# R guide

<!-- Please prefer a markdown editor like Typora when making large changes -->

R originated as a blend between _Scheme_, a functional programming language, and _S_, a statistical computing language. The language specification started as a toy used within a closed-group of statisticians in the early 1990s [1], and grew organically in the public domain from the year 2000. Parts of the language will feel familiar to users of languages like Lisp or Haskell, and other parts will feel familiar to users of software like Matlab.

The language provides very few primitives, and most operators, like `+` or `[` are implemented as functions, which can be overloaded and overridden by users. Given the power and flexibility, it is important that users of the language limit themselves to a known safe set of features, and understand their implications.

For a more comprehensive reading on the language, please see the [official manuals](https://cran.r-project.org/manuals.html). If you are a beginner, start with sections 1-4 of the [R Language Definition](https://cran.r-project.org/doc/manuals/R-lang.html), and follow up with [An Introduction to R](https://cran.r-project.org/doc/manuals/R-intro.html) for general use. If your application is very specific and limited scope, you may choose to skip learning the language and simply use a framework from our third-party dependencies.

At GRAIL, the following is a community agreed set of rules to simplify the language and be consistent in our usage. It is not the aim of this guide to act as a tutorial or a reference.

<a name="toc"></a>

## Table of Contents

- [Language](#language)
  - [Attaching](#attaching)
  - [Variable Sequence Generation](#variable-sequence-generation)
  - [Warnings](#warnings)
  - [Vectors, Indexing and Recycling](#vectors--indexing-and-recycling)
  - [OOP](#oop)
  - [Metaprogramming](#metaprogramming)
  - [Discouraged Functions](#discouraged-functions)
- [Dependencies](#dependencies)
  - [Tidy Evaluation](#tidy-evaluation)
    - [Data Manipulation Verbs](#data-manipulation-verbs)
    - [Pipe Operator](#pipe-operator)
- [Packages](#packages)
- [Style](#style)
  - [Syntax](#syntax)
    - [File Names](#file-names)
    - [Package Names](#package-names)
    - [Object Names](#object-names)
    - [Quotes](#quotes)
    - [Returns](#returns)
    - [Arguments](#arguments)
    - [Errors](#errors)
  - [Formatting](#formatting)
    - [Line Length](#line-length)
    - [Spacing](#spacing)
    - [Code Blocks](#code-blocks)
    - [Comments](#comments)
    - [Roxygen Documentation](#roxygen-documentation)
    - [TODOs](#todos)

---

## Language

[top](#toc)

The following language features are often the subject of opinion and hence we discuss them here. The decisions will gradually become part of our linter rules in Phabricator.

### Attaching

[top](#toc)

Functions like `library`, `attachNamespace`, and `attach` attach objects from their corresponding namespaces or data to the global search space, masking previously attached objects. This is equivalent to the `using namespace` feature in C++, or `import * from ` feature in Python.

An example of how a rogue package can break your code:

```R
# Function defined in roguePkg
`+` <- function(a, b) {"foo"}

# Code in your R package or analysis script
1 + 1 # Returns 2
library(roguePkg)
1 + 1 # Returns "foo"
```

**Pros**: Attaching namespaces and data is convenient and makes the code more compact. This is especially true for common operators.

**Cons**: Although messages are printed on the console listing the objects that were masked by new definitions, these can be easily missed. This makes code behavior dependent on the order or existence of attach operations, which is obviously undesirable.

**Decision**: Avoid attaching as much as you can, and qualify all your objects with the namespace, e.g. `dplyr::mutate`. Attach when you are absolutely sure you are not unintentionally masking. If you do have to attach, in interactive runs, visually inspect the output from your attach operation, and in non-interactive runs, check the output of [base::conflicts](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/conflicts) function. Also, see the _Good Practice_ section on [base::attach](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/attach).

```R
# Bad
library(somePkg)
some_func()

# Good
somePkg::some_func
somePkg::some_var
```

### Variable Sequence Generation

[top](#toc)

A convenient way to generate sequences in R is using the `:` operator, e.g. `1:3`. This section concerns when at least one side of the operator is variable.

**Pros**: It is a much more intuitive way to think that you are _counting_ from `1` to `x`.

**Cons**: This pattern is often misused as a way to get a sequence of length `x` because it gives incorrect results when `x < 1`, because `1:0 == c(1, 0)` which is not the intended result in most cases, where you would expect an empty vector.

**Decision**: Use the [seq](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/seq) family of functions to generate sequences in a reliable way. `seq_along` and `seq_len` are probably the most commonly used, i.e.

1. Use `seq_len(x)` instead of `1:x`
2. Use `seq_along(x)` instead of `1:length(x)`

```R
# Bad
1:x
1:length(y)

# Good
seq_len(x)
seq_along(y)
1:4
1:-2
```

### Warnings

[top](#toc)

R provides separate message and warnings channels, that can be suppressed if the user wants.

**Pros**: Keeping warnings as a separate warnings channel allows you to focus on the details of your analysis.

**Cons**: Warnings are often ignored by users, but they may contain hints about subtle bugs.

**Decision**: In production R code, and in official analysis (presented to an internal audience, etc.), set the warning level to 2 (all warnings become hard errors). In all code, set at least level 1 (all warnings are printed as they happen). Also enable warnings in additional situations when you can. We recommend these set of base R [options](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/options) related to warnings:

```R
options(warn = 2)
options(warnPartialMatchArgs = TRUE)
options(warnPartialMatchAttr = TRUE)
options(warnPartialMatchDollar = TRUE)
```

### Vectors, Indexing and Recycling

[top](#toc)

It pays to keep in mind that there are no scalars in R, and that vectors of insufficient length are recycled in different ways to match the dimensions needed for an operation. Also note that [indexing](https://cran.r-project.org/doc/manuals/R-lang.html#Indexing) in R takes on different semantics in different contexts, and implicit recycling may or may not generate a warning. See this [course lecture](https://eriqande.github.io/rep-res-web/lectures/vectorization_recycling_and_indexing.html) for some examples of these semantics.

**Pros**: These semantics are a convenience for interactive analysis

**Cons**: They are very opaque for ensuring code correctness during code reviews.

**Decision**: Base R does not give you many tools to control these semantics, and it may help to use third-party packages specialized for the problem you are trying to solve. A future version of these guidelines will be more explicit. Some guidelines to help keep you sane in base R:

1. Use `drop = FALSE` as a third argument when indexing a variable number of columns in a data.frame to always consistently get a data.frame back. Without this, single column subsets automatically convert to a column vector.

   ```R
   > df <- data.frame(foo = 1:2, bar = 3:4)

   > df[, "foo"]
   [1] 1 2

   > df[, "foo", drop = FALSE]
     foo
   1   1
   2   2
   ```

2. Be careful when using [logic operators](https://www.rdocumentation.org/packages/base/versions/3.5.3/topics/Logic) in R. The longer form `&&` and `||` are meant to be used only in `if` clauses. It is unfortunate that they do not generate warnings when using them on vectors of length larger than 1.

   ```R
   # Bad
   > c(TRUE, FALSE) && c(TRUE, TRUE)
   [1] TRUE
   > c(FALSE, FALSE) || c(FALSE, TRUE)
   [1] FALSE

   # Good
   > c(TRUE, FALSE) & c(TRUE, TRUE)
   [1]  TRUE FALSE
   > c(FALSE, FALSE) | c(FALSE, TRUE)
   [1] FALSE  TRUE

   # Bad
   > if (x & y) { ... }
   > ifelse(x && y, ..., ...)

   # Good
   > if (x && y) { ... }
   > ifelse(x & y, ..., ...)
   ```

3. Be careful when using the `c` function on lists, as it will flatten its constituents. Prefer explicitly calling the constructor for the appropriate type, e.g. `list` if you don't want this behavior.

   ```R
   # Different behaviors of list concatenation

   > a <- list(one=1, two=2)
   > b <- list(three=3, four=4)

   > class(c(a, b))
   [1] "list"
   > length(c(a, b))
   [1] 4
   > class(c(a, b, recursive=TRUE))
   [1] "numeric"

   > length(list(a, b))
   [1] 2
   ```

4. Be careful in the semantics of the `[[` and the `[` operators. When you want an individual element, always use the `[[` operator. When you want a vector or a list, use the `[` operator. The advantage is that the `[[` operator will check if you are referencing more than one elements. Unfortunately, the converse is not true for the `[` operator.

   ```R
   > x <- as.list(1:2)

   > class(x[[2]])
   [1] "integer"
   > class(x[2])
   [1] "list"

   > class(x[1:2])
   [1] "list"
   > class(x[[1:2]])
   Error in x[[1:2]] : subscript out of bounds
   ```

5. When computing indices, prefer to keep them in logical form rather than numeric form. This allows you to explicitly assert or debug that the length of the indices is the same as the length of the object being indexed. This is especially useful when indices are passed to other contexts where such assertions are not obvious and the user might want to explicitly assert. This rule usually only means that you should not call `which` to convert logical indices into numeric.

6. Set `options(check.bounds = TRUE)` to generate a warning whenever indexing a vector or a list out-of-bounds. Without this option, an out-of-bounds index access returns `NA` silently, and an index write will grow the object automatically to the index you specify filling all intermediate positions as NA. Note that existing code may rely on implicit growth of vectors by indexing, so it may not be feasible for you to set this option globally.

   ```R
   > x <- 1

   # Maybe unintended results
   > x[3] <- 3
   > x
   [1]  1 NA  3
   ```

### OOP

[top](#toc)

R has broadly three object oriented programming systems — S3 and S4 which are implemented from the S language specification, and reference classes (a.k.a. R5) which is implemented in base R and an alternative lightweight implementation provided in the CRAN package R6.

Here, it will suffice to say that base R uses the simpler S3 system, Bioconductor packages use the more complex S4 system, and most other contemporary packages use the R6 system. For a detailed discussion on these systems, see [Advanced R, pt III](https://adv-r.hadley.nz/oo.html).

We propose using the R6 system for GRAIL packages, whenever there is non-trivial complexity.

**Pros**: The R6 system has reference semantics which allows a method on a class to modify its own state and return a value. Moreover, the methods are encapsulated within an object and do not live in the global namespace.

**Cons**: R6 leads to non-idiomatic R code because its semantics are very different from the S language specification.

**Decision**: OOP is not expected to be very common in GRAIL R code. When an OOP system makes sense in new code, prefer R6. Avoid mixing S3 and S4: S4 methods ignore S3 inheritance and vice-versa. Between S3 and S4, prefer S3 for its simplicity.

### Metaprogramming

[top](#toc)

R was designed as an REPL (read-eval-print-loop), which relies on dynamic creation of expressions. R made a design choice in its early days to expose expressions as first class objects to users of the language. This makes it possible to have powerful metaprogramming features, in which code can generate more code dynamically to be evaluated in the interpreter loop. See documentation for [expression](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/expression) and [eval](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/eval), or the [R manual](https://cran.r-project.org/doc/manuals/r-release/R-lang.html#Computing-on-the-language).

Metaprogramming makes code [referentially opaque](https://en.wikipedia.org/wiki/Referential_transparency) and consequently makes it harder to read and reason for correctness. It is so pervasive in R that the two programming styles have been named "Standard Evaluation" and "Nonstandard Evaluation". See [this article](http://developer.r-project.org/nonstandard-eval.pdf) from the early years of R (2003) for a glimpse into its evolution.

For a more detailed reading, see [Advanced R, pt IV](https://adv-r.hadley.nz/metaprogramming.html).

**Pros**: Metaprogramming allows you to define convenient usage patterns in your code. For example, `plot(x, sin(x))` can automatically infer the axes labels to be "x" and "sin(x)" by [deparsing](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/deparse) the arguments. Arguments to functions in packages like dplyr do not have to be valid R symbols, as they can be parsed lazily in a different context, like column names in the context of a table, by the underlying function.

**Cons**: The convenience this adds to the language also brings mysticism to it because it allows multiple domain specific languages (DSL) to be mixed together in the same code. For example, both `data.table` and `dplyr` packages implement their own DSLs which look very different from each other. This makes code extremely hard to read.

**Decision**: Use metaprogramming only when the alternative is much more complex. While this language feature is not difficult to use, it is much better to forsake convenience to be explicit for future users, readers and maintainers of your code. Always favor code correctness, maintainability and an intuitive usage signature over syntactic sugar.

```R
# Hypothetical example of metaprogramming

a <- 1

# Avoid
> my_function <- function(x) sprintf("Value of %s = %d", as.character(substitute(x)), x)
> my_function(a)
[1] "Value of a = 1"

# Prefer
> my_function <- function(x, var_name) sprintf("Value of %s = %d", var_name, x)
> my_function(a, "a")
[1] "Value of a = 1"
```

### Discouraged Functions

[top](#toc)

The following functions from standard packages are discouraged because of unexpected behavior.

1. `base::sample`
   Use `base::sample.int` instead on the indices of the data you want to sample, e.g. `x[sample.int(length(x))]` instead of `sample(x)`. The `sample` function has a convenience feature that leads to undesired behavior when the argument is a single number `> 1`. See Details and Examples in the [documentation](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/sample).
2. `base::subset`
   See warning in the [documentation](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/subset) about caveats with nonstandard evaluation of the argument.

---

## Dependencies

[top](#toc)

"_Dependencies are invitations for other people to break your code_"

R has a thriving ecosystem of community contributions in the form of established package repositories like CRAN and Bioconductor. CRAN [Task Views](https://cran.r-project.org/web/views/) and Bioc [Views](https://www.bioconductor.org/packages/release/BiocViews.html) provide a catalogued view of these ~13,000 packages.

However still, follow the [Tinyverse](http://www.tinyverse.org/) advice and try to keep your dependencies to a minimum; not all available packages are written and maintained to high standards.

Here, we discuss decisions on the usage of some features from the most common packages used at GRAIL.

### Tidy Evaluation

[top](#toc)

https://tidyeval.tidyverse.org/

Tidy Evaluation is a set of principles made possible using metaprogramming. This framework modernizes similar metaprogramming frameworks in base R, and is primarily intended for data transformations without the boilerplate code from standard evaluation. Usual caveats of metaprogramming apply.

#### Data Manipulation Verbs

`dplyr::arrange`, `dplyr::filter`, `dplyr::mutate`, `dplyr::select`, etc.

One of the major objectives of Tidy Evaluation is to make the data your execution environment, extending the idea introduced by the [formula](https://www.rdocumentation.org/packages/stats/versions/3.6.0/topics/formula) interface, and by functions like `base::with` et al. To facilitate this concept, several functions exist in various tidyverse packages that take quoted expressions as arguments.

**Pros**: These functions reduce the boilerplate for the most common uses, when using them without any safety checks.

**Cons**: Use of safety checks (like [quasiquotation](https://dplyr.tidyverse.org/articles/programming.html#quasiquotation) or the [.data pronoun](https://rlang.r-lib.org/reference/tidyeval-data.html)) actually makes the code comparable in verbosity and readability to conventional idioms.

**Decision**:

1. Prefer conventional idioms, if the readability is more or comparable.
2. Use the programming recipes in [Tidy Evaluation cheat sheet](https://github.com/rstudio/cheatsheets/blob/master/tidyeval.pdf) (p. 2), whenever correctness and mantainability of your code are important.
3. Prefer alternative implementations which have cleaner standard evaluation semantics, e.g. the `*_se` variants in the seplyr package ([introduction](https://cran.r-project.org/web/packages/seplyr/vignettes/using_seplyr.html)).

#### Pipe Operator

`` magrittr::`%>%`  ``

Read this [blog post](http://www.win-vector.com/blog/2017/07/in-praise-of-syntactic-sugar/) for some discussion on semantics of the pipe operator, and alternatives.

**Pros**: Great for readability as the code is organized as a flow.

**Cons**: The pipe operator will give different results if your RHS function call uses the current environment, or uses lazy evaluation (see [how it works](https://r4ds.had.co.nz/pipes.html#use-the-pipe)). See Technical Notes in [documentation](https://www.rdocumentation.org/packages/magrittr/versions/1.5/topics/%25%3E%25).

**Decision**:

1. Prefer conventional idioms ([example](https://r4ds.had.co.nz/pipes.html#overwrite-the-original)), if the readability is more or comparable.
2. Do not use the pipe operator in a loop; your code will become [slow](https://stackoverflow.com/a/38882226).
3. Use the operator only when the flow is linear.
4. Break long flows (> 10 steps) by assigning intermediate variable names.
5. Prefer alternative implementations which have cleaner standard evaluation semantics, e.g. the dot pipe operator ([introduction](https://winvector.github.io/wrapr/articles/dot_pipe.html), [technical article](https://journal.r-project.org/archive/2018/RJ-2018-042/RJ-2018-042.pdf)).

---

## Packages

[top](#toc)

R packages provide a namespace scoped collection of functions to other users. This provides much needed encapsulation when distributing your code and using code from other people.

Prefer writing and maintaining your code as an R package. Some useful guidelines:

1. Use the [official R manual](https://cran.r-project.org/doc/manuals/r-release/R-exts.html) as your reference whenever in doubt. All other works are derivations of this document.
2. For GRAIL internal packages, use an empty or dummy License file.
3. Avoid using the `Depends` clause in the DESCRIPTION file for packages. Having package requirements there is used only to automatically attach the package before your package is attached.
4. Avoid importing entire packages in the NAMESPACE file. In Roxygen parlance, avoid using `@import`.
5. Be selective in the symbols you import from other packages in the NAMESPACE file. In almost all cases, you should qualify your symbols with its namespace, e.g. `dplyr::filter` instead of just `filter`, which will remove the need for you to import the symbol. Symbols like `%>%` are worthy exceptions. In Roxygen parlance, this is the `@importFrom` directive.
6. When using Roxygen, collect all package level directives, i.e. package documentation, `@importFrom` directives, etc., above a single symbol (typically `NULL` or `"_PACKAGE"`), usually in the file `zzz.R`.
7. Write unit tests for your package when possible. Any executable file in the tests directory is considered a test. The preferred unit testing framework at GRAIL is `testthat`.

---

## Style

[top](#toc)

This section focuses on consistency in coding style as opposed to the focus on avoiding error-prone coding style as in the language section above.

The GRAIL style guide is based on the [Tidyverse style guide](https://style.tidyverse.org), which is a stricter set than the [Hadley style guide](http://adv-r.had.co.nz/Style.html), which in turn is based on the [Google style guide](https://google.github.io/styleguide/Rguide.xml).

Notable observations and exceptions are listed below.

### Syntax

[top](#toc)

#### File Names

1. Use lower case alphabets and hyphens (-) only.
2. Use capital R in all relevant file extensions (.R, .Rmd, .Rdata, .Rds, etc.)
3. For scripts meant to be run sequentially, prefix with left padded numbers, e.g. `00_setup.sh`, `01_preprocess.sh`, etc.

```
# Bad
import_data.R  # "_" should be "-"
importData.R   # Should not be camel case
import-data.r  # Should be "import-data.R" with upper case "R"

# Good
import-data.R
```

#### Package Names

1. Keep them clear and short, in that order.
2. Use all lower case letters, no punctuation.
3. If the name references a GRAIL project that is a somewhat unique name, say 'ccga', then do not prefix 'grail'. Only prefix when you think there may be a name collision with a public package from CRAN, etc.
4. Do not suffix the package name with 'r' if it does not make sense. This is in contrast with the Tidyverse guideline which says that you should suffix with 'r'.

```
# Bad
grailwgcnar     # Do not use the r suffix.
grailstriveadsl # STRIVE is already a GRAIL project.
StriveADSL      # Do not use mixed case.

# Good
grailwgcna      # Use of grail prefix OK because file is too generic.
striveadsl
```

#### Object Names

1. Keep them clear and short, in that order.
2. Use snake case (all lower case, words separated by underscore).
3. Try to use verbs for function names and nouns for others.
4. Do not reuse exported names from default packages that are attached on startup (base, stats, etc.). Use a syntax highlighter to guide yourself on which symbols are exported from the default packages.

```R
# Bad

# Not following snake case; all the below should be day_one.
DayOne
dayone
day.one

# Too long or too cryptic.
first_day_of_the_month
djm1

# Overriding symbols from default packages.
T <- FALSE
c <- 10
mean <- function(x) sum(x)
```

#### Quotes

1. Be consistent in your usage of quotes, at least in the same file, and preferably in your package. Either use double quotes, or single quotes.

#### Returns

1. Prefer using `return` explicitly, especially in longer functions. This is in contrast with the Google style guide which says you should use `return` only when you are using imperative style programming, i.e. using control flow operations. At GRAIL, we prefer to be consistent and not ask the user to be cognizant of which style a partiicular function is following because it is easy to mix the two.
2. For functions that return an object that you do not want printed on the console, wrap your object in `invisible`.
3. For side-effect functions that do not return anything, prefer using `return(invisible(NULL))` .

#### Arguments

1. Omit argument names if usage is obvious, but be explicit otherwise.
2. Do not use partial matching of argument names, e.g. `val = TRUE` instead of `value = TRUE`.
3. Set default values for arguments only when the default conveys a meaning. For example, a default value of `NULL` rarely conveys a meaning. Use `base::missing` otherwise to check if an argument was set or not.
4. Use `match.arg` ([documentation](https://www.rdocumentation.org/packages/base/versions/3.6.0/topics/match.arg)) when you want your argument to accept one of a finite set of possible values.

#### Errors

1. In non-testing code, raise all errors with `stop` or `stopifnot`.
2. Use `tryCatch` judiciously.

### Formatting

[top](#toc)

#### Line Length

1. Less than 100 characters.
2. OK to exceed for long strings that do not naturally break; it is better than pasting parts of the string together.

#### Spacing

1. Use two spaces as indent. Never use tabs or mix tabs and spaces.
   Exception: When a line break occurs inside parentheses, align the wrapped line with the first character inside the parenthesis, or use 4 characters as indent on next line.
2. Place spaces around all infix operators (`=`, `+`, `-`, `<-`, etc.).
   Exception: Spaces around `=`s are optional (but preferred) when passing parameters in a function call.
3. Do not place a space before a comma, but always place one after a comma.
   Exception: This rule is a paradox when there are consecutive commas.
4. Extra spacing (i.e., more than one consecutive space) is OK if it improves alignment.
5. Do not place spaces around code in parentheses or square brackets.

#### Code Blocks

1. Use `{` as last character on the line (except comments), and `}` as first non-indent character on the line.
2. Do not use semicolons.
3. Inline statements (no `{}`) are OK for short, simple expressions without control flow operations.
4. Surround else with braces.

#### Comments

1. Entire commented lines should begin with `#` and one space.
2. Short comments can be placed after code preceded by two spaces, `#`, and then one space.
3. Comments can be added between piped operations when the purpose of an operation is not obvious.

#### Roxygen Documentation

1. Title is a single sentence in sentence case, without a period at the end. Separate from the next documentation block with one blank line.
2. Description can be multiple paragraphs. Separate from the next documentation block with one blank line.
3. Parameters are a single block with each parameter description starting with a lower case letter and ending in a period. Multi-line parameter descriptions should be indented 2 extra spaces or aligned with the lines above. When aligning, align all parameter descriptions the same way.
4. No blank lines are needed between the function definition and the last documentation block.
5. Have at least one space between `#'` and the text.

```R
# Good

#' Get best labels after collapsing multiple labels into a group.
#'
#' Given a set of multiclass predictions per sample and a mapping from fine-grained
#' multiclass labels to a set of more high-level labels, finds the high-level
#' label w/ the highest score.
#'
#' @param too_scores a data.frame w/ sample scores: must have an accession_id
#'        column; multiclass score columns must have the same labels as too_class
#'        column in too_labels_map.
#' @param too_labels_map a data.frame w/ too_class, full_name columns where
#'        too_class represents a fine-grained set of class labels and full_name
#'        aggregates/translates too_class labels to a smaller set of human-readable
#'        class labels.
#' @return data.frame with accession_id, predicted_label with a row per sample.
#' @export
get_best_label <- function(too_scores, too_labels_map) { ... }
```

#### TODOs

1. Use a consistent style for TODOs throughout your code.
   `TODO(username): Explicit description of action to be taken`

## Open Questions

1. Pros and cons of `tibble` as an alternative to `data.frame`. Looks like accessing non-existent columns generate a warning, and `drop=FALSE` is default.
2. Performance benchmarks of Tidy Evaluation compared to alternatives.
3. Preference to single quotes over double quotes for string constants.
4. Generating errors for unintended use of `switch`, `ifelse`, `case_when`, etc.
5. Examples of well formatted code blocks.

---

[1]: Thieme, N. (2018), R generation. Significance, 15: 14-19. doi:[10.1111/j.1740-9713.2018.01169.x](https://doi.org/10.1111/j.1740-9713.2018.01169.x)
