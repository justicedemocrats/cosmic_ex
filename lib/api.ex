defmodule Cosmic.Api do
  use HTTPotion.Base
  @slug Application.get_env(:cosmic, :slug)

  defp process_url(url) do
    if String.length(url) > 0 do
      "https://api.cosmicjs.com/v1/#{@slug}/object/#{url}"
    else
      "https://api.cosmicjs.com/v1/#{@slug}"
    end
  end

  defp process_response_body(raw) do
    case Poison.decode(raw) do
      {:ok, map} -> map
      {:error, _error} -> raw
    end
  end
end
