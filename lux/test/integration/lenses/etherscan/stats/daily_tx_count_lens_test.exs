defmodule Lux.Integration.Etherscan.DailyTxCountLensTest do
  @moduledoc false
  use IntegrationCase, async: false
  @moduletag timeout: 120_000

  alias Lux.Lenses.Etherscan.DailyTxCount
  alias Lux.Lenses.Etherscan.RateLimitedAPI

  # Example date range (one month)
  @start_date "2023-01-01"
  @end_date "2023-01-31"

  # Add a delay between tests to avoid hitting the API rate limit
  setup do
    # Use our rate limiter instead of Process.sleep
    RateLimitedAPI.throttle_standard_api()
    :ok
  end

  defmodule NoAuthDailyTxCountLens do
    @moduledoc """
    Going to call the api without auth so that we always fail
    """
    use Lux.Lens,
      name: "Etherscan Daily Transaction Count API",
      description: "Fetches the number of transactions performed on the Ethereum blockchain per day",
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
      |> Map.put(:action, "dailytx")
    end
  end

  # Helper function to check if we have a Pro API key
  defp has_pro_api_key? do
    # Make a test call to see if we get a Pro API error
    case RateLimitedAPI.call_standard(DailyTxCount, :focus, [%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    }]) do
      {:error, %{result: result}} ->
        # If the result contains "API Pro endpoint", we don't have a Pro API key
        not String.contains?(result, "API Pro endpoint")
      _ ->
        # If we get any other response, assume we have a Pro API key
        true
    end
  end

  test "can fetch daily transaction count with required parameters" do
    # Skip this test if we don't have a Pro API key
    if not has_pro_api_key?() do
      IO.puts("Skipping test: Pro API key required for DailyTxCount")
      :ok
    else
      assert {:ok, %{result: tx_count_data, daily_tx_count: tx_count_data}} =
               RateLimitedAPI.call_standard(DailyTxCount, :focus, [%{
                 startdate: @start_date,
                 enddate: @end_date,
                 chainid: 1
               }])

      # Verify the structure of the response
      assert is_list(tx_count_data)

      # If we got data, check the first entry
      if length(tx_count_data) > 0 do
        first_entry = List.first(tx_count_data)
        assert Map.has_key?(first_entry, :utc_date)
        assert Map.has_key?(first_entry, :tx_count)

        # Transaction count should be a positive integer
        assert is_integer(first_entry.tx_count)
        assert first_entry.tx_count >= 0

        # Log the data for informational purposes
        IO.puts("Date: #{first_entry.utc_date}")
        IO.puts("Transaction Count: #{first_entry.tx_count}")
      end
    end
  end

  test "can specify different sort order" do
    # Skip this test if we don't have a Pro API key
    if not has_pro_api_key?() do
      IO.puts("Skipping test: Pro API key required for DailyTxCount")
      :ok
    else
      assert {:ok, %{result: tx_count_data}} =
               RateLimitedAPI.call_standard(DailyTxCount, :focus, [%{
                 startdate: @start_date,
                 enddate: @end_date,
                 sort: "desc",
                 chainid: 1
               }])

      # Verify the structure of the response
      assert is_list(tx_count_data)

      # If we got data, check that it's in descending order
      if length(tx_count_data) > 1 do
        first_date = List.first(tx_count_data).utc_date
        second_date = Enum.at(tx_count_data, 1).utc_date

        # In descending order, the first date should be later than the second date
        assert first_date >= second_date
      end
    end
  end

  test "fails when no auth is provided" do
    # The NoAuthDailyTxCountLens doesn't have an API key, so it should fail
    result = RateLimitedAPI.call_standard(NoAuthDailyTxCountLens, :focus, [%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    }])

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
    result = RateLimitedAPI.call_standard(DailyTxCount, :focus, [%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    }])

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
      IO.puts("Skipping test: Pro API key required for DailyTxCount")
      :ok
    else
      # Missing startdate and enddate
      result = RateLimitedAPI.call_standard(DailyTxCount, :focus, [%{
        chainid: 1
      }])

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
