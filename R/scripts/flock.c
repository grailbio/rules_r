// Copyright 2018 The Bazel Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Uses the given file descriptor to acquire an exclusive non-blocking lock.

// The lock is released when the file descriptor is closed, i.e. when the
// parent process that opened the corresponding file is terminated for any
// reason. A SIGKILL to the parent process might have a delay of a few
// seconds, but everything else is instantaneous.

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>

int main(int argc, char** argv) {
  int fd;

  if (argc != 2) {
    fprintf(stderr, "Usage: %s [fd]\n", argv[0]);
    exit(EXIT_FAILURE);
  }

  fd = (int)strtol(argv[1], (char**)NULL, 10);
  errno = 0;
  if (errno != 0) {
    perror("strtol");
    exit(EXIT_FAILURE);
  }

  if (flock(fd, LOCK_EX | LOCK_NB)) {
    if (errno != EAGAIN) {
      perror("flock");
    }
    exit(EXIT_FAILURE);
  }

  return 0;
}
