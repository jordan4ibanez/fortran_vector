module vector
  use, intrinsic :: iso_c_binding
  use :: fortran_vector_bindings
  implicit none


  private


  public :: vec
  public :: new_vec


  type :: vec
    private
    type(c_ptr) :: data = c_null_ptr
    integer(c_size_t) :: size_of_type = 0
    type(c_funptr) :: gc_func = c_null_funptr
  contains
    procedure :: destroy => vector_destroy
    procedure :: get => vector_get
    procedure :: set => vector_set
    procedure :: is_empty => vector_is_empty
    procedure :: size => vector_size
    procedure :: capacity => vector_capacity
    procedure :: shrink_to_fit => vector_shrink_to_fit
    procedure :: clear => vector_clear
    procedure :: insert => vector_insert
    procedure :: remove => vector_remove
    procedure :: push_back => vector_push_back
    procedure :: pop_back => vector_pop_back
    procedure :: reserve => vector_reserve
    procedure :: resize => vector_resize
    procedure :: swap => vector_swap
    procedure :: clone => vector_clone
  end type vec


contains


  !* Create a new vector.
  !* I did not create a module interface because I want you to be able to see explicitly
  !* Where you create your vector.
  function new_vec(size_of_type, initial_size, optional_gc_func) result(v)
    implicit none

    ! size_of_type allows you to simply get the size of your type before and hard code it into your program. 8)
    integer(c_size_t), intent(in), value :: size_of_type, initial_size
    procedure(vec_gc_blueprint), optional :: optional_gc_func
    type(vec) :: v

    ! This will automatically clean your memory upon deletion.
    if (present(optional_gc_func)) then
      v%gc_func = c_funloc(optional_gc_func)
    end if

    v%data = internal_new_vector(initial_size, size_of_type)

    v%size_of_type = size_of_type
  end function new_vec


  !* Destroy all components of the vector. Elements and underlying C memory.
  subroutine vector_destroy(this)
    implicit none

    class(vec), intent(inout) :: this

    if (.not. c_associated(this%data)) then
      return
    end if

    if (.not. this%is_empty()) then
      call run_gc(this, 1_8, this%size())
    end if

    call internal_destroy_vector(this%data)

    this%data = c_null_ptr
    this%size_of_type = 0
  end subroutine vector_destroy


  !* Get an element at an index in the vector.
  function vector_get(this, index) result(raw_c_pointer)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t), intent(in), value :: index
    type(c_ptr) :: raw_c_pointer

    if (index < 1 .or. index > this%size()) then
      error stop "[Vector] Error: Went out of bounds."
    end if

    raw_c_pointer = internal_vector_get(this%data, index)
  end function vector_get

  !* Overwrite the data at an index in the vector.
  !* This will run the GC.
  subroutine vector_set(this, index, fortran_data)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t), intent(in), value :: index
    class(*), intent(in), target :: fortran_data
    type(c_ptr) :: black_magic

    if (index < 1 .or. index > this%size()) then
      error stop "[Vector] Error: Went out of bounds."
    end if

    if (.not. this%is_empty()) then
      call run_gc(this, index, this%size())
    end if

    black_magic = transfer(loc(fortran_data), black_magic)

    call internal_vector_set(this%data, index, black_magic)
  end subroutine vector_set


  !* Check if the vector is empty.
  function vector_is_empty(this) result(empty)
    implicit none

    class(vec), intent(inout) :: this
    logical(c_bool) :: empty

    if (.not. c_associated(this%data)) then
      empty = .true.
    else
      empty = internal_vector_is_empty(this%data)
    end if
  end function vector_is_empty


  !* Get the number of elements in the vector.
  function vector_size(this) result(size)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t) :: size

    size = internal_vector_size(this%data)
  end function vector_size


  !* Get the total allocated size (in elements) of the vector.
  !* You can think of this as: "slots available before a resize occurs"
  function vector_capacity(this) result(cap)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t) :: cap

    cap = internal_vector_capacity(this%data)
  end function vector_capacity


  !* Shrink the capacity of the vector to it's size.
  !* (container size is trimmed to the current number of elements)
  subroutine vector_shrink_to_fit(this)
    implicit none

    class(vec), intent(inout) :: this

    call internal_vector_shrink_to_fit(this%data)
  end subroutine vector_shrink_to_fit


  !* Clear all the elements from the vector.
  !* The GC function will run on each element.
  subroutine vector_clear(this)
    implicit none

    class(vec), intent(inout) :: this

    if (.not. this%is_empty()) then
      call run_gc(this, 1_8, this%size())
    end if

    call internal_vector_clear(this%data)
  end subroutine vector_clear


  !* Insert an element into an index of the array.
  subroutine vector_insert(this, index, fortran_data)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t), intent(in), value :: index
    class(*), intent(in), target :: fortran_data
    type(c_ptr) :: black_magic

    black_magic = transfer(loc(fortran_data), black_magic)

    call internal_vector_insert(this%data, index, black_magic)
  end subroutine vector_insert


  !* Remove an element from the vector at an index.
  !* This will call the GC on the element.
  subroutine vector_remove(this, index)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t), intent(in), value :: index

    if (index < 1 .or. index > this%size()) then
      error stop "[Vector] Error: Went out of bounds."
    end if

    if (.not. this%is_empty()) then
      call run_gc(this, index, index)
    end if

    call internal_vector_remove(this%data, index)
  end subroutine vector_remove


  !* Uses memcpy under the hood.
  !* Push an element to the back of the vector.
  subroutine vector_push_back(this, fortran_data)
    implicit none

    class(vec), intent(inout) :: this
    class(*), intent(in), target :: fortran_data
    type(c_ptr) :: black_magic

    black_magic = transfer(loc(fortran_data), black_magic)

    call internal_vector_push_back(this%data, black_magic)
  end subroutine vector_push_back


  !* Remove the last element of the vector.
  subroutine vector_pop_back(this)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t) :: size

    !? If it's empty, popping can corrupt the memory.
    if (this%is_empty()) then
      return
    end if

    size = this%size()

    if (.not. this%is_empty()) then
      call run_gc(this, size, size)
    end if

    call internal_vector_pop_back(this%data)
  end subroutine vector_pop_back


  !* Reserve an internal capacity of the vector.
  subroutine vector_reserve(this, new_capacity)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t), intent(in), value :: new_capacity

    call internal_vector_reserve(this%data, new_capacity)
  end subroutine vector_reserve


  !* Resize a vector to a new size.
  !* Requires a new default element.
  subroutine vector_resize(this, new_size, default_element)
    implicit none

    class(vec), intent(inout) :: this
    integer(c_size_t), intent(in), value :: new_size
    class(*), intent(in), target :: default_element
    type(c_ptr) :: black_magic

    black_magic = transfer(loc(default_element), black_magic)

    !! FIXME: this will need some in depth analysis of how to GC this.

    call internal_vector_resize(this%data, new_size, black_magic)
  end subroutine vector_resize


  !* Swap one vector's contents with another.
  !* If they are not of the same type, this will throw a C exception.
  subroutine vector_swap(this, other)
    implicit none

    class(vec), intent(inout) :: this
    type(vec), intent(inout) :: other

    call internal_vector_swap(this%data, other%data)
  end subroutine vector_swap


  !* Clone a vector into another one.
  !* Might want to make sure that it's uninitialized or this might cause issues.
  subroutine vector_clone(this, other)
    implicit none

    class(vec), intent(in) :: this
    type(vec), intent(inout) :: other

    call internal_vector_clone(this%data, other%data)
  end subroutine vector_clone


!? BEGIN INTERNAL ONLY ==============================================

  subroutine run_gc(this, min, max)
    implicit none

    type(vec), intent(inout) :: this
    integer(c_size_t), intent(in), value :: min, max
    procedure(vec_gc_blueprint), pointer :: optional_gc
    integer(c_size_t) :: i

    ! No GC function was assigned to the vector.
    if (.not. c_associated(this%gc_func)) then
      return
    end if

    call c_f_procpointer(this%gc_func, optional_gc)

    do i = min, max
      call optional_gc(this%get(i))
    end do
  end subroutine run_gc

end module vector
