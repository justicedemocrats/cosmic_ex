defmodule Cosmic do
  require Logger

  @slug Application.get_env(:cosmic, :slug)
  @slugs Application.get_env(:cosmic, :slugs)

  def prefix(slug, bucket_slug \\ @slug) do
    "#{bucket_slug}/#{slug}"
  end

  def fetch_all do
    if @slug != nil do
      fetch_bucket(@slug)
    else
      Enum.each @slugs, &fetch_bucket/1
    end
  end

  def fetch_bucket(bucket_slug) do
    try do
      %{body: %{"bucket" => %{"objects" => objects }}} = Cosmic.Api.get("", slug: bucket_slug)

      # Store each object
      Enum.each(objects, fn object -> Stash.set(:cosmic_cache, prefix(object["slug"], bucket_slug), object) end)

      # For each type, store an array of slugs
      objects
      |> Enum.map(fn %{"type_slug" => type} -> type end)
      |> MapSet.new
      |> Enum.each(curry_cache_type_slugs(objects, bucket_slug))

      Stash.persist(:cosmic_cache, "./cosmic_cache")
      Logger.info "Fetched cosmic data for #{bucket_slug} on #{DateTime.utc_now() |> DateTime.to_iso8601()}"
    rescue
      _e in MatchError ->
        Logger.error "Could not fetch cosmic data - using latest cached version"
        Stash.load(:cosmic_cache, "./cosmic_cache")
    end
  end

  defp on_no_exist(path) do
    IO.puts "Path #{path} is not cached. fetching..."
    %{body: body} = Cosmic.Api.get(path)
    Stash.set(:cosmic_cache, path, body)
    body
  end

  def get(path, bucket_slug \\ @slug) do
    case Stash.get(:cosmic_cache, prefix(path, bucket_slug)) do
      nil -> on_no_exist(path)
      val -> val
    end
  end

  def get_type(type, bucket_slug \\ @slug) do
    type
    |> (fn t -> Stash.get(:cosmic_cache, prefix(t, bucket_slug)) end).()
    |> Enum.map(&(Stash.get(:cosmic_cache, prefix(&1, bucket_slug))))
  end

  def update() do
    Stash.clear(:cosmic_cache)
    fetch_all()
    Logger.info "Cleared cosmic cache and updated it on #{DateTime.utc_now() |> DateTime.to_iso8601()}"
  end

  def curry_cache_type_slugs(objects, bucket_slug) do
    fn type ->
      matches =
        objects
        |> Enum.filter(fn %{"type_slug" => match} -> match == type end)
        |> Enum.map(fn %{"slug" => slug} -> slug end)

      Stash.set(:cosmic_cache, prefix(type, bucket_slug), matches)
    end
  end
end
