#include "lstm.h"
#include "enzyme_api.h"
static double lstm_scalar(int l, int c, int b, const double *main,
                          const double *extra, const double *state,
                          const double *sequence) {
  double loss;
  lstm_objective(l, c, b, main, extra,
                 std::vector<double>(state, state + 2 * l * b), sequence,
                 &loss);
  return loss;
}
void enzyme_lstm_grad(int l, int c, int b, const double *main,
                      double *dmain, const double *extra, double *dextra,
                      const double *state, double *dstate,
                      const double *sequence, double *dsequence) {
  __enzyme_autodiff((void *)lstm_scalar, enzyme_const, l, enzyme_const, c,
                    enzyme_const, b, enzyme_dup, main, dmain, enzyme_dup,
                    extra, dextra, enzyme_dup, state, dstate, enzyme_dup,
                    sequence, dsequence);
}
