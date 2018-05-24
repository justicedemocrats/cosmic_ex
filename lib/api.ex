defmodule Cosmic.Api do
  use HTTPotion.Base

  def get_slug, do: Application.get_env(:cosmic, :slug)

  defp process_url(url, opts) do
    slug = Keyword.get(opts, :slug, get_slug())

    cond do
      # GET /
      String.length(url) == 0 ->
        "https://api.cosmicjs.com/v1/#{slug}"

      # POST, PUT /edit-object-type, etc.
      contains_one(url, ["object-type", "edit-object", "add-object"]) ->
        "https://api.cosmicjs.com/v1/#{slug}/#{url}"

      # Regular GET /slug
      true ->
        "https://api.cosmicjs.com/v1/#{slug}/object/#{url}"
    end
  end

  defp process_request_headers(hdrs) do
    Enum.into(hdrs, Accept: "application/json", "Content-Type": "application/json")
  end

  defp process_request_body(body) when is_map(body) do
    case Poison.encode(body) do
      {:ok, encoded} -> encoded
      {:error, problem} -> problem
    end
  end

  defp process_request_body(body) do
    body
  end

  defp process_response_body(raw) do
    case Poison.decode(raw) do
      {:ok, map} -> map
      {:error, _error} -> raw
    end
  end

  def contains_one(string, substrings) do
    contains_n =
      substrings
      |> Enum.filter(fn sub -> String.contains?(string, sub) end)
      |> length()

    contains_n > 0
  end
end
