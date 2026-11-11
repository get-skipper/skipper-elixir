defmodule Skipper.ESpec do
  @moduledoc """
  Skipper for [ESpec](https://github.com/antonmi/espec). In `spec/spec_helper.exs`:

      Skipper.ESpec.start()

  and in each spec module, **before** `use ESpec`:

      defmodule AuthSpec do
        use Skipper.ESpec
        use ESpec
        ...
      end

  Disabled examples are reported as pending with the Skipper reason.
  Test ID: `spec/auth_spec.exs > describe > context > example`.
  """

  @doc """
  Load the spreadsheet (see `Skipper.start/1` for options) and register the
  end-of-run hook (report, and sync with `SKIPPER_MODE=sync`).
  """
  def start(opts \\ []) do
    Skipper.start(opts)

    System.at_exit(fn _status ->
      # A broken sync must fail the run.
      with {:error, _} <- Skipper.finish(), do: System.halt(1)
    end)

    :ok
  end

  defmacro __using__(_opts) do
    quote do
      # Checked while the module body runs: ESpec registers :examples then.
      if Module.has_attribute?(__MODULE__, :examples) do
        raise ArgumentError, "use Skipper.ESpec must come before use ESpec"
      end

      @before_compile Skipper.ESpec
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    if Module.has_attribute?(env.module, :examples) do
      # Accumulated newest first: re-add oldest first to keep the order.
      examples = env.module |> Module.get_attribute(:examples) |> Enum.reverse()
      Module.delete_attribute(env.module, :examples)
      Enum.each(examples, &Module.put_attribute(env.module, :examples, gate(&1)))
    end

    nil
  end

  defp gate(%ESpec.Example{opts: opts} = example) do
    case Skipper.check(test_id(example)) do
      {:skip, msg} ->
        if opts[:skip], do: example, else: %{example | opts: Keyword.put(opts, :skip, msg)}

      :run ->
        example
    end
  end

  @doc "Skipper test ID of an `ESpec.Example` (the module-level context is left out)."
  def test_id(%ESpec.Example{} = example) do
    contexts =
      example
      |> ESpec.Example.context_descriptions()
      |> Enum.drop(1)

    Skipper.TestId.build(example.file, Enum.map(contexts ++ [example.description], &describe/1))
  end

  defp describe(a) when is_atom(a), do: inspect(a)
  defp describe(s), do: to_string(s)
end
