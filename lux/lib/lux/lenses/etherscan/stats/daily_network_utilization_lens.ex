defmodule Lux.Lenses.Etherscan.DailyNetworkUtilizationLens do
  @moduledoc """
  Lens for fetching the daily network utilization (gas used / gas limit) from the Etherscan API.

  ## Examples

  Fetch daily network utilization for a specific date range in ascending order:

      iex> Lux.Lenses.Etherscan.DailyNetworkUtilizationLens.focus(%{
      ...>   startdate: "2023-01-01",
      ...>   enddate: "2023-01-05",
      ...>   sort: "asc",
      ...>   chainid: 1
      ...> })
      {:ok, %{
        result: [
          %{utc_date: "2023-01-01", utilization_percentage: 45.67},
          %{utc_date: "2023-01-02", utilization_percentage: 52.34},
          %{utc_date: "2023-01-03", utilization_percentage: 48.91}
        ],
        daily_network_utilization: [
          %{utc_date: "2023-01-01", utilization_percentage: 45.67},
          %{utc_date: "2023-01-02", utilization_percentage: 52.34},
          %{utc_date: "2023-01-03", utilization_percentage: 48.91}
        ]
      }}

  Fetch daily network utilization for a specific date range in descending order:

      iex> Lux.Lenses.Etherscan.DailyNetworkUtilizationLens.focus(%{
      ...>   startdate: "2023-01-01",
      ...>   enddate: "2023-01-05",
      ...>   sort: "desc",
      ...>   chainid: 1
      ...> })
      {:ok, %{
        result: [
          %{utc_date: "2023-01-05", utilization_percentage: 51.23},
          %{utc_date: "2023-01-04", utilization_percentage: 49.78},
          %{utc_date: "2023-01-03", utilization_percentage: 48.91}
        ],
        daily_network_utilization: [
          %{utc_date: "2023-01-05", utilization_percentage: 51.23},
          %{utc_date: "2023-01-04", utilization_percentage: 49.78},
          %{utc_date: "2023-01-03", utilization_percentage: 48.91}
        ]
      }}
  """

  alias Lux.Lenses.Etherscan.BaseLens

  use Lux.Lens,
    url: "https://api.etherscan.io/v2/api",
    method: :get,
    headers: [{"Content-Type", "application/json"}],
    auth: %{
      type: :custom,
      auth_function: &BaseLens.add_api_key/1
    },
    schema: [
      chainid: [type: :integer, required: true],
      startdate: [type: :string, required: true],
      enddate: [type: :string, required: true],
      sort: [type: :string, required: false]
    ]

  @doc """
  Prepares parameters for the API request.
  """
  def before_focus(params) do
    params
    |> Map.put(:module, "stats")
    |> Map.put(:action, "dailynetworkutilization")
    |> Map.put_new(:sort, "asc")
  end

  @doc """
  Processes the API response.
  """
  @impl true
  def after_focus(response) do
    case BaseLens.process_response(response) do
      {:ok, %{result: result}} when is_list(result) ->
        network_utilization_data =
          Enum.map(result, fn item ->
            %{
              utc_date: item["UTCDate"],
              utilization_percentage: parse_float_or_keep(item["utilizationPercentage"])
            }
          end)

        {:ok, %{result: network_utilization_data, daily_network_utilization: network_utilization_data}}

      {:error, %{result: "No data found"}} ->
        {:ok, %{result: [], daily_network_utilization: []}}

      {:error, %{result: "This endpoint requires a Pro subscription"}} ->
        {:error, %{message: "Error", result: "This endpoint requires an Etherscan Pro API key."}}

      other ->
        other
    end
  end

  defp parse_float_or_keep(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, _} -> float_value
      :error -> value
    end
  end

  defp parse_float_or_keep(value), do: value
end
