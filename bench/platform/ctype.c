/* Minimal newlib-compatible classification table used by Embench's slre.
 * Newlib's <ctype.h> macros index this table directly on bare-metal targets. */
enum {
    C_UPPER = 0x01,
    C_LOWER = 0x02,
    C_DIGIT = 0x04,
    C_SPACE = 0x08,
    C_PUNCT = 0x10,
    C_CNTRL = 0x20,
    C_HEX = 0x40,
    C_BLANK = 0x80,
};

const unsigned char _ctype_[257] = {
    [0 ... 32] = C_CNTRL,
    ['\t'] = C_SPACE | C_CNTRL | C_BLANK,
    ['\n' ... '\r'] = C_SPACE | C_CNTRL,
    [' '] = C_SPACE | C_BLANK,
    ['!' ... '/'] = C_PUNCT,
    ['0' ... '9'] = C_DIGIT | C_HEX,
    [':' ... '@'] = C_PUNCT,
    ['A' ... 'F'] = C_UPPER | C_HEX,
    ['G' ... 'Z'] = C_UPPER,
    ['[' ... '`'] = C_PUNCT,
    ['a' ... 'f'] = C_LOWER | C_HEX,
    ['g' ... 'z'] = C_LOWER,
    ['{' ... '~'] = C_PUNCT,
    [127] = C_CNTRL,
};
