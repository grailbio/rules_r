# Copyright 2018 The Bazel Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# `rbe_r_jessie` is a Docker image that can remotely execute Bazel actions that
# depend on a system installation of R.
# - distribution: Debian 8 (Jessie)
# - C/C++ compiler: clang (but gcc is also there)
# - Fortran compiler: gfortran
# - R: 3.5.0 (without recommended packages)
# - Additional system dependencies often used by R packages:
# libssl-dev libxml2-dev libcurl4-openssl-dev

# TODO: maybe replace with https://github.com/GoogleCloudPlatform/distroless?

####################################################################################################
# From https://github.com/bazelbuild/bazel-toolchains/blob/master/examples/debian8_clang/Dockerfile
####################################################################################################
FROM gcr.io/cloud-marketplace/google/clang-debian8@sha256:213da2494bb763f55363213db45d9bfa5eb906039fc02e6cb2e6637dc4917caf

# Install Java
RUN echo 'deb http://httpredir.debian.org/debian jessie-backports main' > /etc/apt/sources.list.d/jessie-backports.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates-java=20161107'*' \
     openjdk-8-jre-headless \
     openjdk-8-jdk-headless \
  && apt-get clean \
  && rm /var/lib/apt/lists/*_*

# Install Bazel deps
RUN apt-get update && apt-get install -y --no-install-recommends \
  curl \
  pkg-config \
  python \
  unzip  \
  zip && \
  rm -rf /var/lib/apt/lists/*

####################################################################################################
# From https://github.com/rocker-org/rocker/blob/629c6f89d81a336a7fa6a8a18f8365f1fd2878be/r-base/Dockerfile
####################################################################################################

RUN apt-get update \ 
	&& apt-get install -y --no-install-recommends \
		ed \
		less \
		locales \
		vim-tiny \
		wget \
		ca-certificates \
		fonts-texgyre \
	&& rm -rf /var/lib/apt/lists/*

## Configure default locale, see https://github.com/rocker-org/rocker/issues/19
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
	&& locale-gen en_US.utf8 \
	&& /usr/sbin/update-locale LANG=en_US.UTF-8

ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8

RUN echo "deb [trusted=yes] http://cloud.r-project.org/bin/linux/debian jessie-cran35/" >> /etc/apt/sources.list

## Now install R and littler, and create a link for littler in /usr/local/bin
## Also set a default CRAN repo, and make sure littler knows about it too
## NB '-t unstable' paused to allow drr35 repo to supply current ones
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		r-base \
		r-base-dev \
	&& rm -rf /tmp/downloaded_packages/ /tmp/*.rds \
	&& rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64
ENV CC /usr/local/bin/clang
ENV GOPATH /go

####################################################################################################

# Common system dependencies for many R packages.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    pkgconf libssl-dev libxml2-dev libcurl4-openssl-dev
