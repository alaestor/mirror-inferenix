// Compile and link only. Build hosts do not need access to a GPU.
#include <hip/hip_runtime.h>
#ifdef CHECK_HIPBLAS
#include <hipblas/hipblas.h>
#endif

__global__ void check_kernel() {}

int main() {
    check_kernel<<<1, 1>>>();
#ifdef CHECK_HIPBLAS
    hipblasHandle_t handle;
    return hipblasCreate(&handle);
#else
    return hipGetLastError();
#endif
}
