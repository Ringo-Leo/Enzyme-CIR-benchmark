#include "enzyme_api.h"
#include "hand_light_matrix.h"
#include <vector>
static double hand_simple_row(const double *theta,
                              const HandDataLightMatrix *data, int row,
                              double *err) {
  hand_objective(theta, *data, err);
  return err[row];
}
static double hand_complicated_row(const double *theta, const double *us,
                                   const HandDataLightMatrix *data, int row,
                                   double *err) {
  hand_objective(theta, us, *data, err);
  return err[row];
}
void enzyme_hand_jac(const double *theta, int ntheta, const double *us,
                     const HandDataLightMatrix *data, double *err,
                     double *J) {
  int nrows = 3 * (int)data->correspondences.size();
  int usCols = us ? 2 : 0;
  std::vector<double> dtheta(ntheta), scratch(nrows), dscratch(nrows);
  std::vector<double> dus(us ? 2 * data->correspondences.size() : 0);
  for (int row = 0; row < nrows; row++) {
    std::fill(dtheta.begin(), dtheta.end(), 0.0);
    std::fill(dus.begin(), dus.end(), 0.0);
    if (us)
      __enzyme_autodiff((void *)hand_complicated_row, enzyme_dup, theta,
                        dtheta.data(), enzyme_dup, us, dus.data(),
                        enzyme_const, data, enzyme_const, row, enzyme_dup,
                        scratch.data(), dscratch.data());
    else
      __enzyme_autodiff((void *)hand_simple_row, enzyme_dup, theta,
                        dtheta.data(), enzyme_const, data, enzyme_const, row,
                        enzyme_dup, scratch.data(), dscratch.data());
    for (int c = 0; c < ntheta; c++)
      J[(usCols + c) * nrows + row] = dtheta[c];
    if (us) {
      int corr = row / 3;
      J[row] = dus[2 * corr];
      J[nrows + row] = dus[2 * corr + 1];
    }
  }
  if (us)
    hand_objective(theta, us, *data, err);
  else
    hand_objective(theta, *data, err);
}
