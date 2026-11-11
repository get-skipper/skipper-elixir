defmodule Skipper.Log do
  @moduledoc false

  @doc "True when `SKIPPER_DEBUG` is set to a non-empty value."
  def debug?, do: System.get_env("SKIPPER_DEBUG", "") != ""

  def log(msg), do: if(debug?(), do: IO.puts(:stderr, "[skipper] " <> msg))
  def warn(msg), do: if(debug?(), do: IO.puts(:stderr, "[skipper] WARN: " <> msg))
end
