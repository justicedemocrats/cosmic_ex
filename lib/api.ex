defmodule Cosmic.Api do
  use HTTPotion.Base
  @slug Application.get_env(:cosmic, :slug)

  defp process_url(url) do
    if String.length(url) > 0 do
      if String.contains?(url, "object-type") do
        "https://api.cosmicjs.com/v1/#{@slug}/#{url}"
      else
        "https://api.cosmicjs.com/v1/#{@slug}/object/#{url}"
      end
    else
      "https://api.cosmicjs.com/v1/#{@slug}"
    end
  end

  defp process_request_headers(hdrs) do
    Enum.into(hdrs, ["Accept": "application/json", "Content-Type": "application/json"])
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
end
