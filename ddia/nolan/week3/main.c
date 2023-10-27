#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#include <string.h>
#include <limits.h>

#include "file-index-map.h"
#include "hash.h"

typedef enum DBError
{
    DB_OKAY = 0U,
    DB_FILE_ERROR = 1U
} DBError;

/**
 * To resume course after a failed checksum,
 * a random indicator is used before every key-value
 * pair. The program should seek this value from
 * within the file before the first key-value pair
 * as well as after any checksum failures.
 *
 * I could make more bytes for lower collision chance
 * I'm satisfied with 2^64 corruption errors required.
 * Also avoid spinning up 2^64 DBs if that's possible
 *
 */
typedef size_t __indicator_t;
const __indicator_t INDICATOR = 0x1725394551607083UL;

typedef __uint8_t __keysize_t;
const size_t MAX_KEY_SIZE = (1UL << (CHAR_BIT * sizeof(__keysize_t))) - 1UL;

const size_t PREFIX_SIZE = sizeof(__indicator_t) + sizeof(__keysize_t) + sizeof(size_t);

/**
 * Store data in the following format:
 * [INDICATOR]{INDICATOR_SIZE}
 * [keySize]{sizeof(__keysize_t)}
 * [valueSize]{sizeof(size_t)}
 * [key]{keySize}
 * [value]{valueSize}
 * [checksum]{CHECKSUM_SIZE}
 * NOTE key is always a string (null-terminated)
 **/

typedef struct DB
{
    FileIndexHashMap map;
    char *handle;
    FILE *file;
    DBError error;
} DB;

/**
 * Consumes a pointer to a FILE and iterates
 * through looking for bytes matching the INDICATOR.
 *
 * Returns any error codes from file operations
 */
int _seekIndicator(FILE *file)
{
    const size_t readSize = sizeof(__indicator_t) * 1024UL;
    const size_t previousDataSize = sizeof(__indicator_t) - 1;
    const size_t bufferSize = readSize + previousDataSize;
    char *buffer = calloc(sizeof(char), bufferSize);

    long position = 0;

    while (true)
    {
        // Copy end of previous buffer to start
        if (position)
        {
            memcpy(buffer, buffer + readSize, previousDataSize);
        }
        size_t expectedBytesRead = position ? readSize : bufferSize;

        size_t bytesRead = fread(
            position
                ? buffer + previousDataSize
                : buffer,
            sizeof(char),
            expectedBytesRead,
            file);

        if (bytesRead < expectedBytesRead && ferror(file))
        {
            return ferror(file);
        }

        __indicator_t testBytes;
        for (long i = 0L; i < bytesRead; ++i)
        {
            memcpy(&testBytes, buffer + i, sizeof(__indicator_t));

            if (testBytes == INDICATOR)
            {
                long offset = position + i;
                // Account for data from previous read
                if (position)
                {
                    offset -= previousDataSize;
                }
                // Skip directly to the key
                offset += sizeof(__indicator_t);
                // Undo reading of last set of bytes
                offset -= bytesRead;
                return fseek(file, offset, SEEK_CUR);
            }
        }

        // This should be an EOF
        if (bytesRead < expectedBytesRead)
        {
            break;
        }

        position += bytesRead;
    }

    return -1;
}

DB DBopen(char *handle)
{
    DB db;

    // FIXME initialize file index map

    FILE *file = fopen(handle, "r");

    if (!file)
    {
        db.error = DB_FILE_ERROR;
        return db;
    }

    _seekIndicator(file);

    char keyValueSizes[sizeof(__keysize_t) + sizeof(size_t)];
    long currentKeyValuePos = ftell(file);
    while (fread(keyValueSizes, sizeof(char), sizeof(keyValueSizes), file) == sizeof(keyValueSizes))
    {
        __keysize_t keySize;
        memcpy(&keySize, keyValueSizes, sizeof(keySize));

        size_t valueSize;
        memcpy(&valueSize, keyValueSizes + sizeof(keySize), sizeof(size_t));

        char *keyValueData = malloc(sizeof(char) * (valueSize + keySize));
        fread(keyValueData, sizeof(char), valueSize + keySize, file);

        char *key = malloc(sizeof(char) * keySize);
        memcpy(key, keyValueData, keySize);

        const __hash_t hash = Hash(keyValueData, keySize + valueSize);
        const __hash_t checksum;
        fread(&checksum, sizeof(__hash_t), 1UL, file);

        if (hash == checksum)
        {
            FileIndex index;
            index.start =
                currentKeyValuePos + PREFIX_SIZE + keySize;
            index.len = valueSize;

            if (index.len)
            {
                FileIndexSet(db.map, key, index);
            }
            else
            {
                FileIndexDelete(db.map, key);
            }
        }
        else
        {
            fseek(file, currentKeyValuePos, SEEK_SET);
            _seekIndicator(file);
        }

        free(key);
        free(keyValueData);
        currentKeyValuePos = ftell(file);
    }

    if (ferror(file))
    {
        db.error |= DB_FILE_ERROR;
    }

    return db;
}

Buffer DBGet(DB db, char *key)
{
    Buffer buff;

    FileIndex index = FileIndexGet(db.map, key);

    FILE *file = freopen(db.handle, "r", db.file);

    if (!file)
    {
        db.error = DB_FILE_ERROR;
        return buff;
    }

    fsetpos(file, index.start);

    char *data = malloc(sizeof(char) * index.len);
    if (fread(data, sizeof(char), index.len, file) != 1)
    {
        db.error = DB_FILE_ERROR;
        return buff;
    }

    buff.data = data;
    buff.len = index.len;

    return buff;
}

// TODO error codes
int DBSet(DB db, char *key, Buffer value)
{
    FILE *file = freopen(db.handle, "a", db.file);

    if (!file)
    {
        db.error = DB_FILE_ERROR;
        return -1;
    }

    const size_t uncheckedKeySize = strlen(key) + sizeof(char);
    if (uncheckedKeySize > MAX_KEY_SIZE)
    {
        return -1;
    }

    const __keysize_t keySize = uncheckedKeySize;

    const size_t payloadSize = PREFIX_SIZE + keySize + value.len +
                               sizeof(__hash_t);

    char *payload = malloc(sizeof(char) * payloadSize);

    size_t bytesCopied = 0;
    memcpy(payload + bytesCopied, &INDICATOR, sizeof(__indicator_t));
    bytesCopied += sizeof(__indicator_t);

    memcpy(payload + bytesCopied, &keySize, sizeof(__keysize_t));
    bytesCopied += sizeof(__keysize_t);

    memcpy(payload + bytesCopied, &(value.len), sizeof(size_t));
    bytesCopied += sizeof(size_t);

    memcpy(payload + bytesCopied, key, keySize);
    bytesCopied += keySize;

    const size_t dataStart = ftell(file) + bytesCopied;
    memcpy(payload + bytesCopied, value.data, value.len);
    bytesCopied += value.len;

    // Just hash key and value
    const __uint32_t hash = Hash(payload + PREFIX_SIZE, bytesCopied - PREFIX_SIZE);
    memcpy(payload + bytesCopied, &hash, sizeof(__hash_t));

    fwrite(payload, sizeof(char), payloadSize, file);

    free(payload);

    FileIndex index = {dataStart, value.len};

    FileIndexSet(db.map, key, index);

    return 0;
}
