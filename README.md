# reproject
Reproject a point. This is just a nif that calls into proj4 and gdal

## Setup
You need proj4 and gdal installed on your system. Install it with
```
sudo apt-get install libproj-dev libgdal1-dev
```
then
```
make
```

Then `mix test` should pass.

## Usage
Initialize a projection from a proj4 string
```elixir
iex> {:ok, prj} = Reproject.create("+init=epsg:4326")
```

Initialize a projection from a PRJ component of a shapefile
```elixir
{:ok, prj} = Reproject.create_from_prj("""
  GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433],AUTHORITY["EPSG",4326]]
""")
```

Initialize a projection from a WKT string
```elixir
{:ok, prj} = Reproject.create_from_wkt("""
  GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433],AUTHORITY["EPSG",4326]]
""")
```

Transform a point from source projection to dest projection
```elixir
iex> {:ok, wgs84} = Reproject.create("+init=epsg:4326")
iex> {:ok, crs2180} = Reproject.create("+init=epsg:2180")
iex> Reproject.transform(wgs84, crs2180, {21.049804687501, 52.22900390625})
{:ok, {639951.5695094677, 486751.7840663176}}
```

Get the expanded projection definition
```elixir
iex> Reproject.expand(prj)
" +init=epsg:4326 +proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"
```
