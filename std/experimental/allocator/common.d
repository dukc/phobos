// Written in the D programming language.
/**
Utility and ancillary artifacts of `std.experimental.allocator`. This module
shouldn't be used directly; its functionality will be migrated into more
appropriate parts of `std`.

Authors: $(HTTP erdani.com, Andrei Alexandrescu), Timon Gehr (`Ternary`)

Source: $(PHOBOSSRC std/experimental/allocator/common.d)
*/
module std.experimental.allocator.common;
import std.algorithm.comparison, std.traits;

/**
Returns the size in bytes of the state that needs to be allocated to hold an
object of type `T`. `stateSize!T` is zero for `struct`s that are not
nested and have no nonstatic member variables.
 */
template stateSize(T)
{
    static if (is(T == class) || is(T == interface))
        enum stateSize = __traits(classInstanceSize, T);
    else static if (is(T == struct) || is(T == union))
        enum stateSize = Fields!T.length || isNested!T ? T.sizeof : 0;
    else static if (is(T == void))
        enum size_t stateSize = 0;
    else
        enum stateSize = T.sizeof;
}

@safe @nogc nothrow pure
unittest
{
    static assert(stateSize!void == 0);
    struct A {}
    static assert(stateSize!A == 0);
    struct B { int x; }
    static assert(stateSize!B == 4);
    interface I1 {}
    //static assert(stateSize!I1 == 2 * size_t.sizeof);
    class C1 {}
    static assert(stateSize!C1 == 3 * size_t.sizeof);
    class C2 { char c; }
    static assert(stateSize!C2 == 4 * size_t.sizeof);
    static class C3 { char c; }
    static assert(stateSize!C3 == 2 * size_t.sizeof + char.sizeof);
}

/**
Returns `true` if the `Allocator` has the alignment known at compile time;
otherwise it returns `false`.
 */
template hasStaticallyKnownAlignment(Allocator)
{
    enum hasStaticallyKnownAlignment = __traits(compiles,
                                                {enum x = Allocator.alignment;});
}

/**
`chooseAtRuntime` is a compile-time constant of type `size_t` that several
parameterized structures in this module recognize to mean deferral to runtime of
the exact value. For example, $(D BitmappedBlock!(Allocator, 4096)) (described in
detail below) defines a block allocator with block size of 4096 bytes, whereas
$(D BitmappedBlock!(Allocator, chooseAtRuntime)) defines a block allocator that has a
field storing the block size, initialized by the user.
*/
enum chooseAtRuntime = size_t.max - 1;

/**
`unbounded` is a compile-time constant of type `size_t` that several
parameterized structures in this module recognize to mean "infinite" bounds for
the parameter. For example, `Freelist` (described in detail below) accepts a
`maxNodes` parameter limiting the number of freelist items. If `unbounded`
is passed for `maxNodes`, then there is no limit and no checking for the
number of nodes.
*/
enum unbounded = size_t.max;

/**
The alignment that is guaranteed to accommodate any D object allocation on the
current platform.
*/
enum uint platformAlignment = std.algorithm.comparison.max(double.alignof, real.alignof);

/**
The default good size allocation is deduced as `n` rounded up to the
allocator's alignment.
*/
size_t goodAllocSize(A)(auto ref A a, size_t n)
{
    return n.roundUpToMultipleOf(a.alignment);
}

/*
Returns s rounded up to a multiple of base.
*/
@safe @nogc nothrow pure
package size_t roundUpToMultipleOf(size_t s, uint base)
{
    assert(base);
    auto rem = s % base;
    return rem ? s + base - rem : s;
}

@safe @nogc nothrow pure
unittest
{
    assert(10.roundUpToMultipleOf(11) == 11);
    assert(11.roundUpToMultipleOf(11) == 11);
    assert(12.roundUpToMultipleOf(11) == 22);
    assert(118.roundUpToMultipleOf(11) == 121);
}

/*
Returns `n` rounded up to a multiple of alignment, which must be a power of 2.
*/
@safe @nogc nothrow pure
package size_t roundUpToAlignment(size_t n, uint alignment)
{
    import std.math : isPowerOf2;
    assert(alignment.isPowerOf2);
    immutable uint slack = cast(uint) n & (alignment - 1);
    const result = slack
        ? n + alignment - slack
        : n;
    assert(result >= n);
    return result;
}

@safe @nogc nothrow pure
unittest
{
    assert(10.roundUpToAlignment(4) == 12);
    assert(11.roundUpToAlignment(2) == 12);
    assert(12.roundUpToAlignment(8) == 16);
    assert(118.roundUpToAlignment(64) == 128);
}

/*
Returns `n` rounded down to a multiple of alignment, which must be a power of 2.
*/
@safe @nogc nothrow pure
package size_t roundDownToAlignment(size_t n, uint alignment)
{
    import std.math : isPowerOf2;
    assert(alignment.isPowerOf2);
    return n & ~size_t(alignment - 1);
}

