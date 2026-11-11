defmodule Skipper.Case do
  @moduledoc """
  Gates the tests of a module with Skipper. Must come **before**
  `use ExUnit.Case` (or any case template that uses it): it hooks in ahead of
  ExUnit's own `@before_compile` and marks disabled tests with a `:skip` tag.

  Test ID: `test/auth_test.exs > describe > test name` (path relative to the
  project root, the umbrella root in an umbrella).
  """

  defmacro __using__(_opts) do
    quote do
      # Checked while the module body runs: ExUnit registers :ex_unit_tests then.
      if Module.has_attribute?(__MODULE__, :ex_unit_tests) do
        raise ArgumentError,
              "use Skipper.Case must come before use ExUnit.Case (or the case template that uses it)"
      end

      @before_compile Skipper.Case
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    if Module.has_attribute?(env.module, :ex_unit_tests) do
      # Accumulated newest first: re-add oldest first to keep the order.
      tests = env.module |> Module.get_attribute(:ex_unit_tests) |> Enum.reverse()
      Module.delete_attribute(env.module, :ex_unit_tests)
      Enum.each(tests, &Module.put_attribute(env.module, :ex_unit_tests, gate(&1)))
    end

    nil
  end

  defp gate(%ExUnit.Test{tags: tags} = test) do
    case Skipper.check(test_id(test)) do
      {:skip, msg} when not is_map_key(tags, :skip) or tags.skip in [nil, false] ->
        %{test | tags: Map.put(tags, :skip, msg)}

      _ ->
        test
    end
  end

  @doc "Skipper test ID of an `ExUnit.Test`."
  def test_id(%ExUnit.Test{name: name, tags: tags}) do
    name = strip(to_string(name), "#{tags[:test_type] || :test} ")
    describe = tags[:describe]
    parts = if describe, do: [describe, strip(name, "#{describe} ")], else: [name]
    Skipper.TestId.build(tags.file, parts)
  end

  defp strip(s, prefix),
    do:
      if(String.starts_with?(s, prefix),
        do: binary_part(s, byte_size(prefix), byte_size(s) - byte_size(prefix)),
        else: s
      )
end
