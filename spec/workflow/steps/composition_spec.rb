# frozen_string_literal: true

require "actionflow"

RSpec.describe "Integration: step composition" do
  it "reduce_if + iterate composition" do
    results = []
    organizer = Class.new { include Workflow::Organizer }.new

    result = organizer.with(items: [1, 2, 3, 4, 5]).reduce(
      Workflow::Steps::ReduceIf.new(
        ->(ctx) { ctx[:items].any? },
        [Workflow::Steps::Iterate.new(:items, [->(ctx) { results << ctx[:item]; ctx }])]
      )
    )

    expect(results).to eq([1, 2, 3, 4, 5])
    expect(result).to be_success
  end

  it "nested reduce_if_else inside iterate" do
    evens = []
    odds = []

    organizer = Class.new { include Workflow::Organizer }.new

    result = organizer.with(numbers: [1, 2, 3, 4]).reduce(
      Workflow::Steps::Iterate.new(:numbers, [
        Workflow::Steps::ReduceIfElse.new(
          ->(ctx) { ctx[:number].even? },
          [->(ctx) { evens << ctx[:number]; ctx }],
          [->(ctx) { odds << ctx[:number]; ctx }]
        )
      ])
    )

    expect(evens).to eq([2, 4])
    expect(odds).to eq([1, 3])
    expect(result).to be_success
  end

  it "organizer helper methods produce correct step types and execute" do
    organizer_class = Class.new {
      include Workflow::Organizer
    }

    organizer = organizer_class.new

    result = organizer.with(items: [10, 20], threshold: 15).reduce(
      organizer.iterate(:items, [
        organizer.reduce_if(
          ->(ctx) { ctx[:item] > ctx[:threshold] },
          [->(ctx) { ctx[:big_items] ||= []; ctx[:big_items] << ctx[:item]; ctx }]
        )
      ])
    )

    expect(result[:big_items]).to eq([20])
  end

  it "AddToContext injects data mid-workflow" do
    step = Workflow::Steps::AddToContext.new(computed: true)
    organizer = Class.new { include Workflow::Organizer }.new

    result = organizer.with(x: 1).reduce(
      step,
      ->(ctx) { ctx[:verified] = ctx[:computed] == true; ctx }
    )

    expect(result[:computed]).to eq(true)
    expect(result[:verified]).to eq(true)
  end

  it "Execute wraps inline logic" do
    step = Workflow::Steps::Execute.new(->(ctx) { ctx[:doubled] = ctx[:x] * 2; ctx })
    organizer = Class.new { include Workflow::Organizer }.new

    result = organizer.with(x: 7).reduce(step)
    expect(result[:doubled]).to eq(14)
  end
end
