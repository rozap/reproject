defmodule ReprojectTest do
  use ExUnit.Case
  doctest Reproject
  require Reproject

  test "returns an error on invalid projection" do
    {:error, _} = Reproject.create("foo")
  end

  test "can reproject stuff" do
    {:ok, wgs84} = Reproject.create("+init=epsg:4326")
    {:ok, crs2180} =  Reproject.create("+init=epsg:2180")
    p = {21.049804687501, 52.22900390625}
    {:ok, {x, y}} = Reproject.transform(wgs84, crs2180, p)

    assert_in_delta(639951.569509, x, 0.000001)
    assert_in_delta(486751.784066, y, 0.000001)
  end

  test "can create a projection from wkt" do
    {:ok, wgs84} = Reproject.create_from_wkt("""
      GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433],AUTHORITY["EPSG",4326]]
    """)
    {:ok, crs2180} =  Reproject.create("+init=epsg:2180")
    p = {21.049804687501, 52.22900390625}
    {:ok, {x, y}} = Reproject.transform(wgs84, crs2180, p)

    assert_in_delta(639951.569509, x, 0.000001)
    assert_in_delta(486751.784066, y, 0.000001)
  end

  test "can parse from wkt" do
    {ok, _} = Reproject.create_from_prj("""
      PROJCS["NAD83_HARN_Ohio_North",GEOGCS["GCS_NAD83(HARN)",DATUM["D_North_American_1983_HARN",SPHEROID["GRS_1980",6378137,298.257222101]],PRIMEM["Greenwich",0],UNIT["Degree",0.017453292519943295]],PROJECTION["Lambert_Conformal_Conic"],PARAMETER["standard_parallel_1",41.7],PARAMETER["standard_parallel_2",40.43333333333333],PARAMETER["latitude_of_origin",39.66666666666666],PARAMETER["central_meridian",-82.5],PARAMETER["false_easting",600000],PARAMETER["false_northing",0],UNIT["Meter",1]]
    """)

    assert ok == :ok
  end
end
