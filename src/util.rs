pub use aliu::*;
use alloc::alloc::Layout;
use core::cell::Cell;
use core::marker::PhantomData;
use core::ptr::NonNull;
use core::sync::atomic::{AtomicUsize, Ordering};
pub use std::collections::hash_map::HashMap;

#[repr(C)]
pub struct HeapArrayData<Tag, Item>
where
    Item: Copy,
{
    pub tag: Tag,
    pub items: [Item],
}

pub struct HeapArray<Tag, Item, A>
where
    Item: Copy,
    A: Allocator,
{
    data: NonNull<HeapArrayData<Tag, Item>>,
    alloc: A,
}

impl<Tag, Item> HeapArray<Tag, Item, Global>
where
    Item: Copy,
{
    #[inline]
    pub fn new(tag: Tag, items: &[Item]) -> Self {
        return Self::with_allocator(tag, items, Global);
    }
}

impl<Tag, Item, A> HeapArray<Tag, Item, A>
where
    Item: Copy,
    A: Allocator,
{
    fn layout(len: usize) -> Layout {
        #[repr(C)]
        pub struct Data<Tag, Item>
        where
            Item: Copy,
        {
            t: Tag,
            i: Item,
        }

        let align = core::mem::align_of::<Data<Tag, Item>>();
        let size = core::mem::size_of::<Data<Tag, Item>>();
        let item_size = core::mem::size_of::<Item>();
        let size = size - item_size + item_size * len;

        return unsafe { Layout::from_size_align_unchecked(size, align) };
    }

    pub fn with_allocator(tag: Tag, items: &[Item], a: A) -> Self {
        unsafe {
            let ptr = match a.allocate(Self::layout(items.len())) {
                Ok(mut p) => p.as_mut(),
                Err(e) => panic!("rip"),
            };

            let ptr = ptr.as_mut_ptr() as *mut Item;
            let data = core::slice::from_raw_parts_mut(ptr, items.len());
            let data = data as *mut [Item] as *mut HeapArrayData<Tag, Item>;

            let data = &mut *data;

            core::ptr::write(&mut data.tag, tag);
            data.items.copy_from_slice(items);

            let data = NonNull::new_unchecked(data);

            return Self { data, alloc: a };
        };
    }
}

impl<Tag, Item, A> Drop for HeapArray<Tag, Item, A>
where
    Item: Copy,
    A: Allocator,
{
    fn drop(&mut self) {
        unsafe {
            let data = self.data.as_mut();
            let layout = Self::layout(data.items.len());

            core::ptr::drop_in_place(data);

            let data = self.data.cast::<u8>();
            self.alloc.deallocate(data, layout);
        }
    }
}

impl<Tag, Item, A> core::ops::Deref for HeapArray<Tag, Item, A>
where
    Item: Copy,
    A: Allocator,
{
    type Target = HeapArrayData<Tag, Item>;

    fn deref(&self) -> &Self::Target {
        unsafe {
            return self.data.as_ref();
        }
    }
}

impl<Tag, Item, A> core::ops::DerefMut for HeapArray<Tag, Item, A>
where
    Item: Copy,
    A: Allocator,
{
    fn deref_mut(&mut self) -> &mut Self::Target {
        unsafe {
            return self.data.as_mut();
        }
    }
}

#[test]
fn heap_array() {
    let mut a = Pod::new();

    for i in 0..100 {
        a.push(100 - i);
    }

    let array = HeapArray::new(Box::new(12), &a);

    assert_eq!(&*a, &array.items);
}
