#include "gmm.h"
#include "enzyme_api.h"
static double gmm_scalar(int d, int k, int n, const double *alphas,
                         const double *means, const double *icf,
                         const double *x, double gamma, int m) {
  Wishart wishart{gamma, m};
  double err;
  gmm_objective(d, k, n, alphas, means, icf, x, wishart, &err);
  return err;
}
void enzyme_gmm_grad(int d, int k, int n, const double *alphas,
                     double *dalphas, const double *means, double *dmeans,
                     const double *icf, double *dicf, const double *x,
                     double gamma, int m) {
  __enzyme_autodiff((void *)gmm_scalar, enzyme_const, d, enzyme_const, k,
                    enzyme_const, n, enzyme_dup, alphas, dalphas, enzyme_dup,
                    means, dmeans, enzyme_dup, icf, dicf, enzyme_const, x,
                    enzyme_const, gamma, enzyme_const, m);
}
