// Deliberate device-side OOB write, same shape as CK#3759 bug 1:
// a 2-element local array is written at index 2/3, spilling into adjacent stack.
// Compiled with -fsanitize=address -fgpu-sanitize this SHOULD be reported.
#include <hip/hip_runtime.h>
#include <cstdio>

__global__ void oob_stack(int* out, int n)
{
    int nonzero_elems[2] = {0, 0};
    int guard[2]         = {0x5a5a5a5a, 0x5a5a5a5a};
    int i                = threadIdx.x;
    // Out-of-bounds: indices 2 and 3 are past the end of nonzero_elems.
    int* p = nonzero_elems;
    for (int k = 0; k < 4; ++k)
        p[k] = i + k;   // k=2,3 are OOB
    if (i < n)
        out[i] = nonzero_elems[0] + nonzero_elems[1] + guard[0] + guard[1];
}

__global__ void oob_heap(int* buf, int n)
{
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    // Write one element past the end of a heap allocation of n ints.
    buf[i] = i;                 // i can reach n (grid is n+1)
}

int main(int argc, char** argv)
{
    int mode = (argc > 1) ? atoi(argv[1]) : 0;
    const int n = 64;
    int* d = nullptr;
    hipMalloc(&d, n * sizeof(int));
    if (mode == 0) {
        hipLaunchKernelGGL(oob_stack, dim3(1), dim3(n), 0, 0, d, n);
    } else {
        // n+1 threads over an n-int allocation -> 4-byte heap overflow
        hipLaunchKernelGGL(oob_heap, dim3(1), dim3(n + 1), 0, 0, d, n);
    }
    hipError_t e = hipDeviceSynchronize();
    printf("mode=%d hipDeviceSynchronize=%d (%s)\n", mode, (int)e, hipGetErrorString(e));
    int h[n];
    hipMemcpy(h, d, n * sizeof(int), hipMemcpyDeviceToHost);
    printf("out[0]=%d out[1]=%d\n", h[0], h[1]);
    hipFree(d);
    return 0;
}
