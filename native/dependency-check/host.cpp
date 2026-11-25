#include <span>
#include <thread>

static_assert(std::span<int>{}.empty());

int main() {
    std::thread worker([] {});
    worker.join();
}
