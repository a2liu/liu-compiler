#import "Basic";

BucketList :: struct {
    len : s64;
    idx : s64;
    next : *BucketList;
    allocator: Allocator;
    allocator_data: *void;

    MIN_SIZE :: 64 * 1024 * 1024;

    make :: (size: s64 = MIN_SIZE, allocator: Allocator = null, allocator_data: *void = null) -> *BucketList {
        buckets := cast(*BucketList) NewArray(size_of(BucketList) + size, u8).data;
        buckets.len = size;
        buckets.idx = 0;
        buckets.next = null;
        if allocator == null {
            buckets.allocator = context.allocator;
            buckets.allocator_data = context.allocator_data;
        } else {
            buckets.allocator = allocator;
            buckets.allocator_data = allocator_data;
        }

        return buckets;
    }

    alloc :: (buckets: *BucketList, size: s64) -> *void {
        assert(buckets != null);
        push_allocator(buckets.allocator, buckets.allocator_data);

        b := buckets;
        while size + b.idx > b.len {
            if b.next == null {
                new_size := max(buckets.len * 2, size);
                b.next = cast(*BucketList) NewArray(size_of(BucketList) + new_size, u8).data;
                b = b.next;
                b.len = size;
                b.idx = 0;
                b.next = null;
                break;
            }

            b = b.next;
        }

        base := cast(*u8) *b[1];
        slot := *base[b.idx];
        b.idx += size;
        if b != buckets {
            buckets.next = b;
        }

        return slot;
    }

    free_all :: (buckets: *BucketList) {
        b := buckets;
        push_allocator(buckets.allocator, buckets.allocator_data);
        while b {
            free(b);
            b = b.next;
        }
    }
}

#add_context buckets : *BucketList = null;

bucket_allocator :: (mode: Allocator_Mode, size: s64, old_size: s64,
                     old_memory_pointer: *void, allocator_data: *void) -> *void {
    assert(mode == .ALLOCATE);

    b := cast(*BucketList) allocator_data;
    return BucketList.alloc(b, size);
}

Buck :: ($T: Type, $initialized := true) -> *T {
    push_allocator(bucket_allocator, context.buckets);
    return New(T, initialized = initialized);
}

BuckArray :: (count: s64, $T: Type, $initialized := true) -> [] T {
    push_allocator(bucket_allocator, context.buckets);
    return NewArray(count, T, initialized = initialized);
}
