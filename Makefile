# Copyright 2015 Google Inc. All rights reserved.
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

################################################################################
# User-servicable parts:
################################################################################

# C/C++ compiler; to use Clang, build with `make CC=clang CXX=clang++`
CXX ?= g++
CC ?= gcc

# Emscripten -- For Jsonnet in the browser
EMCXX ?= em++
EMCC ?= emcc

CP ?= cp
OD ?= od

OPT ?= -O3

PREFIX ?= /usr/local

CXXFLAGS ?= -g $(OPT) -Wall -Wextra -Woverloaded-virtual -pedantic -std=c++0x -fPIC
CXXFLAGS += -Iinclude -Ithird_party/md5 -Ithird_party/json
CFLAGS ?= -g $(OPT) -Wall -Wextra -pedantic -std=c99 -fPIC
CFLAGS += -Iinclude
MAKEDEPENDFLAGS += -Iinclude -Ithird_party/md5 -Ithird_party/json
EMCXXFLAGS = $(CXXFLAGS) -g0 -Os --memory-init-file 0 -s DISABLE_EXCEPTION_CATCHING=0 -s OUTLINING_LIMIT=10000 -s RESERVED_FUNCTION_POINTERS=20 -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1
EMCFLAGS = $(CFLAGS) --memory-init-file 0 -s DISABLE_EXCEPTION_CATCHING=0 -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1
LDFLAGS ?=

SHARED_LDFLAGS ?= -shared

################################################################################
# End of user-servicable parts
################################################################################

LIB_SRC = \
	core/desugarer.cpp \
	core/formatter.cpp \
	core/lexer.cpp \
	core/libjsonnet.cpp \
	core/parser.cpp \
	core/pass.cpp \
	core/static_analysis.cpp \
	core/string_utils.cpp \
	core/vm.cpp \
	third_party/md5/md5.cpp

LIB_OBJ = $(LIB_SRC:.cpp=.o)

LIB_CPP_SRC = \
	cpp/libjsonnet++.cpp

LIB_CPP_OBJ = $(LIB_OBJ) $(LIB_CPP_SRC:.cpp=.o)

BINS = \
	jsonnet \
	jsonnetfmt

LIBS = \
	libjsonnet.so \
	libjsonnet++.so

ALL = \
	libjsonnet_test_snippet \
	libjsonnet_test_file \
	libjsonnet.js \
	doc/js/libjsonnet.js \
	$(BINS) \
	$(LIBS) \
	$(LIB_OBJ)

# public headers
INCS = \
	include/libjsonnet.h \
	include/libjsonnet_fmt.h \
	include/libjsonnet++.h

ALL_HEADERS = \
	core/ast.h \
	core/desugarer.h \
	core/formatter.h \
	core/lexer.h \
	core/parser.h \
	core/state.h \
	core/static_analysis.h \
	core/static_error.h \
	core/string_utils.h \
	core/vm.h \
	core/std.jsonnet.h \
	third_party/md5/md5.h \
	third_party/json/json.hpp \
	$(INCS)


default: $(LIBS) $(BINS)

bins: jsonnet jsonnetfmt
libs: libjsonnet.so libjsonnet++.so

install: bins libs
	mkdir -p $(PREFIX)/bin
	cp $(BINS) $(PREFIX)/bin/
	mkdir -p $(PREFIX)/lib
	cp $(LIBS) $(PREFIX)/lib/
	mkdir -p $(PREFIX)/include
	cp $(INCS) $(PREFIX)/include/

all: $(ALL)

test: jsonnet jsonnetfmt libjsonnet.so libjsonnet_test_snippet libjsonnet_test_file
	./tests.sh

reformat:
	clang-format -i -style=file **/*.cpp **/*.h

test-formatting:
	test "`clang-format -style=file -output-replacements-xml **/*.cpp **/*.h | grep -c "<replacement "`" == 0

MAKEDEPEND_SRCS = \
	cmd/jsonnet.cpp \
	cmd/jsonnetfmt.cpp \
	core/libjsonnet_test_snippet.c \
	core/libjsonnet_test_file.c

depend:
	rm -f Makefile.depend
	for FILE in $(LIB_SRC) $(MAKEDEPEND_SRCS) ; do $(CXX) -MM $(CXXFLAGS) $$FILE -MT $$(dirname $$FILE)/$$(basename $$FILE .cpp).o >> Makefile.depend ; done

core/desugarer.cpp: core/std.jsonnet.h

# Object files
%.o: %.cpp
	$(CXX) -c $(CXXFLAGS) $< -o $@

# Commandline executable.
jsonnet: cmd/jsonnet.cpp cmd/utils.cpp $(LIB_OBJ)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $< cmd/utils.cpp $(LIB_SRC:.cpp=.o) -o $@

# Commandline executable (reformatter).
jsonnetfmt: cmd/jsonnetfmt.cpp cmd/utils.cpp $(LIB_OBJ)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $< cmd/utils.cpp $(LIB_SRC:.cpp=.o) -o $@

# C binding.
libjsonnet.so: $(LIB_OBJ)
	$(CXX) $(LDFLAGS) $(LIB_OBJ) $(SHARED_LDFLAGS) -o $@

libjsonnet++.so: $(LIB_CPP_OBJ)
	$(CXX) $(LDFLAGS) $(LIB_CPP_OBJ) $(SHARED_LDFLAGS) -o $@

# JavaScript build of C binding
JS_EXPORTED_FUNCTIONS = 'EXPORTED_FUNCTIONS=["_jsonnet_make", "_jsonnet_evaluate_snippet", "_jsonnet_fmt_snippet", "_jsonnet_ext_var", "_jsonnet_ext_code", "_jsonnet_tla_var", "_jsonnet_tla_code", "_jsonnet_realloc", "_jsonnet_destroy", "_jsonnet_import_callback"]'

JS_RUNTIME_METHODS = 'EXTRA_EXPORTED_RUNTIME_METHODS=["cwrap", "_free", "getValue", "lengthBytesUTF8", "_malloc", "UTF8ToString", "setValue", "stringToUTF8", "addFunction"]'


libjsonnet.js: $(LIB_SRC) $(ALL_HEADERS)
	$(EMCXX) -s WASM=0 -s $(JS_EXPORTED_FUNCTIONS) -s $(JS_RUNTIME_METHODS) $(EMCXXFLAGS) $(LDFLAGS) $(LIB_SRC) -o $@

# Copy javascript build to doc directory
doc/js/libjsonnet.js: libjsonnet.js
	$(CP) $^ $@

# Tests for C binding.
LIBJSONNET_TEST_SNIPPET_SRCS = \
	core/libjsonnet_test_snippet.c \
	libjsonnet.so \
	include/libjsonnet.h

libjsonnet_test_snippet: $(LIBJSONNET_TEST_SNIPPET_SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) $< -L. -ljsonnet -o $@

LIBJSONNET_TEST_FILE_SRCS = \
	core/libjsonnet_test_file.c \
	libjsonnet.so \
	include/libjsonnet.h

libjsonnet_test_file: $(LIBJSONNET_TEST_FILE_SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) $< -L. -ljsonnet -o $@

# Encode standard library for embedding in C
core/%.jsonnet.h: stdlib/%.jsonnet
	(($(OD) -v -Anone -t u1 $< \
		| tr " " "\n" \
		| grep -v "^$$" \
		| tr "\n" "," ) && echo "0") > $@
	echo >> $@

clean:
	rm -vf */*~ *~ .*~ */.*.swp .*.swp $(ALL) *.o core/*.jsonnet.h Makefile.depend

-include Makefile.depend

.PHONY: default all depend clean reformat test test-formatting
