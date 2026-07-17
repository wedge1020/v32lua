#ifndef __INTERNALS_H
#define __INTERNALS_H

extern int  w_mainwait;

void  compiler_error   (ErrorType, int, const char *, ...);
void  compiler_warning (ErrorType, int, const char *, ...);

#endif
