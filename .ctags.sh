#!/bin/sh
find ./ -path ./build -prune -o \
  \( -name '*.c' -o -name '*.h' \
     -o -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \
     -o -name '*.hpp' -o -name '*.hxx' \
     -o -name '*.C' -o -name '*.s' -o -name '*.S' \
     -o -name 'Makefile' -o -name 'rules' -o -name 'make*' \
  \) -print > cscope.files
cscope -Rbq -i cscope.files
ctags -R --exclude=.svn
