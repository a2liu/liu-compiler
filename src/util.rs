pub use aliu::*;
use alloc::alloc::Layout;
use core::cell::Cell;
use core::ptr::NonNull;

pub struct VirtualAlloc {
    taken: Cell<bool>,
    alloc: region::Allocation,
}

impl VirtualAlloc {
    pub fn new(size: usize) -> Self {
        let alloc = match region::alloc(size, region::Protection::READ_WRITE) {
            Ok(a) => a,
            Err(e) => {
                panic!("{:?}", e);
            }
        };

        return Self {
            taken: Cell::new(false),
            alloc,
        };
    }

    fn get_ptr(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
        let size = self.alloc.len();
        if layout.size() > size || layout.align() > region::page::size() {
            return Err(AllocError);
        }

        let ptr = self.alloc.as_ptr::<u8>() as *mut u8;
        let slice = unsafe { core::slice::from_raw_parts_mut(ptr, size) };
        let ptr = NonNull::new(slice).ok_or(AllocError)?;

        return Ok(ptr);
    }
}

unsafe impl Allocator for VirtualAlloc {
    fn allocate(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
        if self.taken.get() {
            return Err(AllocError);
        }

        let ptr = self.get_ptr(layout)?;
        self.taken.set(true);

        return Ok(ptr);
    }

    unsafe fn deallocate(&self, ptr: NonNull<u8>, layout: Layout) {
        if self.taken.get() {
            self.taken.set(false);
            return;
        }

        println!("tried to deallocate twice??");
    }

    unsafe fn grow(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocError> {
        panic!("what are you growing?");
    }

    unsafe fn grow_zeroed(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocError> {
        panic!("what are you growing?");
    }

    unsafe fn shrink(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocError> {
        panic!("what are you shrinking?");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use aliu::*;

    #[test]
    fn virtual_pod() {
        let mut pod = Pod::with_allocator(VirtualAlloc::new(4096));

        for _ in 0..512 {
            pod.push(1u64);

            println!("len={} capa={}", pod.len(), pod.capacity());
        }

        // pod.push(1u64);
        // println!("len={} capa={}", pod.len(), pod.capacity());
    }
}
