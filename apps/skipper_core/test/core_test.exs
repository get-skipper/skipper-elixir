defmodule Skipper.CoreTest do
  # Not async: some tests change process-global env vars.
  use ExUnit.Case

  alias Skipper.{Client, Config, FakeApi, Report, Resolver, TestId, Writer}

  defp cfg(extra \\ []),
    do: struct!(%Config{spreadsheet_id: "sid", credentials: {:base64, ""}}, extra)

  defp date(s), do: elem(Client.parse_disabled_until(s), 1)

  defp entry(id, until \\ nil), do: %{test_id: id, disabled_until: until, notes: "", row: 0}

  defp with_env(vars, fun) do
    old = Map.new(vars, fn {k, _} -> {k, System.get_env(k)} end)
    Enum.each(vars, fn {k, v} -> if v, do: System.put_env(k, v), else: System.delete_env(k) end)

    try do
      fun.()
    after
      Enum.each(old, fn {k, v} -> if v, do: System.put_env(k, v), else: System.delete_env(k) end)
    end
  end

  describe "test ids" do
    test "normalize" do
      assert TestId.normalize("  Test/A.exs  >\tLogin  > Works ") == "test/a.exs > login > works"
    end

    test "build uses forward slashes" do
      assert TestId.build("test\\a.exs", ["grp", "it works"]) == "test/a.exs > grp > it works"
    end

    test "project root prefers the outermost umbrella" do
      tmp = Path.join(System.tmp_dir!(), "skipper-root-#{System.unique_integer([:positive])}")
      app = Path.join(tmp, "apps/a")
      File.mkdir_p!(Path.join(app, "test"))
      File.write!(Path.join(tmp, "mix.exs"), "[apps_path: \"apps\"]")
      File.write!(Path.join(app, "mix.exs"), "[app: :a]")
      assert TestId.project_root(Path.join(app, "test")) == tmp
      File.write!(Path.join(tmp, "mix.exs"), "# not umbrella")
      assert TestId.project_root(Path.join(app, "test")) == app
      File.rm_rf!(tmp)
    end
  end

  describe "parse_disabled_until" do
    test "returns next midnight UTC" do
      assert {:ok, d} = Client.parse_disabled_until(" 2026-04-01 ")
      assert DateTime.to_iso8601(d) == "2026-04-02T00:00:00Z"
      assert {:ok, nil} = Client.parse_disabled_until("  ")
    end

    test "rejects anything but strict dates" do
      for bad <- ["2026-4-01", "01/04/2026", "2026-02-30", "20260401", "2026-04-01T00:00:00"] do
        assert {:error, _} = Client.parse_disabled_until(bad), bad
      end

      assert {:error, msg} = Client.parse_disabled_until("soon", 7)
      assert msg =~ "row 7"
    end
  end

  describe "client" do
    test "merge keeps the latest date and appends new ids" do
      merged =
        Client.merge(
          [entry("a > x", date("2026-01-01")), entry("b > y")],
          [
            entry("A >  X", date("2025-01-01")),
            entry("b > y", date("2027-01-01")),
            entry("c > z")
          ]
        )

      assert Enum.map(merged, & &1.test_id) == ["a > x", "b > y", "c > z"]
      assert Enum.at(merged, 0).disabled_until == date("2026-01-01")
      assert Enum.at(merged, 1).disabled_until == date("2027-01-01")
    end

    test "fetches primary and reference sheets" do
      api =
        FakeApi.new([
          {"main", 11,
           [
             [" testId ", "disabledUntil", "notes"],
             ["a.exs > t1", "2099-01-01", "flaky"],
             ["", "2099-01-01"],
             ["a.exs > t2"]
           ]},
          {"ref", 12, [["testId", "disabledUntil"], ["A.exs > T2", "2099-06-01"]]}
        ])

      assert {:ok, %{primary: p, entries: e}} =
               Client.fetch_all(api, cfg(reference_sheets: ["ref", "missing"]))

      assert p.sheet_name == "main" and p.sheet_id == 11
      assert [%{notes: "flaky", row: 1}, %{row: 3}] = p.entries
      assert Enum.at(e, 1).disabled_until == date("2099-06-01")

      assert {:error, msg} = Client.fetch_all(api, cfg(test_id_column: "id"))
      assert msg =~ ~s(column "id" not found)
    end

    test "invalid date fails the fetch" do
      api = FakeApi.new([{"s", 1, [["testId", "disabledUntil"], ["x > y", "soon"]]}])
      assert {:error, msg} = Client.fetch_all(api, cfg())
      assert msg =~ "row 2"
    end
  end

  describe "resolver" do
    setup do
      file =
        Path.join(System.tmp_dir!(), "skipper-cache-#{System.unique_integer([:positive])}.json")

      on_exit(fn -> File.rm(file) end)
      %{cache: file}
    end

    test "opt-out model", %{cache: file} do
      with_env(%{"SKIPPER_CACHE_FILE" => file, "SKIPPER_CACHE_TTL" => nil}, fn ->
        {:ok, r} =
          Resolver.initialize_with(fn ->
            {:ok,
             [
               entry("a.exs > future", date("2099-01-01")),
               entry("a.exs > past", date("2020-01-01")),
               entry("a.exs > nodate")
             ]}
          end)

        refute Resolver.enabled?(r, "A.exs  > FUTURE")
        assert Resolver.enabled?(r, "a.exs > past")
        assert Resolver.enabled?(r, "a.exs > nodate")
        assert Resolver.enabled?(r, "a.exs > unknown")

        assert Resolver.skip_message(r, "a.exs > future") ==
                 "[skipper] Test disabled until 2099-01-01"
      end)
    end

    test "falls back to disk cache, then fail-open, else error", %{cache: file} do
      fail = fn -> {:error, "boom"} end

      with_env(
        %{"SKIPPER_CACHE_FILE" => file, "SKIPPER_CACHE_TTL" => "60", "SKIPPER_FAIL_OPEN" => nil},
        fn ->
          {:ok, _} =
            Resolver.initialize_with(fn -> {:ok, [entry("x > y", date("2099-01-01"))]} end)

          {:ok, cached} = Resolver.initialize_with(fail)
          refute Resolver.enabled?(cached, "x > y")
        end
      )

      with_env(%{"SKIPPER_CACHE_FILE" => file, "SKIPPER_CACHE_TTL" => "0"}, fn ->
        {:ok, open} = Resolver.initialize_with(fail)
        assert Resolver.enabled?(open, "x > y")
      end)

      with_env(
        %{
          "SKIPPER_CACHE_FILE" => file,
          "SKIPPER_CACHE_TTL" => "0",
          "SKIPPER_FAIL_OPEN" => "FALSE"
        },
        fn ->
          assert {:error, "boom"} = Resolver.initialize_with(fail)
        end
      )
    end
  end

  describe "writer" do
    defp writer_api do
      FakeApi.new([
        {"main", 42,
         [
           ["notes", "testId", "disabledUntil"],
           ["", "test/a.exs > kept", "2099-01-01"],
           ["", "", ""],
           ["", "test/a.exs > gone", ""],
           ["", "malformed", ""],
           ["", "test/other.exs > untouched", ""]
         ]}
      ])
    end

    test "appends new ids and keeps rows without permission" do
      api = writer_api()

      with_env(%{"SKIPPER_SYNC_ALLOW_DELETE" => nil}, fn ->
        :ok =
          Writer.sync_with(api, cfg(), [
            "test/a.exs > Kept",
            "test/a.exs > new",
            "test/a.exs > NEW"
          ])
      end)

      assert FakeApi.state(api).appended == [["", "test/a.exs > new", ""]]
      assert FakeApi.state(api).batches == []
    end

    test "deletes stale rows of owned files, descending, using real row indexes" do
      api = writer_api()

      with_env(%{"SKIPPER_SYNC_ALLOW_DELETE" => "true"}, fn ->
        :ok = Writer.sync_with(api, cfg(), ["test/a.exs > kept"])
      end)

      starts = for b <- FakeApi.state(api).batches, do: b.deleteDimension.range.startIndex
      assert starts == [4, 3]
      assert hd(FakeApi.state(api).batches).deleteDimension.range.sheetId == 42
    end
  end

  test "report" do
    now = DateTime.utc_now()
    add = &DateTime.add(now, &1, :second)

    r =
      Report.build(
        %{
          "a" => add.(3 * 86_400 + 3600),
          "b" => add.(30 * 86_400 + 3600),
          "c" => add.(-86_400),
          "d" => nil
        },
        ["b", "a"],
        ["c"]
      )

    assert r.currently_suppressed == 2
    assert r.expiring_this_week == 1
    assert r.quarantine_days_debt == 33
    assert r.suppressed_this_run == ["a", "b"]
    md = Report.markdown(r)
    assert md =~ "## Skipper Quarantine Report"
    assert md =~ "### Re-enabled this run\n\n- `c`"
  end

  test "config from env and redacted inspect" do
    with_env(
      %{
        "SKIPPER_SPREADSHEET_ID" => "sid",
        "SKIPPER_CREDENTIALS_FILE" => nil,
        "GOOGLE_CREDS_B64" => "c2VjcmV0",
        "SKIPPER_SHEET_NAME" => "s",
        "SKIPPER_REFERENCE_SHEETS" => "a, b,,"
      },
      fn ->
        c = Config.from_env()
        assert c.credentials == {:base64, "c2VjcmV0"}
        assert c.reference_sheets == ["a", "b"]
        refute inspect(c) =~ "c2VjcmV0"
      end
    )

    with_env(%{"SKIPPER_SPREADSHEET_ID" => nil}, fn -> assert Config.from_env() == nil end)
  end
end
