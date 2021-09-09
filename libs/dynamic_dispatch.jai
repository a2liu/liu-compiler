#import "Compiler";
#import "Basic";
#import "Hash_Table";

// track all interfaces and their implementors
// generate giant switch statements after typechecking finishes

Dyn :: struct(interface_name: Type) {
    Self :: Dyn(interface_name);
    value: *void;
    // @Optimization use an enum instead of a Type object so case matching can
    // be optimized better during codegen
    type: Type;

    make :: (value: *$T) -> Self {
        out : Self;
        out.value = value;
        out.type = T;

        return out;
    }
}

Dispatch :: struct {
    InterfaceMember :: struct {
        procedure_header: *Code_Procedure_Header;
        procedure_body: *Code_Procedure_Body;
    }

    Interface :: struct {
        interface_code: *Code_Struct;
        members: Table(string, InterfaceMember, hash_string);
        implementors: [..] *Code_Struct;
    }

    is_init: bool = false;
    workspace: Workspace;
    interfaces: [..] Interface;

    make :: (workspace: Workspace, allocator: Allocator = null, allocator_data: *void = null) -> Dispatch {
        data : Dispatch;
        init(*data, workspace, allocator, allocator_data);

        return data;
    }

    init :: (data: *Dispatch, workspace: Workspace, allocator: Allocator = null, allocator_data: *void = null) {
        assert(!data.is_init);

        data.is_init = true;
        data.workspace = workspace;
    }

    message_handler :: (data: *Dispatch, msg: *Message, delay_generation: bool = false) {
        assert(msg.workspace == data.workspace, "can only get information from the current workspace");
        w := msg.workspace;
        if msg.kind == {
        case .PHASE;
            phase_msg := cast(*Message_Phase) msg;
            if phase_msg.phase == .TYPECHECKED_ALL_WE_CAN {
                log("Typechecked all we can!\n");
            }

        case .TYPECHECKED;
            typechecked_msg := cast(*Message_Typechecked) msg;

            for typechecked : typechecked_msg.structs {
                struct_definition := typechecked.expression;
                // if struct_definition.constants_block {
                //     for struct_definition.constants_block.members {
                //         log("constant member is named %\n", it.name);
                //     }
                // }

                if struct_definition.block {
                    for member: struct_definition.block.members {
                        if member.kind != .DECLARATION
                            continue;

                        decl := cast(*Code_Declaration) member;
                        if !(decl.flags & .IS_CONSTANT)
                            continue;
                        if !decl.expression     // no idea why this is sometimes false, but it is
                            continue;

                        log("member is named % with expression %\n", member.name, decl.expression.kind);
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------------------------
// Hashing arbitrary data using siphash; was gonna use meowhash but this was
// easier to implement
// ------------------------------------------------------------------------------------

SipHashState :: struct(rounds_per_block : s64 = 2, finalization_rounds : s64 = 4) {
    v0 : u64;
    v1 : u64;
    v2 : u64;
    v3 : u64;
}

SipHash :: struct(rounds_per_block : s64 = 2, finalization_rounds : s64 = 4) {
  k0 : u64 = 0;
  k1 : u64 = 0;
}

hash_string :: (key: string) -> u32 {
    initial : SipHash();
    hasher := start_partial(initial);

    bytes : [] u8 = ---;
    bytes.data = cast(*u8) key.data;
    bytes.count = key.count * 8;
    hash_partial(*hasher, bytes);

    upper, lower := hash_partial_read(*hasher);
    return cast,trunc(u32) lower;
}

hash_sorted_hashes :: (key: [] u64) -> u32 {
    hasher : SipHash();
    bytes : [] u8 = ---;
    bytes.data = cast(*u8) key.data;
    bytes.count = key.count * 8;

    upper, lower := hash(hasher, bytes);
    return cast,trunc(u32) lower;
}

hash :: (initial: SipHash, bytes: [] u8) -> u64, u64 {
    state := start_partial(initial);
    hash_partial(*state, bytes);
    upper, lower := hash_partial_read(*state);
    return upper, lower;
}

start_partial :: (initial: SipHash($per_block, $final)) -> SipHashState(per_block, final) {
    state : SipHashState(per_block, final);
    state.v0 = initial.k0 ^ 0x736f6d6570736575;
    state.v1 = initial.k1 ^ 0x646f72616e646f6d;
    state.v2 = initial.k0 ^ 0x6c7967656e657261;
    state.v3 = initial.k1 ^ 0x7465646279746573;
    state.v1 ^= 0xee;

    return state;
}

hash_partial :: (state: *SipHashState, bytes: [] u8) {
    blocks_count := bytes.count >> 3;
    blocks : [] u64 = ---;
    blocks.data = cast(*u64) bytes.data;
    blocks.count = blocks_count;

    // @Todo lmao im ignoring endianness for now, but whatevs tbh, just insert a
    // call to `from_little_endian` or something
    for blocks {
        block_rounds(state, num_rounds = state.rounds_per_block, data = it);
    }

    // @Todo this also ignores whatever endianness garbage this hash did before.
    // Same as before, add a a call to `from_little_endian` to fix this.
    blocks_count_bytes := blocks_count << 3;
    tail_count := bytes.count - blocks_count_bytes;
    tail_data : union { array: [8] u8; value: u64; };
    memcpy(tail_data.array.data, bytes.data + blocks_count_bytes, tail_count);
    t : u64 = (cast(u64) bytes.count) << 56;
    t |= tail_data.value;

    block_rounds(state, num_rounds = state.rounds_per_block, data = t);
}

hash_partial_read :: (state: *SipHashState) -> u64, u64 {
    // Finalization
    using s := << state;
    v2 ^= 0xee;
    rounds(*s, num_rounds = state.finalization_rounds);
    r0 := v0 ^ v1 ^ v2 ^ v3;

    v1 ^= 0xdd;
    rounds(*s, num_rounds = state.finalization_rounds);
    r1 := v0 ^ v1 ^ v2 ^ v3;

    return r0, r1;
}

rotate_left :: inline (v: u64, shift_by: u8) -> u64 {
    return (v << shift_by) | (v >> (64 - shift_by));
}

rounds :: inline (using state: *SipHashState, num_rounds: s64) {
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
}

block_rounds :: inline (using state: *SipHashState, num_rounds: s64, data: u64) {
    v3 ^= data;

    rounds(state, num_rounds = num_rounds);

    v0 ^= data;
}
