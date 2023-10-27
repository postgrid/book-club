#ifndef HASH_H_
#define HASH_H_

#include <stdlib.h>

typedef __uint32_t __hash_t;
__hash_t Hash(char *bytes, size_t len);

#endif