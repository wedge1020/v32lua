#!/usr/bin/env bash
##
## run_tests.sh - automate unit test validation
##
##############################################################################

##############################################################################
##
## Declare variables 
##
UNIT=$(echo "${1}" | cut -d'.' -f1)
COMPILE="../bin/v32lua"
COMPILE="v32lua"
CFLAGS="-w -g"
ASSEMBLE="assemble"
AFLAGS="-g program"
PACKAGE="packrom"
PFLAGS=
RUNEVAL="v32sim"
RFLAGS="-C ${UNIT}.cmd"

if [ -r "${UNIT}.lua" ]; then
	echo "building ${UNIT}:"
	echo "==============================================================="
	printf "compiling:  %30s (lua->asm)  ... " "${UNIT}"
	${COMPILE}  ${CFLAGS} -o ${UNIT}.asm  ${UNIT}.lua && echo "OK" || echo "FAIL"
	printf "assembling: %30s (asm->vbin) ... " "${UNIT}"
	${ASSEMBLE} ${AFLAGS} -o ${UNIT}.vbin ${UNIT}.asm && echo "OK" || echo "FAIL"
	printf "packaging:  %30s (vbin->v32) ... " "${UNIT}"
	${PACKAGE}  ${PFLAGS} -o ${UNIT}.v32  ${UNIT}.xml && echo "OK" || echo "FAIL"
	
	echo -n                             >  ${UNIT}.cmd
	for entry in `cat ${UNIT}.asm | grep 'define.*var_' | sed 's/^%define  var_\([^ ][^ ]*\) *\(0x[0-9A-F][0-9A-F]*\)$/\1:\2/g'`; do
		name=$(echo  "${entry}" | cut -d':' -f1)
		value=$(echo "${entry}" | cut -d':' -f2)
		dtype=$(echo "${name}"  | cut -d'_' -f1)
		if [ "${dtype}" = "number" ]; then
			echo "d/f ${value} ${name}" >> ${UNIT}.cmd
		elif [ "${dtype}" = "string" ]; then
			echo "d/s ${value} ${name}" >> ${UNIT}.cmd
		elif [ "${dtype}" = "boolean" ]; then
			echo "d/B ${value} ${name}" >> ${UNIT}.cmd
		else 
			echo "invalid data type: ${dtype}"
			exit 1
		fi
		echo "c"                        >> ${UNIT}.cmd
	done
	${RUNEVAL} ${RFLAGS} ${UNIT}.v32    >  ${UNIT}.out
	cat ${UNIT}.out
else
	echo "ERROR: ${UNIT} not found/readable"
fi
