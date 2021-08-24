// Heavily based on Hash_Map implementation from beta 79

// We expose these reserved hash values just in case you want
// to write your own hash map iterator.

Map :: struct(Key: Type, Value: Type, Hasher: Type = SipHash(),
                 given_compare_function: (Key, Key) -> bool = null,
                 LOAD_FACTOR_PERCENT: u32 = 70) {
    // If you leave compare_function null, the map will use operator ==.

    EMPTY_HASH :: 0;
    REMOVED_HASH :: 1;
    FIRST_VALID_HASH :: 2;
    SIZE_MIN :: 32;

    Entry :: struct {
        hash:  u64;
        key:   Key;
        value: Value;
    }

    count:        s64 = 0;   // The number of valid items in the map.
    slots_filled: s64 = 0;   // The number of slots that can't be used for new items (either currently valid, or items that were removed).
    entries: [] Entry; @--- // For performance reasons, this array is created uninitialized, so don't try to print it.

    allocator:      Allocator = null;
    allocator_data: *void = null;


    hasher : Hasher;

    // We either use the compare function that was passed to us, or,
    // if it was null, we use a default one.
    #if given_compare_function {
        compare_function :: given_compare_function;
    } else {
        compare_function :: (a: Key, b: Key) -> bool { return a == b; };
    }
}

empty_map :: ($Key: Type, $Value: Type, capacity : s64 = 0, hasher: $Hasher = SipHash().{},
                allocator : Allocator = null, allocator_data : *void = null,
                $given_compare_function: (Key, Key) -> bool = null,
                $load_factor_percent: u32 = 70)
                -> Map(Key, Value, Hasher, given_compare_function, load_factor_percent)
{
    map : Map(Key, Value, Hasher, given_compare_function, load_factor_percent);
    map.entries.count = 0;
    map.entries.data = null;

    if allocator {
        map.allocator = allocator;
        map.allocator_data = allocator_data;
    } else {
        map.allocator = context.allocator;
        map.allocator_data = context.allocator_data;
    }

    if capacity     map_resize(*map, capacity);
    return map;
}

// map_reserve :: (map: *$T/Map, additional: s64) {
//     if map.count + additional <= map.entries.count
//         return;
// 
//     asked_for := map.count + additional;
//     new_capacity := max(asked_for, map.SIZE_MIN);
// }

