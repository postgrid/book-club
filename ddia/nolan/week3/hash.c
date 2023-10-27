#include "hash.h"

#include <limits.h>

__hash_t Hash(char *bytes, size_t len)
{
    __hash_t hash = (1 << 31) - 1;
    for (size_t i = 0UL; i < len; ++i)
    {
        const size_t byteShift = i % sizeof(__hash_t);
        __hash_t castedByte = bytes[i];
        hash ^= (castedByte << (CHAR_BIT * byteShift));
    }

    return hash;
};