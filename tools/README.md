Pre-compiled tools for which source code will be hard to check-in here and then
compile using bazel.

### install_name_tool
An executable for `install_name_tool` compiled from the below source without
any modifications.
https://opensource.apple.com/source/cctools/cctools-973.0.1/

To compile, the Xcode build setting `HEADER_SEARCH_PATH` was changed in
`libstuff.xcconfig` to remove the directory from `DT_TOOLCHAIN_DIR` and use
`/usr/local/Cellar/llvm/11.1.0_1/include` instead.

Source code is covered under Apple Public Source License
Version 2.0, available at https://opensource.apple.com/apsl/.

The executable that ships with Xcode Command Line Tools is of an unknown
version and does not work sufficiently for this project; see
https://developer.apple.com/forums/thread/677884.
