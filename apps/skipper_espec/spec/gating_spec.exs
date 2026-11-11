defmodule Skipper.GatingSpec do
  use Skipper.ESpec
  use ESpec

  it "disabled example" do
    expect(true) |> to(eq(false))
  end

  it "runs when enabled" do
    expect(1 + 1) |> to(eq(2))
  end

  context "a context" do
    describe "nested" do
      it "disabled nested example" do
        expect(true) |> to(eq(false))
      end

      it "enabled nested example" do
        expect(true) |> to(be_true())
      end
    end
  end

  it "has gated examples with the Skipper reason" do
    by_desc = Map.new(Skipper.GatingSpec.examples(), &{&1.description, &1})

    expect(by_desc["disabled example"].opts[:skip])
    |> to(eq("[skipper] Test disabled until 2099-01-01"))

    expect(by_desc["runs when enabled"].opts[:skip]) |> to(be_nil())

    expect(Skipper.ESpec.test_id(by_desc["enabled nested example"]))
    |> to(
      eq("apps/skipper_espec/spec/gating_spec.exs > a context > nested > enabled nested example")
    )
  end
end
