# Native troubleshooting

## Dependency check or build failure

If the dependency check says "Trying the build anyway," let the build
continue. The check can't recognize every ROCm layout. If the build
fails, look under `native/.work/build/<gpu>/<model>/`.
`dependencies.log` has the compiler check, and `configure-*.log` has
the CMake configuration output.

For a custom ROCm installation, export `ROCM_PATH` and add the ROCm
prefix to `CMAKE_PREFIX_PATH` so CMake can find the SDK. If CMake can't
find the HIP compiler for Qwen, set `HIPCXX` to the absolute path to
ROCm's `clang++`. For Inkling, set `INFERENIX_NATIVE_HIPCC` to the
path to `hipcc` or ROCm's `clang++`.

## Missing library or inaccessible GPU

Use the ROCm runtime that matches your build. For a custom installation,
add its library directories to `LD_LIBRARY_PATH` and export it before
launching the server. Make sure the build target matches your card.
See [GPU targets](USAGE.md#choose-a-gpu-target).

Check `ls -l /dev/kfd /dev/dri/renderD*`. Your account needs read and
write access to `/dev/kfd` and your GPU's render node. If they're missing,
check the `amdgpu` driver. If access is denied, check your distro's GPU
permissions and sign back in after any group changes.

## Qwen service or memory error

Run `systemctl --user status` as your regular user. If it can't reach
the user manager, sign in directly instead of using `sudo` or `su`.
If the service reports missing cgroup memory files, ask your administrator
to check cgroup v2 memory accounting and delegation for user services.

Qwen runs as a user service even in the foreground so the memory cap and
swap limit apply. The defaults are a 48 GiB service cap and a 40 GiB engine
budget. On a machine with less RAM, lower `INFERENIX_MEMORY_MAX_QWEN38`
and `INFERENIX_RAM_CAP_GIB_QWEN38` together, keeping the engine budget
below the service cap. Set the service cap with a suffix such as `G`
and give the engine budget as a number in GiB.
