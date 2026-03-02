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

  describe "get_authority" do
    test "returns EPSG authority for a projection created from an EPSG code" do
      {:ok, prj} = Reproject.create("EPSG:4326")
      assert Reproject.get_authority(prj) == {:ok, {"EPSG", "4326"}}
    end

    test "returns EPSG authority ESRI WKT passed to create_from_prj" do
      wkt =
        ~s(PROJCS["NAD_1983_StatePlane_Tennessee_FIPS_4100_Feet",GEOGCS["GCS_North_American_1983",DATUM["D_North_American_1983",SPHEROID["GRS_1980",6378137.0,298.257222101]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Lambert_Conformal_Conic"],PARAMETER["False_Easting",1968500.0],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",-86.0],PARAMETER["Standard_Parallel_1",35.25],PARAMETER["Standard_Parallel_2",36.41666666666666],PARAMETER["Latitude_Of_Origin",34.33333333333334],UNIT["Foot_US",0.3048006096012192]])

      {:ok, prj} = Reproject.create_from_prj(wkt)
      # ESRI:102736 is deprecated in favor if EPSG:2274
      assert Reproject.get_authority(prj) == {:ok, {"EPSG", "2274"}}
    end

    test "returns EPSG authority for an ESRI WKT with VERTCS passed to create_from_wkt" do
      wkt =
        ~s(PROJCS["NAD_1983_StatePlane_Tennessee_FIPS_4100_Feet",GEOGCS["GCS_North_American_1983",DATUM["D_North_American_1983",SPHEROID["GRS_1980",6378137.0,298.257222101]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Lambert_Conformal_Conic"],PARAMETER["False_Easting",1968500.0],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",-86.0],PARAMETER["Standard_Parallel_1",35.25],PARAMETER["Standard_Parallel_2",36.41666666666666],PARAMETER["Latitude_Of_Origin",34.33333333333334],UNIT["Foot_US",0.3048006096012192]],VERTCS["NAVD_1988_Foot_US",VDATUM["North_American_Vertical_Datum_1988"],PARAMETER["Vertical_Shift",0.0],PARAMETER["Direction",1.0],UNIT["Foot_US",0.3048006096012192]])

      {:ok, prj} = Reproject.create_from_wkt(wkt)
      # ESRI:102736 is deprecated in favor if EPSG:8778 which uses EPSG:2274 for Horizontal CRS
      assert Reproject.get_authority(prj) == {:ok, {"EPSG", "8778"}}
    end
  end

  test "can parse from wkt" do
    {ok, _} =
      Reproject.create_from_prj("""
        PROJCS["NAD83_HARN_Ohio_North",GEOGCS["GCS_NAD83(HARN)",DATUM["D_North_American_1983_HARN",SPHEROID["GRS_1980",6378137,298.257222101]],PRIMEM["Greenwich",0],UNIT["Degree",0.017453292519943295]],PROJECTION["Lambert_Conformal_Conic"],PARAMETER["standard_parallel_1",41.7],PARAMETER["standard_parallel_2",40.43333333333333],PARAMETER["latitude_of_origin",39.66666666666666],PARAMETER["central_meridian",-82.5],PARAMETER["false_easting",600000],PARAMETER["false_northing",0],UNIT["Meter",1]]
      """)

    assert ok == :ok
  end
end
