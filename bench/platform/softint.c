#include <stdint.h>

/* The installed toolchain has only a hard-float libgcc multilib.  These small
 * RV64I_Zmmul compiler helpers keep the bare-metal benchmark images self-contained
 * for operations that remain unsupported, notably division and 128-bit
 * multiplication. Ordinary 64-bit multiplication is emitted as MUL. */
uint64_t __muldi3(uint64_t left, uint64_t right)
{
    uint64_t product = 0;
    while (right != 0) {
        /* Consume two multiplier bits per iteration.  All arithmetic is
         * unsigned, so the required modulo-2^64 product is preserved. */
        switch (right & 3) {
        case 1:
            product += left;
            break;
        case 2:
            product += left << 1;
            break;
        case 3:
            product += left + (left << 1);
            break;
        default:
            break;
        }
        left <<= 2;
        right >>= 2;
    }
    return product;
}

typedef unsigned __int128 bench_u128;

bench_u128 __multi3(bench_u128 left, bench_u128 right)
{
    bench_u128 product = 0;
    while (right != 0) {
        if (right & 1)
            product += left;
        left <<= 1;
        right >>= 1;
    }
    return product;
}

uint64_t __udivdi3(uint64_t dividend, uint64_t divisor)
{
    uint64_t quotient = 0;
    uint64_t bit = 1;
    if (divisor == 0)
        return 0;
    while (divisor < dividend && (divisor & (UINT64_C(1) << 63)) == 0) {
        divisor <<= 1;
        bit <<= 1;
    }
    while (bit != 0) {
        if (dividend >= divisor) {
            dividend -= divisor;
            quotient |= bit;
        }
        divisor >>= 1;
        bit >>= 1;
    }
    return quotient;
}

uint64_t __umoddi3(uint64_t dividend, uint64_t divisor)
{
    if (divisor == 0)
        return 0;
    return dividend - __udivdi3(dividend, divisor) * divisor;
}

int64_t __divdi3(int64_t dividend, int64_t divisor)
{
    int negative = (dividend < 0) != (divisor < 0);
    uint64_t left = dividend < 0 ? (uint64_t)(-dividend) : (uint64_t)dividend;
    uint64_t right = divisor < 0 ? (uint64_t)(-divisor) : (uint64_t)divisor;
    int64_t quotient = (int64_t)__udivdi3(left, right);
    return negative ? -quotient : quotient;
}

int64_t __moddi3(int64_t dividend, int64_t divisor)
{
    int64_t quotient = __divdi3(dividend, divisor);
    return dividend - quotient * divisor;
}
