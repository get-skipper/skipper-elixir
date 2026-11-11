defmodule Skipper.GatingTest do
  use Skipper.Case
  use ExUnit.Case, async: true

  test "top level disabled" do
    flunk("should have been skipped by Skipper")
  end

  test "runs when enabled" do
    assert true
  end

  describe "a group" do
    test "disabled in describe" do
      flunk("should have been skipped by Skipper")
    end

    test "enabled in describe" do
      assert true
    end
  end

  @tag skip: "own reason"
  test "keeps an existing skip tag" do
    flunk("skipped by its own tag")
  end
end

defmodule Skipper.CaseTest do
  use ExUnit.Case, async: true

  defp tests_by_name,
    do: Map.new(Skipper.GatingTest.__ex_unit__().tests, &{to_string(&1.name), &1})

  test "disabled tests carry the skip reason" do
    t = tests_by_name()
    assert t["test top level disabled"].tags.skip == "[skipper] Test disabled until 2099-01-01"
    assert t["test a group disabled in describe"].tags.skip =~ "[skipper]"
    refute t["test runs when enabled"].tags[:skip]
    assert t["test keeps an existing skip tag"].tags.skip == "own reason"
  end

  test "ids drop the test prefix and nest the describe" do
    t = tests_by_name()

    assert Skipper.Case.test_id(t["test a group enabled in describe"]) ==
             "apps/skipper_ex_unit/test/gating_test.exs > a group > enabled in describe"
  end

  test "test order is preserved" do
    names = Enum.map(Skipper.GatingTest.__ex_unit__().tests, &to_string(&1.name))
    assert hd(names) == "test top level disabled"
    assert List.last(names) == "test keeps an existing skip tag"
  end

  test "wrong order is a compile error" do
    assert_raise ArgumentError, ~r/must come before use ExUnit.Case/, fn ->
      Code.compile_string("""
      defmodule Skipper.WrongOrder do
        use ExUnit.Case
        use Skipper.Case
      end
      """)
    end
  end
end
