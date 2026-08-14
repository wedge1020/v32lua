#!/usr/bin/env bash
##
## run_tests.sh - automate unit test validation
##
##############################################################################

##############################################################################
##
## Declare/define pass() function
##
function pass()
{
    [ "${DEBUG}" = "true" ] && echo "OK"
}

##############################################################################
##
## Declare/define fail() function 
##
function fail()
{
    echo "FAIL"
    echo "---------------------------------------------------------------"
    exit
}

##############################################################################
##
## Declare variables 
##
[ -z "${DEBUG}" ] && DEBUG="false" || DEBUG="true"
UNIT=$(echo "${1}" | cut -d'.' -f1)
COMPILE="../bin/v32lua"
COMPILE="v32lua"
CFLAGS="-w -g"
ASSEMBLE="assemble"
AFLAGS="-g program"
PACKAGE="packrom"
PFLAGS=
RUNEVAL="v32sim"
RFLAGS="-r -C ${UNIT}.cmd -L lua"

if [ -r "${UNIT}.lua" ]; then
    echo    "==============================================================="
    if [ "${DEBUG}" = "true" ]; then
        echo    "building ${UNIT}: "
        echo    "---------------------------------------------------------------"
    else
        printf "evaluating %46s: " "${UNIT}"
    fi
    [ "${DEBUG}" = "true" ] && printf "compiling:  %30s (lua->asm)  ... " "${UNIT}"
    ${COMPILE}  ${CFLAGS} -o ${UNIT}.asm  ${UNIT}.lua 2>  ${UNIT}.err && pass || fail
    [ "${DEBUG}" = "true" ] && printf "assembling: %30s (asm->vbin) ... " "${UNIT}"
    ${ASSEMBLE} ${AFLAGS} -o ${UNIT}.vbin ${UNIT}.asm 2>  ${UNIT}.err && pass || fail
    [ "${DEBUG}" = "true" ] && printf "packaging:  %30s (vbin->v32) ... " "${UNIT}"
    ${PACKAGE}  ${PFLAGS} -o ${UNIT}.v32  ${UNIT}.xml 2>  ${UNIT}.err && pass || fail
    
    #if [ "${DEBUG}" = "true" ]; then
    #    echo    "---------------------------------------------------------------"
    #fi

    echo -n                             >  ${UNIT}.cmd
    for entry in `cat ${UNIT}.asm | grep 'define.*var_.*_' | sed 's/^%define  var_\([^ ][^ ]*\) *\(0x[0-9A-F][0-9A-F]*\)$/\1:\2/g'`; do
        name=$(echo  "${entry}" | cut -d':' -f1)
        value=$(echo "${entry}" | cut -d':' -f2)
        dtype=$(echo "${name}"  | cut -d'_' -f1)
		#echo "entry: ${entry}, name: ${name}"
        if [ "${dtype}" = "number" ]; then
            echo "d/f ${value} ${name}" >> ${UNIT}.cmd
        elif [ "${dtype}" = "string" ]; then
            echo "d/s ${value} ${name}" >> ${UNIT}.cmd
        elif [ "${dtype}" = "boolean" ]; then
            echo "d/B ${value} ${name}" >> ${UNIT}.cmd
        fi
    done
    #echo "c"                            >> ${UNIT}.cmd

    ulen=$(cat ${UNIT}.lua | wc -l)
    rpos=$(cat -n ${UNIT}.lua | grep 'EXPECTED OUTPUT' | tr -d ' ' | cut -c1-3)
    upos=$((${ulen}-${rpos}))
    tail -${upos} ${UNIT}.lua | grep ':' > ${UNIT}.want
    total=$(cat ${UNIT}.want | wc -l | tr -d ' ')

    ${RUNEVAL} ${RFLAGS} ${UNIT}.v32    >  ${UNIT}.out
    cat ${UNIT}.out | grep ':.*:' | cut -d':' -f2,3 | sed 's/^\([^:]*\):\([^:]*\)$/\2: \1/g' > ${UNIT}.have
    
    
    result=$(diff ${UNIT}.want ${UNIT}.have | grep '<' | wc -l | tr -d ' ')

    if [ "${result}" -eq 0 ]; then 
        passed="${total}"
        #echo "PASSED ${total} out of ${total} tests"
        qual="PASS"
    else
        passed=$((${total}-${result}))
        #echo "PASSED ${passed} out of ${total} tests"
        qual="FAIL"
    fi

    if [ "${DEBUG}" = "true" ]; then
        echo "---------------------------------------------------------------"
    fi

    printf "evaluating: %30s (%2s/%2s)     ... %4s\n" "${UNIT}" "${passed}" "${total}" "${qual}"

    if [ "${qual}" = "FAIL" ] && [ "${DEBUG}" = "true" ]; then
        echo "---------------------------------------------------------------"
        echo "   expected                   | received"
        echo "---------------------------------------------------------------"
        #diff -y ${UNIT}.want ${UNIT}.have | sed 's/\t/    /g' | cut -c1-30 | sed 's/$/|/g' > ${UNIT}.have1
        #diff -y ${UNIT}.want ${UNIT}.have | cut -d'|' -f2 | tr '\t' ' ' > ${UNIT}.want1
        printf "%-30s\n" $(cat ${UNIT}.want | tr ' ' ';') | tr ';' ' ' > ${UNIT}.want1
        paste ${UNIT}.want1 ${UNIT}.have
    fi
    echo "---------------------------------------------------------------"
    #cat ${UNIT}.out

else
    echo "ERROR: ${UNIT} not found/readable"
fi

exit 0
