#import "Basic";

// Returned pointers always have an alignment of 8. This is all that this compiler needs.
BucketList :: struct {
    Bucket :: struct {
        len : s64;
        idx : s64;
        next : *Bucket;
    }

    allocator: Allocator = null;
    allocator_data: *void = null;
    first: *Bucket = null;
    next: *Bucket = null;

    MIN_SIZE :: 64 * 1024 * 1024;

    make :: (size: s64 = MIN_SIZE, allocator: Allocator = null, allocator_data: *void = null) -> BucketList {
        buckets : BucketList;
        init(*buckets, size, allocator, allocator_data);
        return buckets;
    }

    init :: (buckets: *BucketList, size: s64 = MIN_SIZE, allocator: Allocator = null,
             allocator_data: *void = null) {
        assert(buckets != null);
        if buckets.first != null       return;

        if allocator == null {
            buckets.allocator = context.allocator;
            buckets.allocator_data = context.allocator_data;
        } else {
            buckets.allocator = allocator;
            buckets.allocator_data = allocator_data;
        }

        bucket_size := max(size, MIN_SIZE);
        memory := NewArray(size_of(Bucket) + bucket_size, u8, allocator = buckets.allocator,
                           allocator_data = buckets.allocator_data, initialized = false);
        bucket := cast(*Bucket) memory.data;
        bucket.len = bucket_size;
        bucket.idx = align_cost(memory.data);
        bucket.next = null;
        buckets.first = bucket;
        buckets.next = bucket;
    }

    alloc :: (buckets: *BucketList, size: s64) -> *void {
        assert(buckets != null);
        assert(buckets.first != null, "BucketList must be initialized before using it");
        push_allocator(buckets.allocator, buckets.allocator_data);

        alloc_size := align_up(size);

        b := buckets.next;
        while size + b.idx > b.len {
            if b.next == null {
                new_size := max(b.len * 2, alloc_size);
                memory := NewArray(size_of(Bucket) + new_size, u8, allocator = buckets.allocator,
                                   allocator_data = buckets.allocator_data, initialized = false);
                if memory.data == null      return null;

                b.next = cast(*Bucket) memory.data;
                b = b.next;
                b.len = new_size;
                b.idx = align_cost(memory.data);
                b.next = null;
                break;
            }

            b = b.next;
        }

        base := cast(*u8) *b[1];
        slot := *base[b.idx];
        b.idx += alloc_size;
        if b != buckets.next {
            buckets.next = b;
        }

        return slot;
    }

    free_all :: (buckets: *BucketList) {
        assert(buckets != null);
        assert(buckets.first != null, "BucketList must be initialized before using it");
        push_allocator(buckets.allocator, buckets.allocator_data);

        b := buckets.first;
        while b {
            next := b.next;
            free(b);
            b = next;
        }
    }
}

bucket_allocator :: (mode: Allocator_Mode, size: s64, old_size: s64,
                     old_memory_pointer: *void, allocator_data: *void) -> *void {
    assert(mode == .ALLOCATE);

    b := cast(*BucketList) allocator_data;
    assert(b != null);
    assert(b.first != null, "BucketList must be initialized before using it");
    return BucketList.alloc(b, size);
}

#scope_file

align_up :: (value: s64) -> s64 {
    misalignment := value - (value & (~7));
    if misalignment == 0        return value;
    return 8 - misalignment + value;
}

align_cost :: (ptr: *void) -> s64 {
    value := cast(s64) ptr;
    misalignment := value - (value & (~7));
    if misalignment == 0        return 0;
    return 8 - misalignment;
}
