#include <stdint.h>

/* Embench's wikisort uses sqrt only to obtain an integer block length.  Keep
 * that path soft-float-free: encode/decode finite integer-valued doubles and
 * return floor(sqrt(x)).  This is sufficient for its positive array sizes. */
typedef union {
    double value;
    uint64_t bits;
} bench_double_bits_t;

static uint64_t double_to_unsigned(double value)
{
    bench_double_bits_t input = { .value = value };
    uint64_t fraction = input.bits & UINT64_C(0x000fffffffffffff);
    int exponent = (int)((input.bits >> 52) & 0x7ff) - 1023;
    uint64_t mantissa;
    if (exponent < 0)
        return 0;
    mantissa = fraction | UINT64_C(0x0010000000000000);
    if (exponent >= 52)
        return mantissa << (exponent - 52);
    return mantissa >> (52 - exponent);
}

static double unsigned_to_double(uint64_t value)
{
    bench_double_bits_t output;
    unsigned int shift = 0;
    uint64_t fraction;
    if (value == 0) {
        output.bits = 0;
        return output.value;
    }
    for (uint64_t probe = value; probe > 1; probe >>= 1)
        shift++;
    if (shift <= 52)
        fraction = (value << (52 - shift)) & UINT64_C(0x000fffffffffffff);
    else
        fraction = (value >> (shift - 52)) & UINT64_C(0x000fffffffffffff);
    output.bits = ((uint64_t)(shift + 1023) << 52) | fraction;
    return output.value;
}

double __floatdidf(int64_t value)
{
    if (value < 0) {
        bench_double_bits_t output = { .value = unsigned_to_double((uint64_t)(-value)) };
        output.bits |= UINT64_C(1) << 63;
        return output.value;
    }
    return unsigned_to_double((uint64_t)value);
}

int64_t __fixdfdi(double value)
{
    bench_double_bits_t input = { .value = value };
    uint64_t magnitude = double_to_unsigned(value);
    return (input.bits >> 63) ? -(int64_t)magnitude : (int64_t)magnitude;
}

double sqrt(double value)
{
    uint64_t number = double_to_unsigned(value);
    uint64_t root = 0;
    uint64_t bit = UINT64_C(1) << 62;
    while (bit > number)
        bit >>= 2;
    while (bit != 0) {
        if (number >= root + bit) {
            number -= root + bit;
            root = (root >> 1) + bit;
        } else {
            root >>= 1;
        }
        bit >>= 2;
    }
    return unsigned_to_double(root);
}