@safe @nogc nothrow pure
unittest
{
    assert(10.roundDownToAlignment(4) == 8);
    assert(11.roundDownToAlignment(2) == 10);
    assert(12.roundDownToAlignment(8) == 8);
    assert(63.roundDownToAlignment(64) == 0);
}

/*
Advances the beginning of `b` to start at alignment `a`. The resulting buffer
may therefore be shorter. Returns the adjusted buffer, or null if obtaining a
non-empty buffer is impossible.
*/
@nogc nothrow pure
package void[] roundUpToAlignment(void[] b, uint a)
{
    auto e = b.ptr + b.length;
    auto p = cast(void*) roundUpToAlignment(cast(size_t) b.ptr, a);
    if (e <= p) return null;
    return p[0 .. e - p];
}

@nogc nothrow pure
@system unittest
{
    void[] empty;
    assert(roundUpToAlignment(empty, 4) == null);
    char[128] buf;
    // At least one pointer inside buf is 128-aligned
    assert(roundUpToAlignment(buf, 128) !is null);
}

/*
Like `a / b` but rounds the result up, not down.
*/
@safe @nogc nothrow pure
package size_t divideRoundUp(size_t a, size_t b)
{
    assert(b);
    return (a + b - 1) / b;
}

/*
Returns `s` rounded up to a multiple of `base`.
*/
@nogc nothrow pure
package void[] roundStartToMultipleOf(void[] s, uint base)
{
    assert(base);
    auto p = cast(void*) roundUpToMultipleOf(
        cast(size_t) s.ptr, base);
    auto end = s.ptr + s.length;
    return p[0 .. end - p];
}

nothrow pure
@system unittest
{
    void[] p;
    assert(roundStartToMultipleOf(p, 16) is null);
    p = new ulong[10];
    assert(roundStartToMultipleOf(p, 16) is p);
}

/*
Returns `s` rounded up to the nearest power of 2.
*/
@safe @nogc nothrow pure
package size_t roundUpToPowerOf2(size_t s)
{
    import std.meta : AliasSeq;
    assert(s <= (size_t.max >> 1) + 1);
    --s;
    static if (size_t.sizeof == 4)
        alias Shifts = AliasSeq!(1, 2, 4, 8, 16);
    else
        alias Shifts = AliasSeq!(1, 2, 4, 8, 16, 32);
    foreach (i; Shifts)
    {
        s |= s >> i;
    }
    return s + 1;
}

@safe @nogc nothrow pure
unittest
{
    assert(0.roundUpToPowerOf2 == 0);
    assert(1.roundUpToPowerOf2 == 1);
    assert(2.roundUpToPowerOf2 == 2);
    assert(3.roundUpToPowerOf2 == 4);
    assert(7.roundUpToPowerOf2 == 8);
    assert(8.roundUpToPowerOf2 == 8);
    assert(10.roundUpToPowerOf2 == 16);
    assert(11.roundUpToPowerOf2 == 16);
    assert(12.roundUpToPowerOf2 == 16);
    assert(118.roundUpToPowerOf2 == 128);
    assert((size_t.max >> 1).roundUpToPowerOf2 == (size_t.max >> 1) + 1);
    assert(((size_t.max >> 1) + 1).roundUpToPowerOf2 == (size_t.max >> 1) + 1);
}

/*
Returns the number of trailing zeros of `x`.
*/
@safe @nogc nothrow pure
package uint trailingZeros(ulong x)
{
    uint result;
    while (result < 64 && !(x & (1UL << result)))
    {
        ++result;
    }
    return result;
}

@safe @nogc nothrow pure
unittest
{
    assert(trailingZeros(0) == 64);
    assert(trailingZeros(1) == 0);
    assert(trailingZeros(2) == 1);
    assert(trailingZeros(3) == 0);
    assert(trailingZeros(4) == 2);
}

/*
Returns `true` if `ptr` is aligned at `alignment`.
*/
@nogc nothrow pure
package bool alignedAt(T)(T* ptr, uint alignment)
{
    return cast(size_t) ptr % alignment == 0;
}

/*
Returns the effective alignment of `ptr`, i.e. the largest power of two that is
a divisor of `ptr`.
*/
@nogc nothrow pure
package uint effectiveAlignment(void* ptr)
{
    return 1U << trailingZeros(cast(size_t) ptr);
}

@nogc nothrow pure
@system unittest
{
    int x;
    assert(effectiveAlignment(&x) >= int.alignof);
}

/*
Aligns a pointer down to a specified alignment. The resulting pointer is less
than or equal to the given pointer.
*/
@nogc nothrow pure
package void* alignDownTo(void* ptr, uint alignment)
{
    import std.math : isPowerOf2;
    assert(alignment.isPowerOf2);
    return cast(void*) (cast(size_t) ptr & ~(alignment - 1UL));
}

