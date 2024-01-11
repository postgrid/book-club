#ifndef FILE_INDEX_MAP_H_
#define FILE_INDEX_MAP_H_

#include <stdlib.h>
#include <stdbool.h>

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

typedef struct FileIndexNode
{
    char *key;
    FileIndex fileIndex;
} FileIndexNode;

typedef struct FileIndexBucket
{
    size_t nodeCount;
    size_t nodeCapacity;
    FileIndexNode *nodes;
} FileIndexBucket;

// FIXME
typedef struct FileIndexHashMap
{
    size_t size;
    size_t bucketCount;

    FileIndexBucket *buckets;
} FileIndexHashMap;

FileIndexHashMap *FileIndexCreate();
void FileIndexClose(FileIndexHashMap *map);

void FileIndexSet(FileIndexHashMap *map, char *key, FileIndex index);
FileIndex FileIndexGet(FileIndexHashMap *map, char *key, bool *found);
void FileIndexDelete(FileIndexHashMap *map, char *key);

#endif