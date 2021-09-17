#import "Basic";

Value :: struct {
    kind: enum { BASE; BIG; } = .BASE;
    next : *~s32 Value;
}

BigValue :: struct {
    using _base : Value;
}

BumpAlloc :: struct {
    bytes : [] u8;
    bump : s64;
}

bump_alloc :: (bump: *BumpAlloc, $T: Type) -> *T {
    size := size_of(T);
    pointer := *bump.bytes[bump.bump];
    bump.bump += size;
    ini :: initializer_of(T);
    memset(pointer, 0, size);

    return cast(*T) pointer;
}

#run main();
main :: () {
    bump : BumpAlloc;
    bump.bytes = NewArray(1000, u8);
    value1 := bump_alloc(*bump, Value);
    value2 := bump_alloc(*bump, Value);
    value1_big := bump_alloc(*bump, BigValue);
    value2_big := bump_alloc(*bump, BigValue);
    value1_next : *Value;
    value1_big_next : *Value;

    value1.next = value2;
    value1_next = value1.next;
    assert(value1_next == value2, "value1_next != value2 (% != %)", value1_next, value2);

    value1_big.next = value2;
    value1_big_next = value1_big.next;
    assert(value1_big_next == value2, "value1_big_next != value2 (% != %)", value1_big_next, value2);

    value1.next = value2_big;
    value1_next = value1.next;
    assert(value1_next == value2_big, "value1_next != value2_big (% != %)", value1_next, value2_big);

    value1_big.next = value2_big;
    value1_big_next = value1_big.next;
    assert(value1_big_next == value2_big, "value1_big_next != value2_big (% != %)", value1_big_next, value2_big);
}
