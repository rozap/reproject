# reproject

Reproject a point. NIF bindings to [PROJ](https://proj.org/) (v9) and GDAL for coordinate system transformations.

## Installation

Add `reproject` to your dependencies:

```elixir
def deps do
  [
    {:reproject, "~> 1.0"}
  ]
end
```

Precompiled binaries are provided for common platforms (Linux x86_64/aarch64, macOS x86_64/aarch64). `mix deps.get` will download the appropriate binary automatically.

### Building from source

To build from source (for development or unsupported platforms):

```bash
bash scripts/build_libs.sh
REPROJECT_BUILD_FROM_SOURCE=1 BUNDLED_LIBS_PREFIX=prebuilt mix compile
mix test
```

`scripts/build_libs.sh` builds static PROJ, GDAL, and SQLite3 libraries — via Docker on Linux, or Homebrew + source on macOS.

## Usage

Initialize a projection from an EPSG code:

```elixir
iex> {:ok, prj} = Reproject.create("EPSG:4326")
```

Initialize a projection from a PRJ component of a shapefile:

```elixir
{:ok, prj} = Reproject.create_from_prj("""
  GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433],AUTHORITY["EPSG",4326]]
""")
```

Initialize a projection from a WKT string:

```elixir
{:ok, prj} = Reproject.create_from_wkt("""
  GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433],AUTHORITY["EPSG",4326]]
""")
```

Transform a point from source projection to dest projection:

```elixir
iex> {:ok, wgs84} = Reproject.create("EPSG:4326")
iex> {:ok, crs2180} = Reproject.create("EPSG:2180")
iex> Reproject.transform(wgs84, crs2180, {21.049804687501, 52.22900390625})
{:ok, {639951.5695094677, 486751.7840663176}}
```

Get the expanded projection definition:

```elixir
iex> {:ok, prj} = Reproject.create("EPSG:4326")
iex> Reproject.expand(prj)
"+proj=longlat +datum=WGS84 +no_defs +type=crs"
```