/*
Aligns a pointer up to a specified alignment. The resulting pointer is greater
than or equal to the given pointer.
*/
@nogc nothrow pure
package void* alignUpTo(void* ptr, uint alignment)
{
    import std.math : isPowerOf2;
    assert(alignment.isPowerOf2);
    immutable uint slack = cast(size_t) ptr & (alignment - 1U);
    return slack ? ptr + alignment - slack : ptr;
}

@safe @nogc nothrow pure
package bool isGoodStaticAlignment(uint x)
{
    import std.math : isPowerOf2;
    return x.isPowerOf2;
}

@safe @nogc nothrow pure
package bool isGoodDynamicAlignment(uint x)
{
    import std.math : isPowerOf2;
    return x.isPowerOf2 && x >= (void*).sizeof;
}

/**
The default `reallocate` function first attempts to use `expand`. If $(D
Allocator.expand) is not defined or returns `false`, `reallocate`
allocates a new block of memory of appropriate size and copies data from the old
block to the new block. Finally, if `Allocator` defines `deallocate`, $(D
reallocate) uses it to free the old memory block.

`reallocate` does not attempt to use `Allocator.reallocate` even if
defined. This is deliberate so allocators may use it internally within their own
implementation of `reallocate`.

*/
bool reallocate(Allocator)(ref Allocator a, ref void[] b, size_t s)
{
    if (b.length == s) return true;
    static if (hasMember!(Allocator, "expand"))
    {
        if (b.length <= s && a.expand(b, s - b.length)) return true;
    }
    auto newB = a.allocate(s);
    if (newB.length != s) return false;
    if (newB.length <= b.length) newB[] = b[0 .. newB.length];
    else newB[0 .. b.length] = b[];
    static if (hasMember!(Allocator, "deallocate"))
        a.deallocate(b);
    b = newB;
    return true;
}

/**

The default `alignedReallocate` function first attempts to use `expand`.
If `Allocator.expand` is not defined or returns `false`,  $(D
alignedReallocate) allocates a new block of memory of appropriate size and
copies data from the old block to the new block. Finally, if `Allocator`
defines `deallocate`, `alignedReallocate` uses it to free the old memory
block.

`alignedReallocate` does not attempt to use `Allocator.reallocate` even if
defined. This is deliberate so allocators may use it internally within their own
implementation of `reallocate`.

*/
bool alignedReallocate(Allocator)(ref Allocator alloc,
        ref void[] b, size_t s, uint a)
if (hasMember!(Allocator, "alignedAllocate"))
{
    static if (hasMember!(Allocator, "expand"))
    {
        if (b.length <= s && b.ptr.alignedAt(a)
            && alloc.expand(b, s - b.length)) return true;
    }
    else
    {
        if (b.length == s && b.ptr.alignedAt(a)) return true;
    }
    auto newB = alloc.alignedAllocate(s, a);
    if (newB.length != s) return false;
    if (newB.length <= b.length) newB[] = b[0 .. newB.length];
    else newB[0 .. b.length] = b[];
    static if (hasMember!(Allocator, "deallocate"))
        alloc.deallocate(b);
    b = newB;
    return true;
}

@system unittest
{
    bool called = false;
    struct DummyAllocator
    {
        void[] alignedAllocate(size_t size, uint alignment)
        {
            called = true;
            return null;
        }
    }

    struct DummyAllocatorExpand
    {
        void[] alignedAllocate(size_t size, uint alignment)
        {
            return null;
        }

        bool expand(ref void[] b, size_t length)
        {
            called = true;
            return true;
        }
    }

    char[128] buf;
    uint alignment = 32;
    auto alignedPtr = roundUpToMultipleOf(cast(size_t) buf.ptr, alignment);
    auto diff = alignedPtr - cast(size_t) buf.ptr;

    // Align the buffer to 'alignment'
    void[] b = cast(void[]) (buf.ptr + diff)[0 .. buf.length - diff];

    DummyAllocator a1;
    // Ask for same length and alignment, should not call 'alignedAllocate'
    assert(alignedReallocate(a1, b, b.length, alignment));
    assert(!called);

    // Ask for same length, different alignment
    // should call 'alignedAllocate' if not aligned to new value
    alignedReallocate(a1, b, b.length, alignment + 1);
    assert(b.ptr.alignedAt(alignment + 1) || called);
    called = false;

    DummyAllocatorExpand a2;
    // Ask for bigger length, same alignment, should call 'expand'
    assert(alignedReallocate(a2, b, b.length + 1, alignment));
    assert(called);
    called = false;

    // Ask for bigger length, different alignment
    // should call 'alignedAllocate' if not aligned to new value
    alignedReallocate(a2, b, b.length + 1, alignment + 1);
    assert(b.ptr.alignedAt(alignment + 1) || !called);
}

