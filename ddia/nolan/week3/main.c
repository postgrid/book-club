#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// Store data in binary like
// key1:value1
// key2:value2
//
// TODO add checksum with key1:value1:checksum1
const char KEY_SEP = ':';
const char VALUE_SEP = '\n';
const char ESCAPE = '\\';
const char DELETED = '\0';

typedef struct
{
    char *data;
    size_t len;
} Buffer;

typedef struct
{
    size_t start;
    size_t len;
} FileIndex;

// FIXME
typedef struct
{
} FileIndexHashMap;

void SetIndex(FileIndexHashMap map, char *key, FileIndex index);
FileIndex GetIndex(FileIndexHashMap map, char *key);
void DeleteIndex(FileIndexHashMap map, char *key);

typedef struct
{
    FileIndexHashMap map;
    char *handle;
    FILE *file;
} DB;

DB *open(char *handle)
{
    // FIXME
    FileIndexHashMap map;

    FILE *file = fopen(handle, "r");

    if (!file)
    {
        fclose(file);
        return NULL;
    }

    size_t readBytes;
    size_t totalReadBytes;
    const size_t chunkSize = 100;
    char chunk[100];
    char prevChar;

    size_t keyStart;
    size_t keySize = 0;
    bool nullTerminatingKey = false;

    size_t valueStart;
    size_t valueSize = 0;

    // TODO account for checksum
    bool keyMode = true;

    bool escapeMode = false;

    do
    {
        readBytes = fread(chunk, sizeof(char), chunkSize, file);

        if (ferror(file))
        {
            fclose(file);
            return NULL;
        }

        for (int i = 0; i < readBytes; ++i)
        {
            const char currentChar = chunk[i];
            ++totalReadBytes;

            if (keyMode && currentChar == KEY_SEP && !escapeMode)
            {
                keyMode = false;
                valueStart = totalReadBytes;
                valueSize = 0;

                continue;
            }

            if (!keyMode && currentChar == VALUE_SEP && !escapeMode)
            {
                if (fseek(file, keyStart, SEEK_SET))
                {
                    fclose(file);
                    return NULL;
                }

                // TODO filter key for escaped value
                char *key = malloc(sizeof(char) * (nullTerminatingKey
                                                       ? keySize
                                                       : keySize + 1));

                if (keySize != fread(key, sizeof(char), keySize, file))
                {
                    free(key);
                    fclose(file);
                    return NULL;
                }

                if (!nullTerminatingKey)
                {
                    key[keySize] = '\0';
                }

                if (fseek(file, keySize, SEEK_CUR))
                {
                    fclose(file);
                    return NULL;
                }

                FileIndex index = {valueStart, valueSize};

                SetIndex(map, key, index);

                // Check for deletion markers
                if (valueSize == 1 && currentChar == DELETED)
                {
                    DeleteIndex(map, key);
                }

                keyMode = true;
                keyStart = ftell(file);
            }

            if (keyMode)
            {
                ++keySize;
            }
            else
            {
                ++valueSize;
            }

            escapeMode = keyMode && !escapeMode && currentChar == ESCAPE;

            if (keyMode && currentChar == '\0')
            {
                nullTerminatingKey = true;
            }
            else if (keyMode)
            {
                nullTerminatingKey = false;
            }
        }

    } while (readBytes == chunkSize);

    // Handle incomplete value
    if (!keyMode && valueSize)
    {
        if (fseek(file, keyStart, SEEK_SET))
        {
            fclose(file);
            return NULL;
        }

        // TODO filter key for escaped value
        char *key = malloc(sizeof(char) * (nullTerminatingKey
                                               ? keySize
                                               : keySize + 1));

        if (keySize != fread(key, sizeof(char), keySize, file))
        {
            free(key);
            fclose(file);
            return NULL;
        }

        if (!nullTerminatingKey)
        {
            key[keySize] = '\0';
        }

        FileIndex index = {valueStart, valueSize};
        SetIndex(map, key, index);
    }

    size_t handleSize = strlen(handle);
    char *handleCpy = malloc(sizeof(char) * handleSize);
    memcpy(handleCpy, handle, handleSize);

    DB *db = malloc(sizeof(DB));
    db->handle = handleCpy;
    db->map = map;
    db->file = file;

    return db;
}

Buffer *GetDB(DB db, char *key)
{
    FileIndex index = GetIndex(db.map, key);

    FILE *file = freopen(db.handle, "r", db.file);

    if (!file)
    {
        return NULL;
    }

    fsetpos(file, index.start);

    char *data = malloc(sizeof(char) * index.len);
    if (fread(data, sizeof(char), index.len, file) != 1)
    {
        return NULL;
    }

    Buffer *buff = malloc(sizeof(Buffer));
    buff->data = data;
    buff->len = index.len;

    return buff;
}

int SetDB(DB db, char *key, Buffer value)
{
    FILE *file = freopen(db.handle, "a", db.file);

    if (!file)
    {
        return -1;
    }

    if (fputs(key, file) != EOF)
    {
        return NULL;
    }

    if (fputc(KEY_SEP, file) != EOF)
    {
        return NULL;
    }

    const size_t dataStart = ftell(file);

    if (fwrite(value.data, sizeof(char), value.len, file) != value.len)
    {
        return NULL;
    }

    if (fputc(VALUE_SEP, file) != EOF)
    {
        return NULL;
    }

    FileIndex index = {
        dataStart,
        value.len};

    SetIndex(db.map, key, index);
}
