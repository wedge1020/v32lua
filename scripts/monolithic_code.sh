#/usr/bin/env bash

cat inc/v32lua.h | grep -v '#include \"' | grep -v '#endif'  >  put/v32lua.h

for inc in `cat inc/v32lua.h | grep '^#include \"' | cut -d'"' -f2`; do
	echo "// =========================================="     >> put/v32lua.h
	echo "// ${inc}                                    "     >> put/v32lua.h
	echo "// =========================================="     >> put/v32lua.h
	cat inc/${inc} | grep -v '#include'                      >> put/v32lua.h
	echo                                                     >> put/v32lua.h
done
echo "#endif"                                                >> put/v32lua.h

echo "//"                                                    >  put/v32lua.c
echo "// v32lua - lua compiler written in C"                 >> put/v32lua.c
echo "//          targeting the Vircon32 fantasy console"    >> put/v32lua.c
echo "//"                                                    >> put/v32lua.c
echo "/////////////////////////////////////////////////////" >> put/v32lua.c
echo                                                         >> put/v32lua.c
echo '#include "v32lua.h"'                                   >> put/v32lua.c
echo                                                         >> put/v32lua.c
for src in `/bin/ls -1 src/*.c src/intrinsics/*.c src/node/*.c`; do
	echo "// =========================================="     >> put/v32lua.c
	file=$(echo "${src}" | cut -d '/' -f2)
	echo "// ${file}"                                        >> put/v32lua.c
	echo "// =========================================="     >> put/v32lua.c
	cat ${src} | grep -v '#include'                          >> put/v32lua.c
	echo                                                     >> put/v32lua.c
done

cat src/runtime/memory.s src/runtime/exec.s src/runtime/table.s src/runtime/string.s src/runtime/print.s src/runtime/iters.s src/runtime/vircon32.s src/runtime/pico8.s src/runtime/tic80.s src/runtime/constant.s > put/runtime.s.txt

exit 0
