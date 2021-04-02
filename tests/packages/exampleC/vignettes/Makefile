# Define a custom Makefile to have dummy steps to convert .tex files to .html.
# We do this so that our test setup does not require a Tex installation.
# See https://cran.r-project.org/doc/manuals/r-release/R-exts.html#Writing-package-vignettes
all: html

html: example.html

%.html: %.tex
	cp $< $@
