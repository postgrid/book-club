#ifndef FILE_INDEX_MAP_H_
#define FILE_INDEX_MAP_H_

#include <stdlib.h>

typedef struct Buffer
{
    char *data;
    size_t len;
} Buffer;

typedef struct FileIndex
{
    size_t start;
    size_t len;
} FileIndex;

// FIXME
typedef struct FileIndexHashMap
{
} FileIndexHashMap;

void FileIndexSet(FileIndexHashMap map, char *key, FileIndex index);
FileIndex FileIndexGet(FileIndexHashMap map, char *key);
void FileIndexDelete(FileIndexHashMap map, char *key);

#endif