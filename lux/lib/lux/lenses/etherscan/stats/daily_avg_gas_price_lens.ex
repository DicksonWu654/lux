defmodule Lux.Lenses.Etherscan.DailyAvgGasPrice do
  @moduledoc """
  Lens for fetching the daily average gas price used on the Ethereum network from the Etherscan API.

  ## Examples

  ```elixir
  # Get daily average gas price for a specific date range with ascending sort (default chainid: 1 for Ethereum)
  Lux.Lenses.Etherscan.DailyAvgGasPrice.focus(%{
    startdate: "2023-01-01",
    enddate: "2023-01-31",
    sort: "asc"
  })

  # Get daily average gas price for a specific date range with descending sort on a specific chain
  Lux.Lenses.Etherscan.DailyAvgGasPrice.focus(%{
    startdate: "2023-01-01",
    enddate: "2023-01-31",
    sort: "desc",
    chainid: 1
  })
  ```
  """

  alias Lux.Lenses.Etherscan.Base

  use Lux.Lens,
    name: "Etherscan Daily Average Gas Price API",
    description: "Fetches the daily average gas price used on the Ethereum network",
    url: "https://api.etherscan.io/v2/api",
    method: :get,
    headers: [{"content-type", "application/json"}],
    auth: %{
      type: :custom,
      auth_function: &Base.add_api_key/1
    },
    schema: %{
      type: :object,
      properties: %{
        chainid: %{
          type: :integer,
          description: "Chain ID to query (e.g., 1 for Ethereum)",
          default: 1
        },
        startdate: %{
          type: :string,
          description: "The starting date in yyyy-MM-dd format, e.g., 2023-01-01"
        },
        enddate: %{
          type: :string,
          description: "The ending date in yyyy-MM-dd format, e.g., 2023-01-31"
        },
        sort: %{
          type: :string,
          description: "The sorting preference, use asc to sort by ascending and desc to sort by descending",
          enum: ["asc", "desc"],
          default: "asc"
        }
      },
      required: ["startdate", "enddate"]
    }

  @doc """
  Prepares parameters before making the API request.
  """
  def before_focus(params) do
    # Set module and action for this endpoint
    params
    |> Map.put(:module, "stats")
    |> Map.put(:action, "dailyavggasprice")
  end

  @doc """
  Transforms the API response into a more usable format.
  """
  @impl true
  def after_focus(response) do
    case Base.process_response(response) do
      {:ok, %{result: result}} when is_list(result) ->
        # Process the list of daily gas price data
        processed_results = Enum.map(result, fn data ->
          %{
            utc_date: Map.get(data, "UTCDate", ""),
            gas_price: parse_float_or_keep(Map.get(data, "avgGasPrice_Wei", ""))
          }
        end)

        # Return a structured response
        {:ok, %{
          result: processed_results,
          daily_avg_gas_price: processed_results
        }}
      {:error, %{result: "No data found"}} ->
        # Handle empty results
        {:ok, %{
          result: [],
          daily_avg_gas_price: []
        }}
      {:error, %{result: "This endpoint requires a Pro subscription"}} ->
        # Handle Pro API key errors
        {:error, %{message: "Error", result: "This endpoint requires an Etherscan Pro API key."}}
      other ->
        # Pass through other responses (like errors)
        other
    end
  end

  # Helper function to parse string to float or keep as is
  defp parse_float_or_keep(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, _} -> float_value
      :error -> value
    end
  end
  defp parse_float_or_keep(value), do: value
end
