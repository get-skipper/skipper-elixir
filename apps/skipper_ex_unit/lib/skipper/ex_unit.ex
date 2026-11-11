defmodule Skipper.ExUnit do
  @moduledoc """
  Skipper for ExUnit. In `test/test_helper.exs`:

      Skipper.ExUnit.start()
      ExUnit.start()

  and in each test module, **before** `use ExUnit.Case` (or a case template
  such as `MyAppWeb.ConnCase`):

      use Skipper.Case
      use ExUnit.Case, async: true

  Disabled tests are reported as skipped with the reason. Wallaby `feature`s
  and Hound tests are ExUnit tests, so they are covered the same way.
  """

  @doc """
  Load the spreadsheet (see `Skipper.start/1` for options) and register the
  end-of-suite hook that emits the report and, with `SKIPPER_MODE=sync`,
  reconciles the sheet.
  """
  def start(opts \\ []) do
    Skipper.start(opts)

    ExUnit.after_suite(fn _ ->
      with {:error, _} <- Skipper.finish() do
        # Make the run fail so a broken sync is visible in CI.
        System.at_exit(fn _ -> exit({:shutdown, 1}) end)
      end
    end)

    :ok
  end
end