/**
Forwards each of the methods in `funs` (if defined) to `member`.
*/
/*package*/ string forwardToMember(string member, string[] funs...)
{
    string result = "    import std.traits : hasMember, Parameters;\n";
    foreach (fun; funs)
    {
        result ~= "
    static if (hasMember!(typeof("~member~"), `"~fun~"`))
    auto ref "~fun~"(Parameters!(typeof("~member~"."~fun~")) args)
    {
        return "~member~"."~fun~"(args);
    }\n";
    }
    return result;
}

version(unittest)
{

    package void testAllocator(alias make)()
    {
        import std.conv : text;
        import std.math : isPowerOf2;
        import std.stdio : writeln, stderr;
        import std.typecons : Ternary;
        alias A = typeof(make());
        scope(failure) stderr.writeln("testAllocator failed for ", A.stringof);

        auto a = make();

        // Test alignment
        static assert(A.alignment.isPowerOf2);

        // Test goodAllocSize
        assert(a.goodAllocSize(1) >= A.alignment,
                text(a.goodAllocSize(1), " < ", A.alignment));
        assert(a.goodAllocSize(11) >= 11.roundUpToMultipleOf(A.alignment));
        assert(a.goodAllocSize(111) >= 111.roundUpToMultipleOf(A.alignment));

        // Test allocate
        assert(a.allocate(0) is null);

        auto b1 = a.allocate(1);
        assert(b1.length == 1);
        auto b2 = a.allocate(2);
        assert(b2.length == 2);
        assert(b2.ptr + b2.length <= b1.ptr || b1.ptr + b1.length <= b2.ptr);

        // Test allocateZeroed
        static if (hasMember!(A, "allocateZeroed"))
        {{
            auto b3 = a.allocateZeroed(8);
            if (b3 !is null)
            {
                assert(b3.length == 8);
                foreach (e; cast(ubyte[]) b3)
                    assert(e == 0);
            }
        }}

        // Test alignedAllocate
        static if (hasMember!(A, "alignedAllocate"))
        {{
             auto b3 = a.alignedAllocate(1, 256);
             assert(b3.length <= 1);
             assert(b3.ptr.alignedAt(256));
             assert(a.alignedReallocate(b3, 2, 512));
             assert(b3.ptr.alignedAt(512));
             static if (hasMember!(A, "alignedDeallocate"))
             {
                 a.alignedDeallocate(b3);
             }
         }}
        else
        {
            static assert(!hasMember!(A, "alignedDeallocate"));
            // This seems to be a bug in the compiler:
            //static assert(!hasMember!(A, "alignedReallocate"), A.stringof);
        }

        static if (hasMember!(A, "allocateAll"))
        {{
             auto aa = make();
             if (aa.allocateAll().ptr)
             {
                 // Can't get any more memory
                 assert(!aa.allocate(1).ptr);
             }
             auto ab = make();
             const b4 = ab.allocateAll();
             assert(b4.length);
             // Can't get any more memory
             assert(!ab.allocate(1).ptr);
         }}

        static if (hasMember!(A, "expand"))
        {{
             assert(a.expand(b1, 0));
             auto len = b1.length;
             if (a.expand(b1, 102))
             {
                 assert(b1.length == len + 102, text(b1.length, " != ", len + 102));
             }
             auto aa = make();
             void[] b5 = null;
             assert(aa.expand(b5, 0));
             assert(b5 is null);
             assert(!aa.expand(b5, 1));
             assert(b5.length == 0);
         }}

        void[] b6 = null;
        assert(a.reallocate(b6, 0));
        assert(b6.length == 0);
        assert(a.reallocate(b6, 1));
        assert(b6.length == 1, text(b6.length));
        assert(a.reallocate(b6, 2));
        assert(b6.length == 2);

        // Test owns
        static if (hasMember!(A, "owns"))
        {{
             assert(a.owns(null) == Ternary.no);
             assert(a.owns(b1) == Ternary.yes);
             assert(a.owns(b2) == Ternary.yes);
             assert(a.owns(b6) == Ternary.yes);
         }}

        static if (hasMember!(A, "resolveInternalPointer"))
        {{
             void[] p;
             assert(a.resolveInternalPointer(null, p) == Ternary.no);
             Ternary r = a.resolveInternalPointer(b1.ptr, p);
             assert(p.ptr is b1.ptr && p.length >= b1.length);
             r = a.resolveInternalPointer(b1.ptr + b1.length / 2, p);
             assert(p.ptr is b1.ptr && p.length >= b1.length);
             r = a.resolveInternalPointer(b2.ptr, p);
             assert(p.ptr is b2.ptr && p.length >= b2.length);
             r = a.resolveInternalPointer(b2.ptr + b2.length / 2, p);
             assert(p.ptr is b2.ptr && p.length >= b2.length);
             r = a.resolveInternalPointer(b6.ptr, p);
             assert(p.ptr is b6.ptr && p.length >= b6.length);
             r = a.resolveInternalPointer(b6.ptr + b6.length / 2, p);
             assert(p.ptr is b6.ptr && p.length >= b6.length);
             static int[10] b7 = [ 1, 2, 3 ];
             assert(a.resolveInternalPointer(b7.ptr, p) == Ternary.no);
             assert(a.resolveInternalPointer(b7.ptr + b7.length / 2, p) == Ternary.no);
             assert(a.resolveInternalPointer(b7.ptr + b7.length, p) == Ternary.no);
             int[3] b8 = [ 1, 2, 3 ];
             assert(a.resolveInternalPointer(b8.ptr, p) == Ternary.no);
             assert(a.resolveInternalPointer(b8.ptr + b8.length / 2, p) == Ternary.no);
             assert(a.resolveInternalPointer(b8.ptr + b8.length, p) == Ternary.no);
         }}
    }

    package void testAllocatorObject(RCAllocInterface)(RCAllocInterface a)
    {
        // this used to be a template constraint, but moving it inside prevents
        // unnecessary import of std.experimental.allocator
        import std.experimental.allocator : RCIAllocator, RCISharedAllocator;
        static assert(is(RCAllocInterface == RCIAllocator)
            || is (RCAllocInterface == RCISharedAllocator));

        import std.conv : text;
        import std.math : isPowerOf2;
        import std.stdio : writeln, stderr;
        import std.typecons : Ternary;
        scope(failure) stderr.writeln("testAllocatorObject failed for ",
                RCAllocInterface.stringof);

        assert(!a.isNull);

        // Test alignment
        assert(a.alignment.isPowerOf2);

        // Test goodAllocSize
        assert(a.goodAllocSize(1) >= a.alignment,
                text(a.goodAllocSize(1), " < ", a.alignment));
        assert(a.goodAllocSize(11) >= 11.roundUpToMultipleOf(a.alignment));
        assert(a.goodAllocSize(111) >= 111.roundUpToMultipleOf(a.alignment));

        // Test empty
        assert(a.empty != Ternary.no);

        // Test allocate
        assert(a.allocate(0) is null);

        auto b1 = a.allocate(1);
        assert(b1.length == 1);
        auto b2 = a.allocate(2);
        assert(b2.length == 2);
        assert(b2.ptr + b2.length <= b1.ptr || b1.ptr + b1.length <= b2.ptr);

        // Test alignedAllocate
        {
            // If not implemented it will return null, so those should pass
            auto b3 = a.alignedAllocate(1, 256);
            assert(b3.length <= 1);
            assert(b3.ptr.alignedAt(256));
            if (a.alignedReallocate(b3, 1, 256))
            {
                // If it is false, then the wrapped allocator did not implement
                // this
                assert(a.alignedReallocate(b3, 2, 512));
                assert(b3.ptr.alignedAt(512));
            }
        }

        // Test allocateAll
        {
            auto aa = a.allocateAll();
            if (aa.ptr)
            {
                // Can't get any more memory
                assert(!a.allocate(1).ptr);
                a.deallocate(aa);
            }
            const b4 = a.allocateAll();
            if (b4.ptr)
            {
                // Can't get any more memory
                assert(!a.allocate(1).ptr);
            }
        }

        // Test expand
        {
            assert(a.expand(b1, 0));
            auto len = b1.length;
            if (a.expand(b1, 102))
            {
                assert(b1.length == len + 102, text(b1.length, " != ", len + 102));
            }
        }

        void[] b6 = null;
        assert(a.reallocate(b6, 0));
        assert(b6.length == 0);
        assert(a.reallocate(b6, 1));
        assert(b6.length == 1, text(b6.length));
        assert(a.reallocate(b6, 2));
        assert(b6.length == 2);

        // Test owns
        {
            if (a.owns(null) != Ternary.unknown)
            {
                assert(a.owns(null) == Ternary.no);
                assert(a.owns(b1) == Ternary.yes);
                assert(a.owns(b2) == Ternary.yes);
                assert(a.owns(b6) == Ternary.yes);
            }
        }

        // Test resolveInternalPointer
        {
            void[] p;
            if (a.resolveInternalPointer(null, p) != Ternary.unknown)
            {
                assert(a.resolveInternalPointer(null, p) == Ternary.no);
                Ternary r = a.resolveInternalPointer(b1.ptr, p);
                assert(p.ptr is b1.ptr && p.length >= b1.length);
                r = a.resolveInternalPointer(b1.ptr + b1.length / 2, p);
                assert(p.ptr is b1.ptr && p.length >= b1.length);
                r = a.resolveInternalPointer(b2.ptr, p);
                assert(p.ptr is b2.ptr && p.length >= b2.length);
                r = a.resolveInternalPointer(b2.ptr + b2.length / 2, p);
                assert(p.ptr is b2.ptr && p.length >= b2.length);
                r = a.resolveInternalPointer(b6.ptr, p);
                assert(p.ptr is b6.ptr && p.length >= b6.length);
                r = a.resolveInternalPointer(b6.ptr + b6.length / 2, p);
                assert(p.ptr is b6.ptr && p.length >= b6.length);
                static int[10] b7 = [ 1, 2, 3 ];
                assert(a.resolveInternalPointer(b7.ptr, p) == Ternary.no);
                assert(a.resolveInternalPointer(b7.ptr + b7.length / 2, p) == Ternary.no);
                assert(a.resolveInternalPointer(b7.ptr + b7.length, p) == Ternary.no);
                int[3] b8 = [ 1, 2, 3 ];
                assert(a.resolveInternalPointer(b8.ptr, p) == Ternary.no);
                assert(a.resolveInternalPointer(b8.ptr + b8.length / 2, p) == Ternary.no);
                assert(a.resolveInternalPointer(b8.ptr + b8.length, p) == Ternary.no);
            }
        }

        // Test deallocateAll
        {
            if (a.deallocateAll())
            {
                if (a.empty != Ternary.unknown)
                {
                    assert(a.empty == Ternary.yes);
                }
            }
        }
    }
}

