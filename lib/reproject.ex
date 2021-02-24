defmodule Reproject do
  @on_load {:init, 0}

  app = Mix.Project.config[:app]


  def init do
    path = :filename.join(:code.priv_dir(unquote(app)), 'reproject')
    :ok = :erlang.load_nif(path, 0)
  end

  @doc """
    Get the expanded projection definition

    iex> {:ok, prj} = Reproject.create("+init=epsg:4326")
    iex> Reproject.expand(prj)
    " +init=epsg:4326 +proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"
  """
  def expand(_), do: {:error, :nif_not_loaded}

  @doc """
    Create a projection. This returns `{:ok, projection}` where projection
    is an opaque pointer referring to a C struct

    iex> {:ok, _} = Reproject.create("+init=epsg:4326")
  """
  def create(b) when is_binary(b), do: :binary.bin_to_list(b) |> do_create
  def do_create(_), do: {:error, :nif_not_loaded}



  @doc """
    Create a projection from a WKT. This returns the same thing as the `create/1` function.

    iex> {:ok, _} = Reproject.create_from_wkt("GEOGCS[\\"GCS_WGS_1984\\",DATUM[\\"D_WGS_1984\\",SPHEROID[\\"WGS_1984\\",6378137.0,298.257223563]],PRIMEM[\\"Greenwich\\",0.0],UNIT[\\"Degree\\",0.0174532925199433],AUTHORITY[\\"EPSG\\",4326]]")

  """
  def create_from_wkt(wkt) when is_binary(wkt) do
    wkt_l = wkt
    |> String.trim
    |> :binary.bin_to_list

    do_create_from_wkt(length(wkt_l), wkt_l, 0)
  end
  def do_create_from_wkt(_, _, _), do: {:error, :nif_not_loaded}


  @doc """
    Create a projection from a WKT, like the one in the .prj component
    of a shapefile. This returns the same thing as the `create/1` function.

    iex> {:ok, _} = Reproject.create_from_wkt("GEOGCS[\\"GCS_WGS_1984\\",DATUM[\\"D_WGS_1984\\",SPHEROID[\\"WGS_1984\\",6378137.0,298.257223563]],PRIMEM[\\"Greenwich\\",0.0],UNIT[\\"Degree\\",0.0174532925199433],AUTHORITY[\\"EPSG\\",4326]]")

  """
  def create_from_prj(wkt) when is_binary(wkt) do
    wkt_l = wkt
    |> String.trim
    |> :binary.bin_to_list

    do_create_from_wkt(length(wkt_l), wkt_l, 1)
  end



  @doc """
    Transform a point from source projection to dest projection

    iex> {:ok, wgs84} = Reproject.create("+init=epsg:4326")
    iex> {:ok, crs2180} = Reproject.create("+init=epsg:2180")
    iex> {:ok, {x, y}} = Reproject.transform(wgs84, crs2180, {21.049804687501, 52.22900390625})
    iex> {is_number(x), is_number(y)}
    {true, true}
  """
  def transform_2d(_, _, _), do: {:error, :nif_not_loaded}
  def transform_3d(_, _, _), do: {:error, :nif_not_loaded}

  def transform(src, dst, {_x, _y} = p),     do: transform_2d(src, dst, p)
  def transform(src, dst, {_x, _y, _z} = p), do: transform_3d(src, dst, p)
end
