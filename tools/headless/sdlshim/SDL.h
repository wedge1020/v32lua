#pragma once
#include <stdlib.h>
#include <string.h>
static inline int SDL_Init(unsigned){return 0;}
static inline void SDL_Quit(void){}
static inline char* SDL_GetBasePath(void){return strdup("./");}
static inline void SDL_free(void*p){free(p);}