/* Basically the `is` operator, but handles static arrays for which `is` is
deprecated. For use in CTFE. */
private bool bitwiseIdentical(T)(T a, T b)
{
    static if (isStaticArray!T)
    {
        foreach (i, e; a)
        {
            if (!.bitwiseIdentical(e, b[i])) return false;
        }
        return true;
    }
    else return a is b;
}

@nogc nothrow pure @safe unittest
{
    import std.meta : AliasSeq;

    static struct NeverEq
    {
        int x;
        bool opEquals(NeverEq other) const { return false; }
    }

    static struct AlwaysEq
    {
        int x;
        bool opEquals(AlwaysEq other) const { return true; }
    }

    static foreach (x; AliasSeq!(-1, 0, 1, 2, "foo", NeverEq(0)))
    {
        assert(bitwiseIdentical(x, x));
        static assert(bitwiseIdentical(x, x));
    }

    static foreach (pair; AliasSeq!([0, 1], [-1, 1], [2, 3], ["foo", "bar"],
        [AlwaysEq(0), AlwaysEq(1)]))
    {
        assert(!bitwiseIdentical(pair[0], pair[1]));
        static assert(!bitwiseIdentical(pair[0], pair[1]));
    }

    {
        int[2][2][2] x = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
        int[2][2][2] y = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
        assert(bitwiseIdentical(x, y));
    }

    {
        enum int[2][2][2] x = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
        enum int[2][2][2] y = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
        static assert(bitwiseIdentical(x, y));
    }
}

