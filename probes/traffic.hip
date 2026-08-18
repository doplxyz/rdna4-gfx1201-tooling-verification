// Memory-traffic microkernel with analytically known byte counts.
//   mode 0: contiguous float4 (dwordx4) streaming read  -> 16 B/lane
//   mode 1: contiguous float  (dword)   streaming read  ->  4 B/lane
//   mode 2: strided float read, stride 32 B                (sparse EA requests)
//   mode 3: contiguous float4 write
// Bytes touched are printed by the program itself so the counter table can be
// checked against an analytic number rather than against another counter.
#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstdlib>

__global__ void read_f4(const float4* __restrict__ in, float* __restrict__ out, size_t n4)
{
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    float acc = 0.f;
    if (i < n4) { float4 v = in[i]; acc = v.x + v.y + v.z + v.w; }
    if (acc == 1234.5678f) out[0] = acc;   // never true; keeps the load alive
}

__global__ void read_f1(const float* __restrict__ in, float* __restrict__ out, size_t n)
{
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    float acc = 0.f;
    if (i < n) acc = in[i];
    if (acc == 1234.5678f) out[0] = acc;
}

__global__ void read_stride32(const float* __restrict__ in, float* __restrict__ out, size_t n)
{
    size_t i = ((size_t)blockIdx.x * blockDim.x + threadIdx.x) * 8;  // 8 floats = 32 B
    float acc = 0.f;
    if (i < n) acc = in[i];
    if (acc == 1234.5678f) out[0] = acc;
}

__global__ void null_kernel(float* __restrict__ out)
{
    // mode 4: launched with the same geometry but touches no memory at all.
    if (threadIdx.x == 0xffffffffu) out[0] = 1.f;   // never taken
}

__global__ void write_f4(float4* __restrict__ out, size_t n4)
{
    size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n4) out[i] = make_float4(1.f, 2.f, 3.f, 4.f);
}

#define CHECK(x) do { hipError_t e_=(x); if(e_!=hipSuccess){ printf("HIP error %d %s at %d\n",(int)e_,hipGetErrorString(e_),__LINE__); exit(1);} } while(0)

int main(int argc, char** argv)
{
    int    mode  = (argc > 1) ? atoi(argv[1]) : 0;
    size_t bytes = (argc > 2) ? (size_t)atoll(argv[2]) : (size_t)256 * 1024 * 1024;
    int    iters = (argc > 3) ? atoi(argv[3]) : 1;

    float* in = nullptr; float* out = nullptr;
    CHECK(hipMalloc(&in, bytes));
    CHECK(hipMalloc(&out, 1024));
    CHECK(hipMemset(in, 0, bytes));
    CHECK(hipDeviceSynchronize());

    size_t n1  = bytes / sizeof(float);
    size_t n4  = bytes / sizeof(float4);
    const int block = 256;
    size_t touched = 0;

    for (int it = 0; it < iters; ++it) {
        switch (mode) {
        case 0:
            hipLaunchKernelGGL(read_f4, dim3((n4 + block - 1)/block), dim3(block), 0, 0,
                               (const float4*)in, out, n4);
            touched += n4 * 16; break;
        case 1:
            hipLaunchKernelGGL(read_f1, dim3((n1 + block - 1)/block), dim3(block), 0, 0,
                               in, out, n1);
            touched += n1 * 4; break;
        case 2: {
            size_t nt = n1 / 8;
            hipLaunchKernelGGL(read_stride32, dim3((nt + block - 1)/block), dim3(block), 0, 0,
                               in, out, n1);
            touched += nt * 4; break;   // 4 B requested per lane, 32 B apart
        }
        case 4:
            hipLaunchKernelGGL(null_kernel, dim3((n4 + block - 1)/block), dim3(block), 0, 0, out);
            touched += 0; break;
        case 3:
            hipLaunchKernelGGL(write_f4, dim3((n4 + block - 1)/block), dim3(block), 0, 0,
                               (float4*)in, n4);
            touched += n4 * 16; break;
        }
    }
    CHECK(hipDeviceSynchronize());
    printf("mode=%d buffer_bytes=%zu iters=%d requested_bytes=%zu (%.2f MiB)\n",
           mode, bytes, iters, touched, touched / 1048576.0);
    hipFree(in); hipFree(out);
    return 0;
}
