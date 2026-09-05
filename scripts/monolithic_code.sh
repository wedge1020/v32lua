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

RUNTIME_UNITS="memory datetime exec table string print iters"
RUNTIME_UNITS="${RUNTIME_UNITS} vircon32 pico8 tic80"
RUNTIME_UNITS="${RUNTIME_UNITS} constant"

echo -n                                                      >  put/runtime.s.txt
for unit in ${RUNTIME_UNITS}; do
	cat src/runtime/${unit}.s                                >> put/runtime.s.txt
done

exit 0
