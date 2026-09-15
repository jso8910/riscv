#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t count)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    while (count--)
        *d++ = *s++;
    return dest;
}

void *memmove(void *dest, const void *src, size_t count)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    if (d < s) {
        while (count--)
            *d++ = *s++;
    } else {
        d += count;
        s += count;
        while (count--)
            *--d = *--s;
    }
    return dest;
}

void *memset(void *dest, int value, size_t count)
{
    unsigned char *d = dest;
    while (count--)
        *d++ = (unsigned char)value;
    return dest;
}

int memcmp(const void *left, const void *right, size_t count)
{
    const unsigned char *a = left;
    const unsigned char *b = right;
    while (count--) {
        if (*a != *b)
            return *a - *b;
        a++;
        b++;
    }
    return 0;
}

size_t strlen(const char *s)
{
    const char *start = s;
    while (*s)
        s++;
    return (size_t)(s - start);
}

int strcmp(const char *left, const char *right)
{
    while (*left && *left == *right) {
        left++;
        right++;
    }
    return (unsigned char)*left - (unsigned char)*right;
}

char *strchr(const char *s, int c)
{
    while (*s) {
        if (*s == (char)c)
            return (char *)s;
        s++;
    }
    return c == 0 ? (char *)s : 0;
}
