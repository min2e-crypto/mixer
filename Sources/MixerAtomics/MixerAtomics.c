#include "MixerAtomics.h"
#include <stdatomic.h>
#include <stdlib.h>

struct MixerAtomicFloat {
    _Atomic float value;
};

MixerAtomicFloat *mixer_atomic_float_create(float value) {
    MixerAtomicFloat *atomic = malloc(sizeof(MixerAtomicFloat));
    atomic_init(&atomic->value, value);
    return atomic;
}

void mixer_atomic_float_destroy(MixerAtomicFloat *atomic) {
    free(atomic);
}

float mixer_atomic_float_load(const MixerAtomicFloat *atomic) {
    return atomic_load_explicit((_Atomic float *)&atomic->value, memory_order_relaxed);
}

void mixer_atomic_float_store(MixerAtomicFloat *atomic, float value) {
    atomic_store_explicit(&atomic->value, value, memory_order_relaxed);
}
