# Try to get the output directory from the command line, if present.
args <- commandArgs(trailingOnly=TRUE)
output_dir <- NULL
if (length(args) == 1) {
  output_dir <- args[1]
} else if (length(args) > 1) {
  stop("at most one argument expected as output directory")
}

input <- normalizePath('{src}')
{render_function}({input_argument}=input, {output_dir_argument}=output_dir{render_args})
