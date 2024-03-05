#include "file-index-map.h"

#include <string.h>
#include "hash.h"

FileIndexHashMap *FileIndexCreate()
{
    FileIndexHashMap *map = malloc(sizeof(FileIndexHashMap));

    map->size = 0;
    map->bucketCount = 1;

    map->buckets = malloc(
        sizeof(FileIndexBucket) * map->bucketCount);

    for (size_t bucketIndex = 0; bucketIndex < map->bucketCount; ++bucketIndex)
    {
        FileIndexBucket bucket = map->buckets[bucketIndex];

        bucket.nodeCount = 0;
        bucket.nodeCapacity = 4;
        bucket.nodes = malloc(
            sizeof(FileIndexNode) * bucket.nodeCapacity);
    }

    return map;
}

void FileIndexClose(FileIndexHashMap *map)
{
    for (size_t bucketIndex = 0; bucketIndex < map->bucketCount; ++bucketIndex)
    {
        FileIndexBucket bucket = map->buckets[bucketIndex];

        for (size_t nodeIndex = 0; nodeIndex < bucket.nodeCapacity; ++nodeIndex)
        {
            FileIndexNode node = bucket.nodes[nodeIndex];
            free(node.key);
        }

        free(bucket.nodes);
    }

    free(map->buckets);
    free(map);
}

FileIndex FileIndexGet(FileIndexHashMap *map, char *key, bool *found)
{
    size_t keyLen = strlen(key);

    size_t bucketIndex = Hash(key, keyLen + 1) % map->bucketCount;

    FileIndexBucket bucket = map->buckets[bucketIndex];

    for (size_t nodeIndex = 0; nodeIndex < bucket.nodeCount; ++nodeIndex)
    {
        FileIndexNode node = bucket.nodes[nodeIndex];
        if (strcmp(node.key, key))
        {
            *found = true;
            return node.fileIndex;
        }
    }

    *found = false;
    return (FileIndex){0, 0};
}

void _set(FileIndexHashMap *map, char *key, FileIndex index, bool copyKey)
{
    size_t keyLen = strlen(key);
    size_t bucketIndex = Hash(key, keyLen + 1) % map->bucketCount;

    FileIndexBucket bucket = map->buckets[bucketIndex];

    for (size_t nodeIndex = 0; nodeIndex < bucket.nodeCount; ++nodeIndex)
    {
        FileIndexNode node = bucket.nodes[nodeIndex];
        if (strcmp(node.key, key) == 0)
        {
            node.fileIndex = index;
            return;
        }
    }

    if (bucket.nodeCount == bucket.nodeCapacity)
    {
        bucket.nodeCapacity *= 2;
        // TODO handle bad re-alloc
        bucket.nodes = realloc(bucket.nodes, bucket.nodeCapacity);
    }

    char *nodeKey;

    if (copyKey)
    {
        nodeKey = str(sizeof(char) * (keyLen + 1));
        memcpy(key, nodeKey, keyLen + 1);
    }
    else
    {
        nodeKey = key;
    }

    bucket.nodes[bucket.nodeCount] = (FileIndexNode){
        nodeKey,
        index};

    ++bucket.nodeCount;
    ++map->size;
}

void _resizeBuckets(FileIndexHashMap *map, size_t bucketCount)
{
    size_t oldBucketCount = map->bucketCount;
    map->bucketCount = bucketCount;

    FileIndexBucket *oldBuckets = map->buckets;
    map->buckets = malloc(
        sizeof(FileIndexBucket) * map->bucketCount);

    for (size_t bucketIndex = 0; bucketIndex < oldBucketCount; ++bucketIndex)
    {
        const FileIndexBucket oldBucket = oldBuckets[bucketIndex];
        for (size_t nodeIndex = 0; nodeIndex < oldBucket.nodeCount; ++nodeIndex)
        {
            const FileIndexNode node = oldBucket.nodes[nodeIndex];
            _set(map, node.key, node.fileIndex, false);
        }

        free(oldBucket.nodes);
    }

    free(oldBuckets);
}

void FileIndexSet(FileIndexHashMap *map, char *key, FileIndex index)
{
    _set(map, key, index, true);

    if (map->size / map->bucketCount > 3)
    {
        _resizeBuckets(map, map->bucketCount * 2);
    }
}

void FileIndexDelete(FileIndexHashMap *map, char *key)
{
    size_t keyLen = strlen(key);
    size_t bucketIndex = Hash(key, keyLen + 1) % map->bucketCount;

    FileIndexBucket bucket = map->buckets[bucketIndex];

    bool foundNode = false;
    for (size_t nodeIndex = 0; nodeIndex < bucket.nodeCount; ++nodeIndex)
    {
        FileIndexNode node = bucket.nodes[nodeIndex];
        if (strcmp(node.key, key) == 0)
        {
            foundNode = true;
            continue;
        }

        if (foundNode)
        {
            bucket.nodes[nodeIndex - 1] = node;
        }
    }

    if (foundNode)
    {
        --bucket.nodeCount;
        --map->size;
    }

    if (map->size / map->bucketCount < 1)
    {
        _resizeBuckets(map, map->bucketCount / 2);
    }
}
