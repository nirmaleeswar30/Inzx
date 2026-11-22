// See InzxTransition.h. GPL-3.0, like the shared sources it wraps.

#include "InzxTransition.h"

#include "blend_renderer.h"

struct InzxTransition {
  inzx::automix::TransitionFilter filter;
};

InzxTransition *InzxTransitionCreate() { return new InzxTransition(); }

void InzxTransitionDestroy(InzxTransition *t) { delete t; }

void InzxTransitionConfigure(InzxTransition *t, int sampleRate) { t->filter.configure(sampleRate); }

void InzxTransitionSet(InzxTransition *t, float lowPassHz, float highPassHz, bool echo,
                       float echoSeconds, float echoSend, float echoDry) {
  t->filter.setCutoffs(lowPassHz, highPassHz);
  if (echo) t->filter.setEcho(echoSeconds, echoSend, echoDry);
}

void InzxTransitionProcess(InzxTransition *t, float *left, float *right, int frames) {
  t->filter.process(left, right, frames);
}
