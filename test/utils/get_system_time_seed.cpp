// get_system_time_seed.cpp
#include <iostream>
#include <ctime>

extern "C" unsigned int get_system_time_seed() {
    return static_cast<unsigned int>(std::time(nullptr));
}