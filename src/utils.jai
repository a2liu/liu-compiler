#import "Basic";
#import "Bit_Array";

view_set_bits :: (array: *Bit_Array, body: Code, flags: For_Flags, target_value: bool) #expand {
    #assert(!flags);  // No options are supported.

    `it := true; // 'it' will just be true, or false, always.

    for slot, slot_index: array.slots {
        #if !target_value slot = ~slot;   // Static 'if' ... no runtime cost if false.
        if !slot  continue;

        base_index := slot_index * 64;

        bit := 1;
        for i: 0..63 {
            `it_index := base_index + i;
            if it_index >= array.count break slot;

            if slot & bit #insert (remove=#assert(false), break=break slot) body;
            bit = bit << 1;
        }
    }
}

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
  for :view_set_bits bit_array {
    if mem_a[it_index] != mem_b[it_index] return false;
  }

  return true;
}

Custom :: struct {
  a := true;
  b := 12;
  c := true;
  d := 12;
}

test :: () {
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

#run test();
