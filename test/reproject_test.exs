defmodule ReprojectTest do
  use ExUnit.Case
  doctest Reproject
  require Reproject

  test "returns an error on invalid projection" do
    {:error, _} = Reproject.create("foo")
  end

  test "can expand a wkid" do
    {:ok, wgs84} = Reproject.create("EPSG:4326")
    assert Reproject.expand(wgs84) == "+proj=longlat +datum=WGS84 +no_defs +type=crs"
  end

  test "can reproject stuff" do
    {:ok, wgs84} = Reproject.create("EPSG:4326")
    {:ok, crs2180} = Reproject.create("EPSG:2180")
    p = {21.049804687501, 52.22900390625}
    {:ok, {x, y}} = Reproject.transform(wgs84, crs2180, p)

    assert_in_delta(639_951.569509, x, 0.00001)
    assert_in_delta(486_751.784066, y, 0.00001)
  end

  @tag skip: true
  test "can create a projection from wkt" do
    # This is broken due to the proj update - don't have time right now to
    # fix it, TODO
    {:ok, wgs84} =
      Reproject.create_from_wkt("""
        GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433],AUTHORITY["EPSG",4326]]
      """)

    {:ok, crs2180} = Reproject.create("EPSG:2180")
    p = {21.049804687501, 52.22900390625}
    {:ok, {x, y}} = Reproject.transform(wgs84, crs2180, p)

    assert_in_delta(639_951.569509, x, 0.00001)
    assert_in_delta(486_751.784066, y, 0.00001)
  end

  @tag timeout: 120_000
  test "concurrent transforms sharing one projection don't corrupt PROJ state" do
    # Regression test: create/transform are dirty NIFs that run on multiple BEAM
    # scheduler threads at once. They used to share PROJ's global PJ_DEFAULT_CTX,
    # which is not thread-safe (its proj.db SQLite handle in particular), so
    # concurrent calls corrupted it and crashed the VM (SIGSEGV/SIGABRT/SIGBUS),
    # often deferred to GC/shutdown. With a private context per resource and a
    # fresh local context per transform, this must run clean.
    {:ok, wgs84} = Reproject.create("EPSG:4326")
    {:ok, crs2180} = Reproject.create("EPSG:2180")

    p = {21.049804687501, 52.22900390625}
    expected_x = 639_951.569509
    expected_y = 486_751.784066

    procs = 64
    iterations = 25

    results =
      1..procs
      |> Task.async_stream(
        fn _ ->
          # Hammer the two shared projection resources from many processes at once.
          Enum.each(1..iterations, fn _ ->
            {:ok, {x, y}} = Reproject.transform(wgs84, crs2180, p)
            assert_in_delta(expected_x, x, 0.00001)
            assert_in_delta(expected_y, y, 0.00001)
          end)

          :ok
        end,
        max_concurrency: procs,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, res} -> res end)

    assert Enum.all?(results, &(&1 == :ok))
    assert length(results) == procs
  end

  test "concurrent create + transform from many processes stays stable" do
    # Exercises the cold proj.db lookup path (create) concurrently as well, since
    # proj_create reads proj.db through the context's SQLite handle.
    p = {21.049804687501, 52.22900390625}

    results =
      1..100
      |> Task.async_stream(
        fn _ ->
          {:ok, wgs84} = Reproject.create("EPSG:4326")
          {:ok, crs2180} = Reproject.create("EPSG:2180")
          {:ok, {x, y}} = Reproject.transform(wgs84, crs2180, p)
          assert_in_delta(639_951.569509, x, 0.00001)
          assert_in_delta(486_751.784066, y, 0.00001)
          :ok
        end,
        max_concurrency: 100,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, res} -> res end)

    assert Enum.all?(results, &(&1 == :ok))
  end

  test "can parse from wkt" do
    {ok, _} =
      Reproject.create_from_prj("""
        PROJCS["NAD83_HARN_Ohio_North",GEOGCS["GCS_NAD83(HARN)",DATUM["D_North_American_1983_HARN",SPHEROID["GRS_1980",6378137,298.257222101]],PRIMEM["Greenwich",0],UNIT["Degree",0.017453292519943295]],PROJECTION["Lambert_Conformal_Conic"],PARAMETER["standard_parallel_1",41.7],PARAMETER["standard_parallel_2",40.43333333333333],PARAMETER["latitude_of_origin",39.66666666666666],PARAMETER["central_meridian",-82.5],PARAMETER["false_easting",600000],PARAMETER["false_northing",0],UNIT["Meter",1]]
      """)

    assert ok == :ok
  end
end
