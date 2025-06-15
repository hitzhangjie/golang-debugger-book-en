## Variable-Length Data

Throughout DWARF, there is a large amount of information represented using integer values, from data segment offsets to array or structure sizes, and so on. Since most integer values are small numbers that can be represented with just a few bits, this means the data consists mainly of zeros, and the corresponding bits are effectively wasted.

DWARF defines a variable-length integer encoding scheme called Little Endian Base 128 (LEB128), which can compress the actual number of bytes used and reduce the size of the encoded data. LEB128 has two variants:

- ULEB128: Used for encoding unsigned integers
- SLEB128: Used for encoding signed integers

### ULEB128 Encoding Scheme

UELB128 encoding algorithm:

```
MSB ------------------ LSB
      10011000011101100101  In raw binary
     010011000011101100101  Padded to a multiple of 7 bits
 0100110  0001110  1100101  Split into 7-bit groups
00100110 10001110 11100101  Add high 1 bits on all but last (most significant) group to form bytes
    0x26     0x8E     0xE5  In hexadecimal

→ 0xE5 0x8E 0x26            Output stream (LSB to MSB)
```

To summarize in plain language:

1. Convert the number to binary representation, with these bytes arranged in little-endian order (i.e., least significant byte first)
2. Split the integer into groups of 7 bits
3. Store each 7-bit group in a byte, using the highest bit (8th bit) as a flag:
   - If there are more groups to follow, set this bit to 1
   - If this is the last group, set this bit to 0

For example, the ULEB128 encoding of the number Uint64 624485 is:

624485 = 0x98765

Hexadecimal number, where each digit is represented by 4 binary bits, converted to binary representation:
```
1001 1000 0111 0110 0101
```

Considering splitting into groups of 7 bits, first pad to a multiple of 7 bits:
```
0 1001 1000 0111 0110 0101
```

Then split into groups of 7 bits, note that it's little-endian byte order, so split from the right:

```
0 1001 10 / 00 0111 0 / 110 0101
```

- Group 1: 110 0101, because there are more to follow, set the 8th bit to 1, final result is 1110 0101 = 0xe5
- Group 2: 00 0111 0, 000 1110, set the 8th bit to 1, final result is 1000 1110 = 0x8e
- Group 3: 0 1001 10, 010 0110, set the 8th bit to 0, final result is 0010 0110 = 0x26

The encoded byte sequence is: []byte{0xe5 0x8e 0x26}, using only 3 bytes in total, while using the original data type uint64 would require 8 bytes.

### SLEB128 Encoding Scheme

The SLEB128 encoding rules are similar, but when handling negative numbers, sign bit extension needs to be considered. There is no difference when handling positive numbers.

SLEB128 negative number encoding algorithm:

```
MSB ------------------ LSB
         11110001001000000  Binary encoding of 123456
     000011110001001000000  As a 21-bit number
     111100001110110111111  Negating all bits (ones' complement)
     111100001110111000000  Adding one (two's complement)
 1111000  0111011  1000000  Split into 7-bit groups
01111000 10111011 11000000  Add high 1 bits on all but last (most significant) group to form bytes
    0x78     0xBB     0xC0  In hexadecimal
```

In plain language:

1. If it's a negative number, first convert to two's complement representation
2. Then split into groups of 7 bits, still following little-endian order
3. Set the 8th bit to 1 for all groups except the last one
4. Get the final result

### Summary

This article introduced the ULEB128 and SLEB128 encoding schemes that are storage-friendly for small integers, which can save storage space. For positive numbers, ULEB128 and SLEB128 encoding results are the same, but for negative numbers, SLEB128 needs to convert to its two's complement before encoding. Through this encoding method, DWARF can effectively compress integer data and reduce the size of debugging information. In practical applications, most integer values can be represented using 1-2 bytes, saving significant space compared to fixed 4-byte or 8-byte storage methods.
