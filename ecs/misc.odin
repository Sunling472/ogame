package ecs

@(private)
_stride_of :: proc(size, align: int) -> int {
	if size == 0 do return 0
	return (size + align - 1) & ~(align - 1) // align_forward
}
