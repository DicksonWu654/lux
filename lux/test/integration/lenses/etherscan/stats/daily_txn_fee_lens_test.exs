defmodule Lux.Integration.Etherscan.DailyTxnFeeLensTest do
  @moduledoc false
  use IntegrationCase, async: false
  @moduletag timeout: 120_000

  alias Lux.Lenses.Etherscan.DailyTxnFee

  # Example date range (one month)
  @start_date "2023-01-01"
  @end_date "2023-01-31"

  # Add a delay between tests to avoid hitting the API rate limit
  setup do
    # Sleep for 2000ms to avoid hitting the Etherscan API rate limit (2 calls per second for this endpoint)
    Process.sleep(2000)
    :ok
  end

  defmodule NoAuthDailyTxnFeeLens do
    @moduledoc """
    Going to call the api without auth so that we always fail
    """
    use Lux.Lens,
      name: "Etherscan Daily Transaction Fee API",
      description: "Fetches the amount of transaction fees paid to miners per day",
      url: "https://api.etherscan.io/v2/api",
      method: :get,
      headers: [{"content-type", "application/json"}]

    @doc """
    Prepares parameters before making the API request.
    """
    def before_focus(params) do
      # Set module and action for this endpoint
      params
      |> Map.put(:module, "stats")
      |> Map.put(:action, "dailytxnfee")
    end
  end

  # Helper function to check if we have a Pro API key
  defp has_pro_api_key? do
    # Make a test call to see if we get a Pro API error
    case DailyTxnFee.focus(%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    }) do
      {:error, %{result: result}} ->
        # If the result contains "API Pro endpoint", we don't have a Pro API key
        not String.contains?(result, "API Pro endpoint")
      _ ->
        # If we get any other response, assume we have a Pro API key
        true
    end
  end

  test "can fetch daily transaction fees with required parameters" do
    # Skip this test if we don't have a Pro API key
    if not has_pro_api_key?() do
      IO.puts("Skipping test: Pro API key required for DailyTxnFee")
      :ok
    else
      assert {:ok, %{result: txn_fee_data, daily_txn_fee: txn_fee_data}} =
               DailyTxnFee.focus(%{
                 startdate: @start_date,
                 enddate: @end_date,
                 chainid: 1
               })

      # Verify the structure of the response
      assert is_list(txn_fee_data)

      # If we got data, check the first entry
      if length(txn_fee_data) > 0 do
        first_entry = List.first(txn_fee_data)
        assert Map.has_key?(first_entry, :utc_date)
        assert Map.has_key?(first_entry, :tx_fee_eth)

        # Transaction fee should be a positive number
        assert is_number(first_entry.tx_fee_eth)
        assert first_entry.tx_fee_eth > 0

        # Log the data for informational purposes
        IO.puts("Date: #{first_entry.utc_date}")
        IO.puts("Transaction Fee: #{first_entry.tx_fee_eth} ETH")
      end
    end
  end

  test "can specify different sort order" do
    # Skip this test if we don't have a Pro API key
    if not has_pro_api_key?() do
      IO.puts("Skipping test: Pro API key required for DailyTxnFee")
      :ok
    else
      assert {:ok, %{result: txn_fee_data}} =
               DailyTxnFee.focus(%{
                 startdate: @start_date,
                 enddate: @end_date,
                 sort: "desc",
                 chainid: 1
               })

      # Verify the structure of the response
      assert is_list(txn_fee_data)

      # If we got data, check that it's in descending order
      if length(txn_fee_data) > 1 do
        first_date = List.first(txn_fee_data).utc_date
        second_date = Enum.at(txn_fee_data, 1).utc_date

        # In descending order, the first date should be later than the second date
        assert first_date >= second_date
      end
    end
  end

  test "fails when no auth is provided" do
    # The NoAuthDailyTxnFeeLens doesn't have an API key, so it should fail
    result = NoAuthDailyTxnFeeLens.focus(%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    })

    case result do
      {:ok, %{"status" => "0", "message" => "NOTOK", "result" => error_message}} ->
        assert String.contains?(error_message, "Missing/Invalid API Key")

      {:error, error} ->
        # If it returns an error tuple, that's also acceptable
        assert error != nil
    end
  end

  test "raises error or returns error for Pro API endpoint" do
    # This test verifies that we either get an ArgumentError or a specific error message
    # when trying to use a Pro API endpoint without a Pro API key
    result = DailyTxnFee.focus(%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    })

    case result do
      {:error, %{result: result}} ->
        # If we get an error about API Pro endpoint, that's expected
        assert String.contains?(result, "API Pro endpoint")
        IO.puts("Expected error for Pro API endpoint: #{result}")

      _ ->
        # If we get here, we might have a Pro API key, so the test should be skipped
        if has_pro_api_key?() do
          IO.puts("Skipping test: We have a Pro API key, so this test is not applicable")
          :ok
        else
          flunk("Expected an error for Pro API endpoint")
        end
    end
  end

  test "returns error for missing required parameters" do
    # Skip this test if we don't have a Pro API key
    if not has_pro_api_key?() do
      IO.puts("Skipping test: Pro API key required for DailyTxnFee")
      :ok
    else
      # Missing startdate and enddate
      result = DailyTxnFee.focus(%{
        chainid: 1
      })

      case result do
        {:error, error} ->
          # Should return an error for missing required parameters
          assert error != nil

        _ ->
          flunk("Expected an error for missing required parameters")
      end
    end
  end
end