/+
Can the representation be determined at compile time to consist of nothing but
zero bits? Padding between a struct's fields is not considered.
+/
private template isAllZeroBits(T, T value)
{
    static if (isDynamicArray!(typeof(value)))
        enum isAllZeroBits = value is null && value.length == 0;
    else static if (is(typeof(value is null)))
        enum isAllZeroBits = value is null;
    else static if (is(typeof(value is 0)))
        enum isAllZeroBits = value is 0;
    else static if (isStaticArray!(typeof(value)))
        enum isAllZeroBits = ()
        {

            static if (value.length == 0) return true;
            else static if (.isAllZeroBits!(typeof(value[0]), value[0]))
            {
                foreach (e; value[1 .. $])
                {
                    if (!bitwiseIdentical(e, value[0])) return false;
                }
                return true;
            }
            else return false;
        }();
    else static if (is(typeof(value) == struct) || is(typeof(value) == union))
        enum isAllZeroBits = ()
        {
            bool b = true;
            static foreach (e; value.tupleof)
            {
                b &= isAllZeroBits!(typeof(e), e);
                if (b == false) return b;
            }

            return b;
        }();
    else
        enum isAllZeroBits = false;
}

@nogc nothrow pure @safe unittest
{
    import std.meta : AliasSeq;
    static foreach (Int; AliasSeq!(bool, char, wchar, dchar, byte, ubyte,
        short, ushort, int, uint, long, ulong))
    {
        static assert(isAllZeroBits!(Int, Int(0)));
        static assert(!isAllZeroBits!(Int, Int(1)));
    }

    foreach (Float; AliasSeq!(float, double, real))
    {
        assert(isAllZeroBits!(Float, 0.0));
        assert(!isAllZeroBits!(Float, -0.0));
        assert(!isAllZeroBits!(Float, Float.nan));
    }

    static assert(isAllZeroBits!(void*, null));
    static assert(isAllZeroBits!(int*, null));
    static assert(isAllZeroBits!(Object, null));
}

