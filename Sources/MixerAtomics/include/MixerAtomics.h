#ifndef MIXER_ATOMICS_H
#define MIXER_ATOMICS_H

typedef struct MixerAtomicFloat MixerAtomicFloat;

MixerAtomicFloat *mixer_atomic_float_create(float value);
void mixer_atomic_float_destroy(MixerAtomicFloat *atomic);
float mixer_atomic_float_load(const MixerAtomicFloat *atomic);
void mixer_atomic_float_store(MixerAtomicFloat *atomic, float value);

#endif
