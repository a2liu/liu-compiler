#import "Basic";
#import "Bit_Array";
Math :: #import "Math";

mem_eq :: (a: *$T, b: *T) -> bool {
  build_bitset :: (info: *$T) -> string {
    bit_array : Bit_Array;
    init_bit_array(*bit_array, info.runtime_size);
    set_all_bits(*bit_array);

    return sprint("Bit_Array.{ slots = s64.%, count = % };", bit_array.slots, bit_array.count);
  }

  build_bitset :: (info: *Type_Info_Struct) -> string {
    bit_array : Bit_Array;
    init_bit_array(*bit_array, info.runtime_size);

    for info.members {
      offset := it.offset_in_bytes;
      size := it.type.runtime_size;

      for index: offset..offset+size-1 set_bit(*bit_array, index);
    }

    return sprint("Bit_Array.{ slots = s64.%, count = % };", bit_array.slots, bit_array.count);
  }

  bit_array :: #insert #run build_bitset(type_info(T));

  mem_a, mem_b := cast(*u8) a, cast(*u8) b;
  for :only_set bit_array {
    if mem_a[it_index] != mem_b[it_index] return false;
  }

  return true;
}

Cond :: struct (code: Code) {}
for_expansion :: (cond: *Cond, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    for iterator : 0..Math.S64_MAX {
        `it_index := iterator;
        `it := #insert cond.code;

        if it   #insert body;
        else    break;
    }
}

test :: () {
    // i := 0;
    // for_expansion(i < 12, #code { print("% ", it_index); i += 1; continue; }, 0);
    // print("\n");

    a := 0;
    for Cond(#code a < 12).{} {
        print("(% % % %) ", it_index, a, it, type_of(it));
        a += 1;
    }
    print("\n");

    array : Bit_Array;
    init_bit_array(*array, 10);
    set_all_bits(*array);
    for array {
        print("% ", it);
    }
    print("\n");

    Custom :: struct {
        a := true;
        b := 12;
        c := true;
        d := 12;
    }

    a_custom, b_custom : Custom;

    assert(mem_eq(*a_custom, *b_custom), "% and % should be equal", a_custom, b_custom);
    a_custom.b += 1;
    assert(!mem_eq(*a_custom, *b_custom), "% and % should not be equal", a_custom, b_custom);
    a_custom.b -= 1;

    (cast(*u8) *a_custom.a)[1] = 1;
    assert(mem_eq(*a_custom, *b_custom), "% and % should be equal", a_custom, b_custom);

    a_int, b_int : int = 12, 12;
    assert(mem_eq(*a_int, *b_int), "% and % should be equal", a_int, b_int);
    a_int += 1;
    assert(!mem_eq(*a_int, *b_int), "% and % should not be equal", a_int, b_int);

    print("utils test passed\n");
}