@nogc nothrow pure @safe unittest // large static arrays
{
    import std.meta : Repeat;
    enum n = 16 * 1024;

    static assert(isAllZeroBits!(ubyte[n], (ubyte[n]).init));
    static assert(!isAllZeroBits!(ubyte[n], [Repeat!(n, 1)]));
    static assert(!isAllZeroBits!(ubyte[n], [1, Repeat!(n - 1, 0)]));
    static assert(!isAllZeroBits!(ubyte[n], [Repeat!(n - 1, 0), 1]));

    static assert(!isAllZeroBits!(char[n], (char[n]).init));
    static assert(isAllZeroBits!(char[n], [Repeat!(n, 0)]));
}

@nogc nothrow pure @safe unittest // nested static arrays
{
    static assert(isAllZeroBits!(int[2][2], [[0, 0], [0, 0]]));
    static assert(!isAllZeroBits!(int[2][2], [[0, 0], [1, 0]]));
}

@nogc nothrow pure @safe unittest // funky opEquals
{
    static struct AlwaysEq
    {
        int x;
        bool opEquals(AlwaysEq other) const { return true; }
    }
    static assert(AlwaysEq(0) == AlwaysEq(0));
    static assert(AlwaysEq(0) == AlwaysEq(1));
    static assert(isAllZeroBits!(AlwaysEq, AlwaysEq(0)));
    static assert(!isAllZeroBits!(AlwaysEq, AlwaysEq(1)));
    static assert(isAllZeroBits!(AlwaysEq[1], [AlwaysEq(0)]));
    static assert(!isAllZeroBits!(AlwaysEq[2], [AlwaysEq(0), AlwaysEq(1)]));

    static struct NeverEq
    {
        int x;
        bool opEquals(NeverEq other) const { return false; }
    }
    static assert(NeverEq(0) != NeverEq(1));
    static assert(NeverEq(0) != NeverEq(0));
    static assert(isAllZeroBits!(NeverEq, NeverEq(0)));
    static assert(!isAllZeroBits!(NeverEq, NeverEq(1)));
    static assert(isAllZeroBits!(NeverEq[1], [NeverEq(0)]));
    static assert(!isAllZeroBits!(NeverEq[2], [NeverEq(0), NeverEq(1)]));
}

/+
Is the representation of T.init known at compile time to consist of nothing but
zero bits? Padding between a struct's fields is not considered.
+/
package template isInitAllZeroBits(T)
{
    static if (isStaticArray!T && __traits(compiles, T.init[0]))
        enum isInitAllZeroBits = __traits(compiles, {
            static assert(isAllZeroBits!(typeof(T.init[0]), T.init[0]));
        });
    else
        enum isInitAllZeroBits = __traits(compiles, {
            static assert(isAllZeroBits!(T, T.init));
        });
}

@nogc nothrow pure @safe unittest
{
    static assert(isInitAllZeroBits!(Object));
    static assert(isInitAllZeroBits!(void*));
    static assert(isInitAllZeroBits!uint);
    static assert(isInitAllZeroBits!(uint[2]));

    static assert(!isInitAllZeroBits!float);
    static assert(isInitAllZeroBits!(float[0]));
    static assert(!isInitAllZeroBits!(float[2]));

    static struct S1
    {
        int a;
    }
    static assert(isInitAllZeroBits!S1);

    static struct S2
    {
        int a = 1;
    }
    static assert(!isInitAllZeroBits!S2);

    static struct S3
    {
        S1 a;
        int b;
    }
    static assert(isInitAllZeroBits!S3);
    static assert(isInitAllZeroBits!(S3[2]));

    static struct S4
    {
        S1 a;
        S2 b;
    }
    static assert(!isInitAllZeroBits!S4);

    static struct S5
    {
        real r = 0;
    }
    static assert(isInitAllZeroBits!S5);

    static struct S6
    {

    }
    static assert(isInitAllZeroBits!S6);

    static struct S7
    {
        float[0] a;
    }
    static assert(isInitAllZeroBits!S7);

    static class C1
    {
        int a = 1;
    }
    static assert(isInitAllZeroBits!C1);

    // Ensure Tuple can be read.
    import std.typecons : Tuple;
    static assert(isInitAllZeroBits!(Tuple!(int, int)));
    static assert(!isInitAllZeroBits!(Tuple!(float, float)));

    // Ensure private fields of structs from other modules
    // are taken into account.
    import std.random : Mt19937;
    static assert(!isInitAllZeroBits!Mt19937);
    // Check that it works with const.
    static assert(isInitAllZeroBits!(const(Mt19937)) == isInitAllZeroBits!Mt19937);
    static assert(isInitAllZeroBits!(const(S5)) == isInitAllZeroBits!S5);
}

