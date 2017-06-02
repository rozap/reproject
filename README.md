# reproject
Reproject a point. This is just a nif that calls into proj4

## Setup
You need proj4 installed on your system. Install it with
```
sudo apt-get install libproj-dev
```
then
```
make
```

Then `mix test` should pass.

## Usage

Get the expanded projection definition
```elixir
iex> {:ok, prj} = Reproject.create('+init=epsg:4326')
iex> Reproject.get_def(prj)
" +init=epsg:4326 +proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"
```


Create a projection. This returns `{:ok, projection}` where projection
is an opaque pointer referring to a C struct
```elixir
iex> Reproject.create('+init=epsg:4326')
{:ok, ""}
```

Transform a point from source projection to dest projection
```elixir
iex> {:ok, wgs84} = Reproject.create('+init=epsg:4326')
iex> {:ok, crs2180} = Reproject.create('+init=epsg:2180')
iex> Reproject.transform(wgs84, crs2180, {21.049804687501, 52.22900390625})
{:ok, {639951.5695094677, 486751.7840663176}}
```
