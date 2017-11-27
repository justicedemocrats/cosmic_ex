defmodule Cosmic do
  require Logger

  @slug Application.get_env(:cosmic, :slug)
  @slugs Application.get_env(:cosmic, :slugs)

  def prefix(slug, bucket_slug \\ @slug) do
    "#{bucket_slug}/#{slug}"
  end

  def fetch_all do
    if @slug != nil do
      bucket = fetch_bucket(@slug)
      cache_bucket(bucket)
    else
      bucket_tasks = Enum.map(@slugs, fn slug -> Task.async(fn -> fetch_bucket(slug) end) end)
      buckets = Enum.map(bucket_tasks, fn b -> Task.await(b, 150_000) end)

      Enum.map(buckets, &cache_bucket/1)
      tasks = Enum.map(@slugs, fn slug -> Task.async(fn -> fetch_bucket(slug) end) end)
      Enum.each(tasks, fn t -> Task.await(t, 15_000) end)
    end
  end

  def fetch_bucket(bucket_slug) do
    %{body: %{"bucket" => %{"objects" => objects}}} =
      Cosmic.Api.get("", query: %{hide_metafields: true}, slug: bucket_slug, timeout: 150_000)

    {bucket_slug, objects}
  end

  def cache_bucket({bucket_slug, objects}) do
    # Store each object
    Enum.each(objects, fn object ->
      Stash.set(:cosmic_cache, prefix(object["slug"], bucket_slug), object)
    end)

    # For each type, store an array of slugs
    objects
    |> Enum.map(fn %{"type_slug" => type} -> type end)
    |> MapSet.new()
    |> Enum.each(curry_cache_type_slugs(objects, bucket_slug))

    Logger.info(
      "Fetched cosmic data for #{bucket_slug} on #{DateTime.utc_now() |> DateTime.to_iso8601()}"
    )
  end

  defp on_no_exist(path) do
    IO.puts("Path #{path} is not cached. fetching...")
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
    |> Enum.map(&Stash.get(:cosmic_cache, prefix(&1, bucket_slug)))
  end

  def update() do
    Stash.clear(:cosmic_cache)
    fetch_all()

    Logger.info(
      "Cleared cosmic cache and updated it on #{DateTime.utc_now() |> DateTime.to_iso8601()}"
    )
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
