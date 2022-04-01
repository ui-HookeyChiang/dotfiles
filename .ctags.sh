#!/bin/sh
find ./  -name "*.c" -o -name "*.h" -o -name "*.cpp" -o -name 'Makefile' -o -name 'rules' -o -name 'make*' -o -name '*.cc' -o -name '*.C'-o -name '*.s'-o -name '*.S' > cscope.files
cscope -Rbq -i cscope.files
ctags -R --exclude=.svn
