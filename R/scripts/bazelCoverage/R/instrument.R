# Copyright 2018 The Bazel Authors.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#' Instrument all the functions within an environment.
#'
#' This is a copy of covr:::trace_environment with an option not to clear
#' counters at the beginning.
trace_environment <- local(
  # The following lines requires covr to be imported ("Depends:" entry in
  # the DESCRIPTION file), not merely depended upon (via "Imports:").
  envir = .getNamespace("covr"),
  function(env, clear_counters=TRUE) {
    if (clear_counters) {
      clear_counters()
    }

    the$replacements <- compact(c(
      replacements_S4(env),
      replacements_RC(env),
      replacements_R6(env),
      lapply(ls(env, all.names = TRUE), replacement, env = env)))

    lapply(the$replacements, replace)
  }
)