for_expansion :: (map: *$T/Map, body: Code, flags: For_Flags) #expand {
    #assert(!(flags & .REVERSE)); // We don't handle the reverse flag.

    for * entry, i: map.entries {
        if entry.hash < map.FIRST_VALID_HASH  continue;

        #if flags & .POINTER {
            `it := *entry.value;
        } else {
            `it := entry.value;
        }

        `it_index := entry.key;

        #insert (remove={entry.hash=map.REMOVED_HASH; map.count-=1;}) body;
    }
}

map_resize :: (using map: *Map, slots_to_allocate: s64 = 0) {
    if slots_to_allocate == 0 slots_to_allocate = SIZE_MIN;
    n := next_power_of_two(slots_to_allocate);

    // Right now we align to 8 bytes. Should we handle arbitrary alignment of both
    // keys and values? Maybe, but that will complicate the map,
    // so let's not worry about it now unless we need it.

    entries = NewArray(n, Entry, false, map.allocator, map.allocator_data);
    for * entries  it.hash = 0;
}

// Frees the memory allocated by the map.
map_deinit :: (map: *Map) {
    free(map.entries.data, map.allocator, map.allocator_data);
}

// This reset keeps the current number of allocated slots;
// it just clears occupancy.
// @@ IC: I like this behavior, but array_reset frees memory and that is confusing. See array_reset for more discussion.
map_reset :: (using map: *Map) {
    count        = 0;
    slots_filled = 0;
    for * entries  it.hash = 0;
}

// Adds the given key value pair to the map, returns a pointer to the inserted value.
// If you add a key twice, the map will not currently notice that this has happened,
// so you'll just get the first one. It's unclear whether we should assert on this;
// it sort of depends on how slow you think key comparison might be. Maybe that should
// be a compile-time parameter to the hash map?   -jblow, 8 September 2020
map_add :: (map: *Map, key: map.Key_Type, value: map.Value_Type) -> *map.Value_Type {
    // The + 1 is here to handle the weird case when the map size is 1 and you add the first item...
    // If we just do map_count * 2 >= map.entries.count, we would fill the map, causing an infinite loop on find.

    #assert map.LOAD_FACTOR_PERCENT < 100;  // A 100% full map will infinite loop (and, you will want to be substantially smaller than this for reasonable performance).

    // filled / allocated >= 70/100 ... therefore
    // filled * 100 >= allocated * 70
    if (map.slots_filled + 1)*100 >= map.entries.count * map.LOAD_FACTOR_PERCENT  expand(map);

    assert(map.slots_filled <= map.entries.count);

    hash := map.hash_function(key);
    if hash < map.FIRST_VALID_HASH  hash += map.FIRST_VALID_HASH;

    index := hash & (map.entries.count - 1);
    probe_increment: u32 = 1;

    while map.entries[index].hash {
        index += probe_increment;
        probe_increment += 1;
        while index >= map.entries.count  index -= map.entries.count;
    }

    map.count        += 1;
    map.slots_filled += 1;

    entry := *map.entries[index];
    entry.hash  = hash;
    entry.key   = key;
    entry.value = value;

    return *entry.value;
}

// Adds or replaces the given key value pair.
map_set :: (map: *Map, key: map.Key_Type, value: map.Value_Type) -> *map.Value_Type {
    value_ptr := map_find_pointer(<<map, key);
    if value_ptr {
        <<value_ptr = value;
        return value_ptr;
    } else {
        return map_add(map, key, value);
    }
}

// Lookup the given key and return a pointer to the corresponding value.
map_find_pointer :: (map: Map, key: map.Key_Type) -> *map.Value_Type {
    if !map.entries.count  return null;

    hash := map.hash_function(key);
    if hash < map.FIRST_VALID_HASH  hash += map.FIRST_VALID_HASH;

    index := hash & (map.entries.count - 1);
    probe_increment: u32 = 1;

    while map.entries[index].hash {
        entry := *map.entries[index];
        if entry.hash == hash {
            if map.compare_function(entry.key, key)  return *entry.value;
        }

        index += probe_increment;
        probe_increment += 1;
        while index >= map.entries.count  index -= map.entries.count;
    }

    return null;
}

// Lookup the given key and return the corresponding value.
//
// You need to pay attention to 'success' because if it's false, 
// the return value will be uninitialized. Thus the `#must`.
//
map_find :: (map: Map, key: map.Key_Type) -> (map.Value_Type, success: bool #must) {
    pointer := inline map_find_pointer(map, key);
    if pointer  return << pointer, true;

    dummy: map.Value_Type = ---;
    return dummy, false;
}

// Remove the entry at the given key. Returns false if the key was not found.
map_remove :: (map: *Map, key: map.Key_Type) -> (success: bool, value: map.Value_Type) {
    hash := map.hash_function(key);
    if hash < map.FIRST_VALID_HASH  hash += map.FIRST_VALID_HASH;

    dummy: map.Value_Type = ---;
    if !map.entries.count  return false, dummy;  // Empty map, means not found!

    index := hash & (map.entries.count - 1);
    probe_increment: u32 = 1;

    while map.entries[index].hash {
        entry := *map.entries[index];

        if (entry.hash == hash) && map.compare_function(entry.key, key) {
            entry.hash = map.REMOVED_HASH;  // No valid entry will ever hash to REMOVED_HASH.
            map.count -= 1;
            return true, entry.value;
        }

        index += probe_increment;
        probe_increment += 1;
        while index >= map.entries.count  index -= map.entries.count;
    }

    return false, dummy;
}

// A beta user requested being able to call expand(), so, here:
expand :: (map: *Map) {
    old_entries := map.entries;

    // If we were adding and removing lots of stuff from the map,
    // we might have lots of slots filled with REMOVED_HASH, so,
    // in that case, don't grow!
    new_allocated: s64 = ---;
    if map.count * 2 < map.entries.count {
        // Just go with the current size, but clean out the removals.
        new_allocated = map.entries.count;
    } else {
        // We need to go deeper!
        new_allocated = map.entries.count * 2;
    }

    if new_allocated < map.SIZE_MIN  new_allocated = map.SIZE_MIN;

    resize(map, new_allocated);

    map.count        = 0;   // count and slots_filled will be incremented by map_add.
    map.slots_filled = 0;

    for * entry, index: old_entries {
        // Note that if we removed some stuff, we will over-allocate the next map.
        // Maybe we should count the number of clobbers and subtract that. I dunno.
        if entry.hash >= map.FIRST_VALID_HASH  map_add(map, entry.key, entry.value);
    }

    free(old_entries.data, map.allocator, map.allocator_data);
}

test :: () {}

#scope_file

next_power_of_two :: inline (x : int) -> int {
    p := 1;
    while x > p p += p;
    return p;
}

#import "hasher";
#import "Basic";
