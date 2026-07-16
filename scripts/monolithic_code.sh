#/usr/bin/env bash

cat inc/v32lua.h | grep -v '#include \"' | grep -v '#endif'  >  v32lua.h

for inc in `cat inc/v32lua.h | grep '^#include \"' | cut -d'"' -f2`; do
	echo "// =========================================="     >> v32lua.h
	echo "// ${inc}                                    "     >> v32lua.h
	echo "// =========================================="     >> v32lua.h
	cat inc/${inc} | grep -v '#include'                      >> v32lua.h
	echo                                                     >> v32lua.h
done
echo "#endif"                                                >> v32lua.h

echo "//"                                                    >  v32lua.c
echo "// v32lua - lua compiler written in C"                 >> v32lua.c
echo "//          targeting the Vircon32 fantasy console"    >> v32lua.c
echo "//"                                                    >> v32lua.c
echo "/////////////////////////////////////////////////////" >> v32lua.c
echo                                                         >> v32lua.c
echo '#include "v32lua.h"'                                   >> v32lua.c
echo                                                         >> v32lua.c
for src in `/bin/ls -1 src/*.c`; do
	echo "// =========================================="     >> v32lua.c
	file=$(echo "${src}" | cut -d '/' -f2)
	echo "// ${file}"                                        >> v32lua.c
	echo "// =========================================="     >> v32lua.c
	cat ${src} | grep -v '#include'                          >> v32lua.c
	echo                                                     >> v32lua.c
done

exit 0
