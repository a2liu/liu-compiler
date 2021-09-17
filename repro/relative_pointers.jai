#import "Basic";

Value :: struct {
    next : *~s32 Value;
}

BigValue :: struct {
    using _base : Value;
}

#run main();
main :: () {
    values := NewArray(4, BigValue);

    value1 : *Value = *values[0];
    value2 : *Value = *values[1];
    value1_big := *values[2];
    value2_big := *values[3];
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