/+
Can the representation be determined at compile time to consist of nothing but
1 bits? This is reported as $(B false) for structs with padding between
their fields because `opEquals` and hashing may rely on those bits being
zero.

Note:
A bool occupies 8 bits so `isAllOneBits!(bool, true) == false`

See_Also:
https://forum.dlang.org/post/hn11oh$1usk$1@digitalmars.com
+/
private template isAllOneBits(T, T value)
{
    static if (isIntegral!T || isSomeChar!T)
    {
        import core.bitop : popcnt;
        static if (T.min < T(0))
            enum isAllOneBits = popcnt(cast(Unsigned!T) value) == T.sizeof * 8;
        else
            enum isAllOneBits = popcnt(value) == T.sizeof * 8;
    }
    else static if (isStaticArray!(typeof(value)))
    {
        enum isAllOneBits = ()
        {
            bool b = true;
            // Use index so this works when T.length is 0.
            static foreach (i; 0 .. T.length)
            {
                b &= isAllOneBits!(typeof(value[i]), value[i]);
                if (b == false) return b;
            }

            return b;
        }();
    }
    else static if (is(typeof(value) == struct))
    {
        enum isAllOneBits = ()
        {
            bool b = true;
            size_t fieldSizeSum = 0;
            static foreach (e; value.tupleof)
            {
                b &= isAllOneBits!(typeof(e), e);
                if (b == false) return b;
                fieldSizeSum += typeof(e).sizeof;
            }
            // If fieldSizeSum == T.sizeof then there can be no gaps
            // between fields.
            return b && fieldSizeSum == T.sizeof;
        }();
    }
    else
    {
        enum isAllOneBits = false;
    }
}

// If `isAllOneBits` becomes public document this unittest.
@nogc nothrow pure @safe unittest
{
    static assert(isAllOneBits!(char, 0xff));
    static assert(isAllOneBits!(wchar, 0xffff));
    static assert(isAllOneBits!(byte, cast(byte) 0xff));
    static assert(isAllOneBits!(int, 0xffff_ffff));
    static assert(isAllOneBits!(char[4], [0xff, 0xff, 0xff, 0xff]));

    static assert(!isAllOneBits!(bool, true));
    static assert(!isAllOneBits!(wchar, 0xff));
    static assert(!isAllOneBits!(Object, Object.init));
}

// Don't document this unittest.
@nogc nothrow pure @safe unittest
{
    import std.meta : AliasSeq;
    foreach (Int; AliasSeq!(char, wchar, byte, ubyte, short, ushort, int, uint,
        long, ulong))
    {
        static assert(isAllOneBits!(Int, cast(Int) 0xffff_ffff_ffff_ffffUL));
        static assert(!isAllOneBits!(Int, Int(1)));
        static if (Int.sizeof > 1)
            static assert(!isAllOneBits!(Int, cast(Int) 0xff));
    }
    static assert(!isAllOneBits!(dchar, 0xffff));
}

/+
Can the representation be determined at compile time to consist of nothing but
1 bits? This is reported as $(B false) for structs with padding between
their fields because `opEquals` and hashing may rely on those bits being
zero.

See_Also:
https://forum.dlang.org/post/hn11oh$1usk$1@digitalmars.com
+/
package template isInitAllOneBits(T)
{
    static if (isStaticArray!T && __traits(compiles, T.init[0]))
        enum isInitAllOneBits = __traits(compiles, {
            static assert(isAllOneBits!(typeof(T.init[0]), T.init[0]));
        });
    else
        enum isInitAllOneBits = __traits(compiles, {
            static assert(isAllOneBits!(T, T.init));
        });
}

@nogc nothrow pure @safe unittest
{
    static assert(isInitAllOneBits!char);
    static assert(isInitAllOneBits!wchar);
    static assert(!isInitAllOneBits!dchar);

    static assert(isInitAllOneBits!(char[4]));
    static assert(!isInitAllOneBits!(int[4]));
    static assert(!isInitAllOneBits!Object);

    static struct S1
    {
        char a;
        char b;
    }
    static assert(isInitAllOneBits!S1);

    static struct S2
    {
        char a = 1;
    }
    static assert(!isInitAllOneBits!S2);

    static struct S3
    {
        S1 a;
        char b;
    }
    static assert(isInitAllOneBits!S3);
    static assert(isInitAllOneBits!(S3[2]));

    static struct S4
    {
        S1 a;
        S2 b;
    }
    static assert(!isInitAllOneBits!S4);

    static struct S5
    {
        int r = 0xffff_ffff;
    }
    static assert(isInitAllOneBits!S5);

    // Verify that when there is padding between fields isInitAllOneBits is false.
    static struct S6
    {
        align(4) char a;
        align(4) char b;
    }
    static assert(!isInitAllOneBits!S6);

    static class C1
    {
        char c;
    }
    static assert(!isInitAllOneBits!C1);
}
