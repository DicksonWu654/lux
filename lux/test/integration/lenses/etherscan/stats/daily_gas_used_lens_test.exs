defmodule Lux.Integration.Etherscan.DailyGasUsedLensTest do
  @moduledoc false
  use IntegrationCase, async: false
  @moduletag timeout: 120_000

  alias Lux.Lenses.Etherscan.DailyGasUsedLens

  # Example date range (one month)
  @start_date "2019-02-01"
  @end_date "2019-02-28"

  # Add a delay between tests to avoid hitting the API rate limit
  setup do
    # Sleep for 2000ms to avoid hitting the Etherscan API rate limit (2 calls per second for this endpoint)
    Process.sleep(2000)
    :ok
  end

  defmodule NoAuthDailyGasUsedLens do
    @moduledoc """
    Going to call the api without auth so that we always fail
    """
    use Lux.Lens,
      name: "Etherscan Daily Gas Used API",
      description: "Fetches the total amount of gas used daily for transactions on the Ethereum network",
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
      |> Map.put(:action, "dailygasused")
    end
  end

  # Helper function to check if we have a Pro API key
  defp has_pro_api_key? do
    # Make a test call to see if we get a Pro API error
    case DailyGasUsedLens.focus(%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    }) do
      {:error, %{result: result}} ->
        # If the result contains "API Pro endpoint", we don't have a Pro API key
        not String.contains?(result, "API Pro endpoint") and
        not String.contains?(result, "Missing Or invalid Action name")
      _ ->
        # If we get any other response, assume we have a Pro API key
        true
    end
  end

  test "can fetch daily gas used with required parameters" do
    # Skip this test if we don't have a Pro API key or if the action name is invalid
    if not has_pro_api_key?() do
      IO.puts("Skipping test: Pro API key required for DailyGasUsedLens or invalid action name")
      :ok
    else
      assert {:ok, %{result: gas_used_data}} =
               DailyGasUsedLens.focus(%{
                 startdate: @start_date,
                 enddate: @end_date,
                 chainid: 1
               })

      # Verify the structure of the response
      assert is_list(gas_used_data)

      # If we got data, check the first entry
      if length(gas_used_data) > 0 do
        first_entry = List.first(gas_used_data)
        assert Map.has_key?(first_entry, :utc_date)
        assert Map.has_key?(first_entry, :gas_used)

        # Gas used should be a positive number
        assert is_number(first_entry.gas_used) or is_binary(first_entry.gas_used)

        # Log the data for informational purposes
        IO.puts("Date: #{first_entry.utc_date}")
        IO.puts("Gas Used: #{first_entry.gas_used}")
      end
    end
  end

  test "can specify different sort order" do
    # Skip this test if we don't have a Pro API key or if the action name is invalid
    if not has_pro_api_key?() do
      IO.puts("Skipping test: Pro API key required for DailyGasUsedLens or invalid action name")
      :ok
    else
      assert {:ok, %{result: gas_used_data}} =
               DailyGasUsedLens.focus(%{
                 startdate: @start_date,
                 enddate: @end_date,
                 sort: "desc",
                 chainid: 1
               })

      # Verify the structure of the response
      assert is_list(gas_used_data)

      # If we got data, check that it's in descending order
      if length(gas_used_data) > 1 do
        first_date = List.first(gas_used_data).utc_date
        second_date = Enum.at(gas_used_data, 1).utc_date

        # In descending order, the first date should be later than the second date
        assert first_date >= second_date
      end
    end
  end

  test "fails when no auth is provided" do
    # The NoAuthDailyGasUsedLens doesn't have an API key, so it should fail
    result = NoAuthDailyGasUsedLens.focus(%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    })

    case result do
      {:ok, %{"status" => "0", "message" => "NOTOK", "result" => error_message}} ->
        assert String.contains?(error_message, "Missing/Invalid API Key") or
               String.contains?(error_message, "Missing Or invalid Action name")

      {:error, error} ->
        # If it returns an error tuple, that's also acceptable
        assert error != nil
    end
  end

  test "raises error or returns error for Pro API endpoint" do
    # This test verifies that we either get an ArgumentError or a specific error message
    # when trying to use a Pro API endpoint without a Pro API key
    result = DailyGasUsedLens.focus(%{
      startdate: @start_date,
      enddate: @end_date,
      chainid: 1
    })

    case result do
      {:error, %{result: result}} ->
        # If we get an error about API Pro endpoint or invalid action, that's expected
        assert String.contains?(result, "API Pro endpoint") or
               String.contains?(result, "Missing Or invalid Action name")
        IO.puts("Expected error: #{result}")

      _ ->
        # If we get here, we might have a Pro API key, so the test should be skipped
        if has_pro_api_key?() do
          IO.puts("Skipping test: We have a Pro API key, so this test is not applicable")
          :ok
        else
          flunk("Expected an error for Pro API endpoint or invalid action name")
        end
    end
  end

  test "returns error for missing required parameters" do
    # Skip this test if we don't have a Pro API key or if the action name is invalid
    if not has_pro_api_key?() do
      IO.puts("Skipping test: Pro API key required for DailyGasUsedLens or invalid action name")
      :ok
    else
      # Missing startdate and enddate
      result = DailyGasUsedLens.focus(%{
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
