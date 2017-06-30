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
end
