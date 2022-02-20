#import "Basic";
#import "write";

// Based on Basic.String_Builder from Beta 76
StringBuilder :: struct {
    Buffer :: struct {
        occupied : s64 = 0;
        next : *Buffer = null;
        data : [BUFFER_SIZE] u8 = ---;
    }

    inline_data : [64] u8;
    inline_occupied : s64; // marker for inline buffer and also number of buffers in linked list
    first_buffer : *Buffer;
    current_buffer : *Buffer;
    allocator : Allocator;

    try_write :: (builder: *StringBuilder, data: []u8) -> bool {
        if !builder.allocator.proc init(builder);

        eat :: (data: [] u8, index: s64) -> [] u8, [] u8 {
            assert(0 <= index);

            idx := min(index, data.count);
            begin, end : [] u8 = data, data;
            begin.count = idx;
            end.data += idx;
            end.count -= idx;

            return begin, end;
        }

        to_write := data;
        current : [] u8 = ---;

        if builder.inline_occupied < builder.inline_data.count {
            current, to_write = eat(to_write, builder.inline_data.count - builder.inline_occupied);
            memcpy(builder.inline_data.data + builder.inline_occupied, current.data, current.count);
            builder.inline_occupied += current.count;
        }

        buffer := builder.current_buffer;
        while to_write.count > 0 {
            if !buffer || buffer.occupied >= buffer.data.count      buffer = expand(builder);

            current, to_write = eat(to_write, buffer.data.count - buffer.occupied);
            memcpy(buffer.data.data + buffer.occupied, current.data, current.count);
            buffer.occupied += current.count;
        }

        return true;
    }

    make :: () -> StringBuilder {
        builder : StringBuilder;
        init(*builder);
        return builder;
    }

}

init :: (builder: *StringBuilder) {
    builder.allocator = context.allocator;
}

free_buffers :: (builder: *StringBuilder) {
    buffer := builder.first_buffer;
    while buffer {
        next := buffer.next;
        free(buffer, builder.allocator);
        buffer = next;
    }

    builder.inline_occupied = 0;
    builder.first_buffer = null;
    builder.current_buffer = null;
}

clear_contents :: (builder: *StringBuilder) {
    builder.inline_occupied = 0;
    builder.current_buffer = builder.first_buffer;
    if builder.current_buffer   builder.current_buffer.occupied = 0;
}

to_string :: (builder: *StringBuilder, allocator := context.allocator) -> string {
    if builder.inline_occupied == 0 return "";

    if builder.inline_occupied <= builder.inline_data.count {
        result : string = ---;
        result.data  = alloc(builder.inline_occupied, allocator);
        result.count = builder.inline_occupied;
        memcpy(result.data, builder.inline_data.data, result.count);

        return result;
    }


    buffer_count := builder.inline_occupied - builder.inline_data.count;
    buffers_size := BUFFER_SIZE * (buffer_count - 1) + builder.current_buffer.occupied;
    string_count := builder.inline_data.count + buffers_size;

    result : string = ---;
    result.data  = alloc(string_count, allocator);
    assert(result.data != null);
    result.count = string_count;

    cursor := result.data;
    memcpy(cursor, builder.inline_data.data, builder.inline_data.count);
    cursor += builder.inline_data.count;

    buffer := builder.first_buffer;
    while buffer && buffer.occupied != 0 {
        memcpy(cursor, buffer.data.data, buffer.occupied);
        cursor += buffer.occupied;
        buffer = buffer.next;
    }

    assert(cursor == result.data + string_count);

    return result;
}

#scope_file

Buffer :: StringBuilder.Buffer;
// BUFFER_SIZE :: 16_384;
BUFFER_SIZE :: 16;

expand :: (builder: *StringBuilder) -> *Buffer #expand {
    if !builder.allocator.proc    init(builder);

    if builder.current_buffer && builder.current_buffer.next {
        buffer := builder.current_buffer.next;
        builder.current_buffer = buffer;
        builder.inline_occupied += 1;
        buffer.occupied = 0;

        return buffer;
    }

    buffer := cast(*Buffer) alloc(size_of(Buffer), builder.allocator);
    if !buffer  `return false;

    buffer.occupied = 0;
    buffer.next = null;

    if builder.current_buffer != null   builder.current_buffer.next = buffer;
    else                                builder.first_buffer = buffer;

    builder.inline_occupied += 1;
    builder.current_buffer = buffer;
    return buffer;
}

#scope_export

// -------------------------------------
//
// STRING FUNCTIONS
//
// -------------------------------------

cut_at :: (s: string, index: s64) -> string, string {
    assert(0 <= index);
    assert(index <= s.count);

    begin, end : string = s, s;
    begin.count = index;
    end.data += index;
    end.count -= index;

    return begin, end;
}

test :: () {
    hello, world := cut_at("hello world!", 5);
    assert(hello == "hello");
    assert(world == " world!");

    builder : StringBuilder;
    init(*builder);
    for 0..10 {
        write(*builder, "Hello,");
        write(*builder, " World!  ");
    }
    write(*builder, "\n");
    s := to_string(*builder);
    print(s);

    print("strings test passed\n");
}
