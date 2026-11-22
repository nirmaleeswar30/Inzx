// A plain-C++ handle on the shared Automix TransitionFilter
// (desktop/automix/blend_renderer.h), for the iOS audio tap. The tap is
// Objective-C++ and shouldn't pull in that header's time-stretch library, so
// it goes through these few functions instead.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.

#pragma once

struct InzxTransition;

InzxTransition *InzxTransitionCreate();
void InzxTransitionDestroy(InzxTransition *t);
void InzxTransitionConfigure(InzxTransition *t, int sampleRate);
/// Cutoffs glide towards these; 20000 / 20 Hz park the filters. With
/// `echo`, the feedback echo runs too (it stays engaged from then on, which
/// with no send and full dry passes the audio through).
void InzxTransitionSet(InzxTransition *t, float lowPassHz, float highPassHz, bool echo,
                       float echoSeconds, float echoSend, float echoDry);
/// Stereo, in place.
void InzxTransitionProcess(InzxTransition *t, float *left, float *right, int frames);
