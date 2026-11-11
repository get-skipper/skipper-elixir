defmodule Skipper.WallabyTest do
  # A Wallaby feature is an ExUnit test: Skipper.Case gates it like any other.
  # The disabled feature never starts a browser session (skipped tests run no setup).
  use Skipper.Case
  use ExUnit.Case, async: true
  use Wallaby.Feature

  feature "disabled feature", %{session: _session} do
    flunk("should have been skipped by Skipper")
  end

  test "feature ids drop the feature prefix" do
    [t] = Enum.filter(__ex_unit__().tests, &(&1.tags.test_type == :feature))

    assert Skipper.Case.test_id(t) ==
             "apps/skipper_ex_unit/test/wallaby_test.exs > disabled feature"

    assert t.tags.skip =~ "[skipper]"
  end
end
