defmodule Cosmic do
  require Logger
  alias Phoenix.{PubSub}

  def get_slug, do: Application.get_env(:cosmic, :slug)
  def get_slugs, do: Application.get_env(:cosmic, :slugs)

  # ------------ Start GenServer stuff -----------
  use GenServer

  def start_link(opts) do
    app_name = Keyword.get(opts, :application, :cosmic)
    GenServer.start_link(__MODULE__, app_name, [])
  end

  def init(app_name) do
    PubSub.subscribe(app_name, "update")
    fetch_all()
    {:ok, %{}}
  end

  def handle_info("update", _) do
    fetch_all()
    {:noreply, %{}}
  end

  # ------------- standard local ets caching -------
  def prefix(slug, bucket_slug \\ false) do
    bucket = if bucket_slug, do: bucket_slug, else: get_slug()
    "#{bucket}/#{slug}"
  end

  def fetch_all do
    if get_slug() != nil do
      bucket = fetch_bucket(get_slug())
      cache_bucket(bucket)
    else
      bucket_tasks =
        Enum.map(get_slugs(), fn slug -> Task.async(fn -> fetch_bucket(slug) end) end)

      buckets = Enum.map(bucket_tasks, fn b -> Task.await(b, 150_000) end)

      Enum.map(buckets, &cache_bucket/1)
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

  def get(path, bucket_slug \\ false) do
    bucket = if bucket_slug, do: bucket_slug, else: get_slug()

    case Stash.get(:cosmic_cache, prefix(path, bucket_slug)) do
      nil -> on_no_exist(path)
      val -> val
    end
  end

  def get_type(type, bucket_slug \\ false) do
    bucket = if bucket_slug, do: bucket_slug, else: get_slug()

    type
    |> (fn t -> Stash.get(:cosmic_cache, prefix(t, bucket_slug)) end).()
    |> Enum.map(&Stash.get(:cosmic_cache, prefix(&1, bucket_slug)))
  end

  defp on_no_exist(path) do
    Logger.info("Path #{path} is not cached. Fetching...")

    path
    |> Cosmic.Api.get()
    |> process_response_body(path)
  end

  defp process_response_body(%{body: body, status_code: status_code}, path)
       when status_code == 200 do
    Stash.set(:cosmic_cache, path, body)
    body["object"] || body["objects"]
  end

  defp process_response_body(%{status_code: status_code}, path) do
    %{
      "content" => "#{status_code}! Failed to fetch cosmic data for #{path}",
      "error" => true,
      "failed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "path" => path,
      "status_code" => status_code
    }
  end

  defp process_response_body(_, path), do: "Unknown error while fetching cosmic data for #{path}"

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
