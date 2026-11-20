#include "../../shared/ITest.h"
#include "../../shared/GMMData.h"
#include "../../shared/BAData.h"
#include "../../shared/HandData.h"
#include "../../shared/LSTMData.h"
#include "../../shared/gmm.h"
#include "../../shared/ba.h"
#include "../../shared/hand_light_matrix.h"
#include "../../shared/lstm.h"
#include "enzyme_api.h"
#include <algorithm>

class EnzymeGMM : public ITest<GMMInput, GMMOutput> {
  GMMInput in;
  GMMOutput out;
public:
  void prepare(GMMInput &&input) override {
    in = input;
    int icf_sz = in.d * (in.d + 1) / 2;
    out = {0, std::vector<double>(in.k + in.d * in.k + icf_sz * in.k)};
  }
  GMMOutput output() override { return out; }
  void calculate_objective(int times) override {
    for (int i = 0; i < times; ++i)
      gmm_objective(in.d, in.k, in.n, in.alphas.data(), in.means.data(),
                    in.icf.data(), in.x.data(), in.wishart, &out.objective);
  }
  void calculate_jacobian(int times) override {
    for (int i = 0; i < times; ++i) {
      std::fill(out.gradient.begin(), out.gradient.end(), 0.0);
      double *g = out.gradient.data();
      enzyme_gmm_grad(in.d, in.k, in.n, in.alphas.data(), g, in.means.data(),
                      g + in.k, in.icf.data(), g + in.k + in.d * in.k,
                      in.x.data(), in.wishart.gamma, in.wishart.m);
    }
  }
};

class EnzymeBA : public ITest<BAInput, BAOutput> {
  BAInput in;
  BAOutput out;
  std::vector<double> block = std::vector<double>(2 * (BA_NCAMPARAMS + 3 + 1));
public:
  void prepare(BAInput &&input) override {
    in = input;
    out = {std::vector<double>(2 * in.p), std::vector<double>(in.p),
           BASparseMat(in.n, in.m, in.p)};
  }
  BAOutput output() override { return out; }
  void calculate_objective(int times) override {
    for (int i = 0; i < times; ++i)
      ba_objective(in.n, in.m, in.p, in.cams.data(), in.X.data(), in.w.data(),
                   in.obs.data(), in.feats.data(), out.reproj_err.data(),
                   out.w_err.data());
  }
  void calculate_jacobian(int times) override {
    for (int t = 0; t < times; ++t) {
      out.J.clear();
      for (int j = 0; j < in.p; ++j) {
        int cam = in.obs[2 * j], pt = in.obs[2 * j + 1];
        enzyme_ba_reproj_jac(&in.cams[cam * BA_NCAMPARAMS], &in.X[pt * 3],
                             &in.w[j], &in.feats[2 * j], block.data());
        out.J.insert_reproj_err_block(j, cam, pt, block.data());
      }
      for (int j = 0; j < in.p; ++j)
        out.J.insert_w_err_block(j, enzyme_ba_w_grad(&in.w[j]));
    }
  }
};

class EnzymeHand : public ITest<HandInput, HandOutput> {
  HandInput in;
  HandOutput out;
  bool complicated = false;
public:
  void prepare(HandInput &&input) override {
    in = input;
    complicated = in.us.size() != 0;
    int rows = 3 * in.data.correspondences.size();
    int cols = (complicated ? 2 : 0) + in.theta.size();
    out = {std::vector<double>(rows), cols, rows,
           std::vector<double>(rows * cols)};
  }
  HandOutput output() override { return out; }
  void calculate_objective(int times) override {
    for (int i = 0; i < times; ++i) {
      if (complicated)
        hand_objective(in.theta.data(), in.us.data(), in.data,
                       out.objective.data());
      else
        hand_objective(in.theta.data(), in.data, out.objective.data());
    }
  }
  void calculate_jacobian(int times) override {
    for (int i = 0; i < times; ++i)
      enzyme_hand_jac(in.theta.data(), in.theta.size(),
                      complicated ? in.us.data() : nullptr, &in.data,
                      out.objective.data(), out.jacobian.data());
  }
};

class EnzymeLSTM : public ITest<LSTMInput, LSTMOutput> {
  LSTMInput in;
  LSTMOutput out;
  std::vector<double> dstate, dsequence;
public:
  void prepare(LSTMInput &&input) override {
    in = input;
    out = {0, std::vector<double>(in.main_params.size() +
                                  in.extra_params.size())};
    dstate.resize(in.state.size());
    dsequence.resize(in.sequence.size());
  }
  LSTMOutput output() override { return out; }
  void calculate_objective(int times) override {
    for (int i = 0; i < times; ++i)
      lstm_objective(in.l, in.c, in.b, in.main_params.data(),
                     in.extra_params.data(), in.state, in.sequence.data(),
                     &out.objective);
  }
  void calculate_jacobian(int times) override {
    for (int i = 0; i < times; ++i) {
      std::fill(out.gradient.begin(), out.gradient.end(), 0.0);
      std::fill(dstate.begin(), dstate.end(), 0.0);
      std::fill(dsequence.begin(), dsequence.end(), 0.0);
      enzyme_lstm_grad(in.l, in.c, in.b, in.main_params.data(),
                       out.gradient.data(), in.extra_params.data(),
                       out.gradient.data() + in.main_params.size(),
                       in.state.data(), dstate.data(), in.sequence.data(),
                       dsequence.data());
    }
  }
};

extern "C" DLL_PUBLIC ITest<GMMInput, GMMOutput> *get_gmm_test() {
  return new EnzymeGMM();
}
extern "C" DLL_PUBLIC ITest<BAInput, BAOutput> *get_ba_test() {
  return new EnzymeBA();
}
extern "C" DLL_PUBLIC ITest<HandInput, HandOutput> *get_hand_test() {
  return new EnzymeHand();
}
extern "C" DLL_PUBLIC ITest<LSTMInput, LSTMOutput> *get_lstm_test() {
  return new EnzymeLSTM();
}
