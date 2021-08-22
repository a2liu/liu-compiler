#import "Bit_Operations";

// @Api this should probably be split up into a set of keys and a set of round
// configs, because round config is usually picked at compile time.
SipHash :: struct {
  k0 : u64 = 0;
  k1 : u64 = 0;
  rounds_per_block := 2;
  finalization_rounds := 4;
}

hash :: (state: *SipHash, data: [] u8) -> u64, u64 {;
    // Initialization
    v0 := state.k0 ^ 0x736f6d6570736575;
    v1 := state.k1 ^ 0x646f72616e646f6d;
    v2 := state.k0 ^ 0x6c7967656e657261;
    v3 := state.k1 ^ 0x7465646279746573;

    blocks_count := data.count >> 3;
    blocks : [] u64 = ---;
    blocks.data = cast(*u64) data.data;
    blocks.count = blocks_count;

    v1 ^= 0xee;
    // @Todo lmao im ignoring endianness for now, but whatevs tbh, just insert a
    // call to `from_little_endian` or something
    for blocks {
        v0, v1, v2, v3 = block_rounds(v0, v1, v2, v3, num_rounds = state.rounds_per_block, data = it);
    }

    // @Todo this also ignores whatever endianness garbage this hash did before.
    // Same as before, add a a call to `from_little_endian` to fix this.
    blocks_count_bytes := blocks_count << 3;
    tail_count := data.count - blocks_count_bytes;
    tail_data : union { array: [8] u8; value: u64; };
    memcpy(data.data + blocks_count_bytes, tail_data.array.data, tail_count);
    t : u64 = (cast(u64) data.count) << 56;
    t |= tail_data.value;

    v0, v1, v2, v3 = block_rounds(v0, v1, v2, v3, num_rounds = state.rounds_per_block, data = t);

    // Finalization
    v2 ^= 0xee;
    v0, v1, v2, v3 = rounds(v0, v1, v2, v3, num_rounds = state.finalization_rounds);
    r0 := v0 ^ v1 ^ v2 ^ v3;

    v1 ^= 0xdd;
    v0, v1, v2, v3 = rounds(v0, v1, v2, v3, num_rounds = state.finalization_rounds);
    r1 := v0 ^ v1 ^ v2 ^ v3;

    return r0, r1;

    rotate_left :: inline (v: u64, shift_by: u8) -> u64 {
        return (v << shift_by) | (v >> (64 - shift_by));
    }

    rounds :: inline (v0 : u64, v1 : u64, v2 : u64, v3 : u64, num_rounds: s64) -> u64, u64, u64, u64 {
      for 1..num_rounds {
          v0 += v1;
          v1 = rotate_left(v1, 13);
          v1 ^= v0;
          v0 = rotate_left(v0, 32);

          v2 += v3;
          v3 = rotate_left(v3, 16);
          v3 ^= v2;

          v0 += v3;
          v3 = rotate_left(v3, 21);
          v3 ^= v0;

          v2 += v1;
          v1 = rotate_left(v1, 17);
          v1 ^= v2;
          v2 = rotate_left(v2, 32);
      }

      return v0, v1, v2, v3;
    }

    block_rounds :: inline (v0 : u64, v1 : u64, v2 : u64, v3 : u64, num_rounds: s64, data: u64) -> u64, u64, u64, u64 {
        v3 ^= data;

        v0, v1, v2, v3 = rounds(v0, v1, v2, v3, num_rounds = num_rounds);

        v0 ^= data;

        return v0, v1, v2, v3;
    }
}
