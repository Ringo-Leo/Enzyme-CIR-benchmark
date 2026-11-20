#pragma once
#include "defs.h"
#include "utils.h"
extern "C" {
extern int enzyme_const, enzyme_dup, enzyme_dupnoneed, enzyme_out;
double __enzyme_autodiff(void *, ...);

void enzyme_gmm_grad(int d, int k, int n, const double *alphas,
                     double *dalphas, const double *means, double *dmeans,
                     const double *icf, double *dicf, const double *x,
                     double gamma, int m);
void enzyme_ba_reproj_jac(const double *cam, const double *X, const double *w,
                          const double *feat, double *J);
double enzyme_ba_w_grad(const double *w);
void enzyme_hand_jac(const double *theta, int ntheta, const double *us,
                     const HandDataLightMatrix *data, double *err, double *J);
void enzyme_lstm_grad(int l, int c, int b, const double *main,
                      double *dmain, const double *extra, double *dextra,
                      const double *state, double *dstate,
                      const double *sequence, double *dsequence);
}
