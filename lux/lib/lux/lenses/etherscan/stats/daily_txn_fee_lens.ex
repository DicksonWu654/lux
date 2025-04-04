defmodule Lux.Lenses.Etherscan.DailyTxnFee do
  @moduledoc """
  Lens for fetching the amount of transaction fees paid to miners per day from the Etherscan API.

  ## Examples

  Fetch daily transaction fees for a specific date range in ascending order:

      iex> Lux.Lenses.Etherscan.DailyTxnFee.focus(%{
      ...>   startdate: "2023-01-01",
      ...>   enddate: "2023-01-05",
      ...>   sort: "asc",
      ...>   chainid: 1
      ...> })
      {:ok, %{
        result: [
          %{utc_date: "2023-01-01", tx_fee_eth: 123.45},
          %{utc_date: "2023-01-02", tx_fee_eth: 234.56},
          %{utc_date: "2023-01-03", tx_fee_eth: 345.67}
        ],
        daily_txn_fee: [
          %{utc_date: "2023-01-01", tx_fee_eth: 123.45},
          %{utc_date: "2023-01-02", tx_fee_eth: 234.56},
          %{utc_date: "2023-01-03", tx_fee_eth: 345.67}
        ]
      }}

  Fetch daily transaction fees for a specific date range in descending order:

      iex> Lux.Lenses.Etherscan.DailyTxnFee.focus(%{
      ...>   startdate: "2023-01-01",
      ...>   enddate: "2023-01-05",
      ...>   sort: "desc",
      ...>   chainid: 1
      ...> })
      {:ok, %{
        result: [
          %{utc_date: "2023-01-05", tx_fee_eth: 567.89},
          %{utc_date: "2023-01-04", tx_fee_eth: 456.78},
          %{utc_date: "2023-01-03", tx_fee_eth: 345.67}
        ],
        daily_txn_fee: [
          %{utc_date: "2023-01-05", tx_fee_eth: 567.89},
          %{utc_date: "2023-01-04", tx_fee_eth: 456.78},
          %{utc_date: "2023-01-03", tx_fee_eth: 345.67}
        ]
      }}
  """

  alias Lux.Lenses.Etherscan.Base

  use Lux.Lens,
    name: "Etherscan.DailyTxnFee",
    description: "Tracks daily transaction fee revenue paid to validators/miners in ETH",
    url: "https://api.etherscan.io/v2/api",
    method: :get,
    headers: [{"Content-Type", "application/json"}],
    auth: %{
      type: :custom,
      auth_function: &Base.add_api_key/1
    },
    schema: %{
      type: :object,
      properties: %{
        chainid: %{
          type: :integer,
          description: "Network identifier (1=Ethereum, 137=Polygon, 56=BSC, etc.)",
          default: 1
        },
        startdate: %{
          type: :string,
          description: "Beginning date for transaction fee data in yyyy-MM-dd format"
        },
        enddate: %{
          type: :string,
          description: "Ending date for transaction fee data in yyyy-MM-dd format"
        },
        sort: %{
          type: :string,
          description: "Chronological ordering of results (asc=oldest first, desc=newest first)",
          enum: ["asc", "desc"],
          default: "asc"
        }
      },
      required: ["startdate", "enddate"]
    }

  @doc """
  Prepares parameters for the API request.
  """
  def before_focus(params) do
    params = params
    |> Map.put(:module, "stats")
    |> Map.put(:action, "dailytxnfee")
    |> Map.put_new(:sort, "asc")
    
    # Check if this endpoint requires a Pro API key
    case Base.check_pro_endpoint("stats", "dailytxnfee") do
      {:ok, _} -> params
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Processes the API response.
  """
  @impl true
  def after_focus(response) do
    case Base.process_response(response) do
      {:ok, %{result: result}} when is_list(result) ->
        txn_fee_data =
          Enum.map(result, fn item ->
            %{
              utc_date: item["UTCDate"],
              tx_fee_eth: parse_float_or_keep(item["transactionFee_Eth"])
            }
          end)

        {:ok, %{result: txn_fee_data, daily_txn_fee: txn_fee_data}}

      {:error, %{result: "No data found"}} ->
        {:ok, %{result: [], daily_txn_fee: []}}

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
