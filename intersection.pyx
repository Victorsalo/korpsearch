# cython: language_level=3

from disk import SlowDiskIntArray
import sys

from libc.stdlib cimport malloc, free

cdef to_bytes_and_elemsize(array):
    """Convert an array to a pair (bytes, item size)."""

    if isinstance(array, memoryview):
        bytearray = array.obj
        elemsize = array.itemsize
    elif isinstance(array, SlowDiskIntArray):
        assert array._byteorder == sys.byteorder
        bytearray = array._array
        elemsize = array._elemsize
    else:
        assert False, "argument to to_bytes_and_elemsize has unknown type"

    return bytearray, elemsize

cdef const unsigned char[::1] to_memoryview(array, elemsize, start, length):
    """Convert a slice of an array into a memoryview."""

    cdef const unsigned char[::1] result = array
    return result[start*elemsize:(start+length)*elemsize]

def intersection(arr1, start1, length1, arr2, start2, length2):
    """Take the intersection of two sorted arrays."""

    arr1, elemsize = to_bytes_and_elemsize(arr1)
    arr2, elemsize2 = to_bytes_and_elemsize(arr2)
    assert elemsize == elemsize2

    cdef const unsigned char[::1] buf1 = to_memoryview(arr1, elemsize, start1, length1)
    cdef const unsigned char[::1] buf2 = to_memoryview(arr2, elemsize, start2, length2)
    out = <char*>malloc(max(len(buf1), len(buf2)))

    try:
        length = intersection_switch(&buf1[0], len(buf1), &buf2[0], len(buf2), out, elemsize)
        result = out[:length]
        return SlowDiskIntArray(result, elemsize, sys.byteorder)
    finally:
        free(out)

cdef int intersection_switch(const void *in1, int len1, const void *in2, int len2, void *out, int size):
    # Generate specialised code for each value of 'size'.
    # This improves performance because it allows the C compiler to specialise
    # read_bytes and write_bytes to the given size.
    if size == 1: return intersection_core(in1, len1, in2, len2, out, 1)
    elif size == 2: return intersection_core(in1, len1, in2, len2, out, 2)
    elif size == 3: return intersection_core(in1, len1, in2, len2, out, 3)
    elif size == 4: return intersection_core(in1, len1, in2, len2, out, 4)
    else: return intersection_core(in1, len1, in2, len2, out, size)

cdef inline int intersection_core(const void *in1, int len1, const void *in2, int len2, void *out, int size):
    """The low-level intersection routine."""

    cdef int i = 0
    cdef int j = 0
    cdef int k = 0

    while i < len1 and j < len2:
        x = read_bytes(in1+i, size)
        y = read_bytes(in2+j, size)

        if x < y: i += size
        elif x > y: j += size
        else:
            write_bytes(out+k, x, size)
            i += size
            j += size
            k += size
    return k

cdef extern from "string.h":
    void *memcpy(void *dest, const void *src, size_t len)

cdef inline long read_bytes(const void *ptr, int size):
    """Read an integer of the given number of bytes from a pointer."""

    cdef long result = 0
    memcpy(&result, ptr, size)
    return result

cdef inline void write_bytes(void *ptr, long value, int size):
    """Write an integer of the given number of bytes to a pointer."""

    memcpy(ptr, &value, size)
