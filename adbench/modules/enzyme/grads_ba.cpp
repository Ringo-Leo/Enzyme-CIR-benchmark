#include "ba.h"
#include "enzyme_api.h"
static double reproj_component(const double *cam, const double *X,
                               const double *w, const double *feat,
                               int which) {
  double err[2];
  computeReprojError(cam, X, w, feat, err);
  return err[which];
}
static double zach(const double *w) {
  double err;
  computeZachWeightError(w, &err);
  return err;
}
void enzyme_ba_reproj_jac(const double *cam, const double *X, const double *w,
                          const double *feat, double *J) {
  for (int out = 0; out < 2; out++) {
    double dcam[BA_NCAMPARAMS] = {0}, dX[3] = {0}, dw = 0;
    __enzyme_autodiff((void *)reproj_component, enzyme_dup, cam, dcam,
                      enzyme_dup, X, dX, enzyme_dup, w, &dw, enzyme_const,
                      feat, enzyme_const, out);
    for (int i = 0; i < BA_NCAMPARAMS; i++)
      J[i * 2 + out] = dcam[i];
    for (int i = 0; i < 3; i++)
      J[(BA_NCAMPARAMS + i) * 2 + out] = dX[i];
    J[(BA_NCAMPARAMS + 3) * 2 + out] = dw;
  }
}
double enzyme_ba_w_grad(const double *w) {
  double dw = 0;
  __enzyme_autodiff((void *)zach, enzyme_dup, w, &dw);
  return dw;
}
