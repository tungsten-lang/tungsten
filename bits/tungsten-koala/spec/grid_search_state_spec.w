# Focused GridSearch learned-state lifecycle regression.

use spec
use koala

describe "GridSearch refit state" ->
  it "clears an earlier winner when a later fit is rejected" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    search = GridSearch.new(KNNClassifier.new, { k: [5, 1] }, 4)

    expect(search.fit(x, y)).not_to be_nil
    expect(search.fitted?).to be_true
    expect(search.best_estimator).not_to be_nil
    expect(search.predict([0, 13]).to_s).to eq("\[0, 1\]")

    expect(search.fit(x, [0, 1])).to be_nil
    expect(search.fitted?).to be_false
    expect(search.best_params).to be_nil
    expect(search.best_score).to be_nil
    expect(search.best_estimator).to be_nil
    expect(search.results).to be_nil
    expect(search.predict(x)).to be_nil
    expect(search.score(x, y)).to be_nil

spec_summary
