defmodule Skipper.TestId do
  @moduledoc "Test ID helpers: `relative/path > part1 > part2`, matched case-insensitively."

  @doc "Canonical form for lookups: trim, lowercase, collapse whitespace."
  @spec normalize(String.t()) :: String.t()
  def normalize(id), do: id |> String.split() |> Enum.join(" ") |> String.downcase()

  @doc "Build an ID from a file path (made relative to the project root) and title parts."
  @spec build(Path.t(), [String.t()]) :: String.t()
  def build(file, parts) do
    Enum.join([relative(file) | Enum.map(parts, &to_string/1)], " > ")
  end

  @doc "Make `file` relative to the project root, with `/` separators."
  def relative(file) do
    file = to_string(file)

    rel =
      if Path.type(file) == :absolute do
        Path.relative_to(Path.expand(file), project_root())
      else
        file
      end

    String.replace(rel, "\\", "/")
  end

  @doc """
  Outermost ancestor of `start` whose `mix.exs` is an umbrella (`apps_path`),
  else the nearest directory with a `mix.exs`, else `start`. Cached.
  """
  def project_root(start \\ nil) do
    if start do
      find_root(Path.expand(start))
    else
      case :persistent_term.get({__MODULE__, :root}, nil) do
        nil ->
          root = find_root(File.cwd!())
          :persistent_term.put({__MODULE__, :root}, root)
          root

        root ->
          root
      end
    end
  end

  defp find_root(start) do
    {nearest, umbrella} =
      start
      |> ancestors()
      |> Enum.reduce({nil, nil}, fn dir, {nearest, umbrella} ->
        case File.read(Path.join(dir, "mix.exs")) do
          {:ok, src} ->
            {nearest || dir, if(String.contains?(src, "apps_path"), do: dir, else: umbrella)}

          _ ->
            {nearest, umbrella}
        end
      end)

    umbrella || nearest || start
  end

  defp ancestors(dir) do
    Stream.unfold(dir, fn
      nil -> nil
      d -> {d, if(Path.dirname(d) == d, do: nil, else: Path.dirname(d))}
    end)
  end
end
