cmd_args <- commandArgs(trailingOnly=TRUE)

flag_idx <- startsWith(cmd_args, "--")
cmd_flags <- cmd_args[flag_idx]
cmd_args <- cmd_args[!flag_idx]

if (!all(grepl("^--.+=.+$", cmd_flags))) {
  stop("all flags must be of form --flag=value")
}

# Check if an output_dir was specified.
output_dir <- NULL
if (length(cmd_args) > 0) {
  output_dir <- tail(cmd_args, 1)
  # All other cmd_args are discarded.
}

# Set up the environment for evaluating the expressions in the flags.
eval_env <- new.env(parent = baseenv())
assign("output_dir", output_dir, eval_env)

# Get a named list of flags.
cmd_flags <- substring(cmd_flags, 3)  # Remove the '--' prefix.
cmd_flags_list <- eval(parse(text = paste0("list(", paste(cmd_flags, collapse = ", "), ")")),
                       envir = eval_env)

# Check that some forbidden arguments were not supplied as flags.
if (any(c("{input_argument}", "{output_dir_argument}") %in% names(cmd_flags_list))) {
  stop("input and output_dir arguments can not be supplied as flags")
}

# Check that some forbidden arguments were not supplied as render_args.
build_flags_list <- eval(parse(text = paste0("list({render_args})")),
                         envir = eval_env)
if (any(c("{input_argument}", "{output_dir_argument}") %in% names(build_flags_list))) {
  stop("input and output_dir arguments can not be supplied as render_args")
}

# Construct arguments to render function.
input <- normalizePath('{src}')
function_args <- list({input_argument}=input, {output_dir_argument}=output_dir)
function_args <- c(function_args, build_flags_list, cmd_flags_list)

# Retain only the last element with a given name.
function_args <- rev(function_args)[unique(names(function_args))]

# When the source directory is read-only, and when latexmk will be used, i.e.
# when the output_format is pdf, dvi, ps, etc., the output_directory argument
# needs to be set explicitly.
# See https://github.com/rstudio/rmarkdown/issues/1615.
if ("{render_function}" == "rmarkdown::render") {
    options(tinytex.output_dir = output_dir)
    options(tinytex.engine_args = sprintf("'--output-directory=%s'", output_dir))
}

# Actually render.
message("Calling {render_function} with arguments: ", list(function_args), "\n")
do.call({render_function}, function_args)
