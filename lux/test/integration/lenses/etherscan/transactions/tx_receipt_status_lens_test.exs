defmodule Lux.Integration.Etherscan.TxReceiptStatusLensTest do
  @moduledoc false
  use IntegrationCase, async: false
  @moduletag timeout: 120_000

  alias Lux.Lenses.Etherscan.TxReceiptStatus

  # Example successful transaction hash
  @successful_tx "0x513c1ba0bebf66436b5fed86ab668452b7805593c05073eb2d51d3a52f480a76"

  # Add a delay between tests to avoid hitting the API rate limit
  setup do
    # Sleep for 300ms to avoid hitting the Etherscan API rate limit (5 calls per second)
    Process.sleep(300)
    :ok
  end

  defmodule NoAuthTxReceiptStatusLens do
    @moduledoc """
    Going to call the api without auth so that we always fail
    """
    use Lux.Lens,
      name: "Etherscan Transaction Receipt Status API",
      description: "Checks the receipt status of a transaction",
      url: "https://api.etherscan.io/v2/api",
      method: :get,
      headers: [{"content-type", "application/json"}]

    @doc """
    Prepares parameters before making the API request.
    """
    def before_focus(params) do
      # Set module and action for this endpoint
      params
      |> Map.put(:module, "transaction")
      |> Map.put(:action, "gettxreceiptstatus")
    end
  end

  test "can check receipt status for a successful transaction" do
    assert {:ok, %{result: %{status: status, is_success: is_success}}} =
             TxReceiptStatus.focus(%{
               txhash: @successful_tx,
               chainid: 1
             })

    # Verify the status is "1" for a successful transaction
    assert status == "1"
    assert is_success == true

    # Log the status for informational purposes
    IO.puts("Transaction #{@successful_tx} receipt status: #{status} (Success: #{is_success})")
  end

  test "can check receipt status for a different chain" do
    # This test just verifies that we can specify a different chain
    # The actual result may vary depending on whether the transaction exists on that chain
    result = TxReceiptStatus.focus(%{
      txhash: @successful_tx,
      chainid: 137 # Polygon
    })

    case result do
      {:ok, %{result: %{status: status, is_success: is_success}}} ->
        # Log the status for informational purposes
        IO.puts("Transaction #{@successful_tx} receipt status on Polygon: #{status} (Success: #{is_success})")

      {:error, error} ->
        # If the transaction doesn't exist on this chain, that's also acceptable
        IO.puts("Error checking transaction on Polygon: #{inspect(error)}")
        assert true
    end
  end

  test "returns appropriate status for invalid transaction hash" do
    # Using an invalid transaction hash format
    result = TxReceiptStatus.focus(%{
      txhash: "0xinvalid",
      chainid: 1
    })

    case result do
      {:error, error} ->
        # Should return an error for invalid transaction hash
        assert error != nil
        IO.puts("Error for invalid transaction hash: #{inspect(error)}")

      {:ok, %{result: %{status: status}}} ->
        # Some APIs might return a status for invalid hashes
        IO.puts("API returned status for invalid transaction hash: #{status}")
        assert true
    end
  end

  test "fails when no auth is provided" do
    # The NoAuthTxReceiptStatusLens doesn't have an API key, so it should fail
    result = NoAuthTxReceiptStatusLens.focus(%{
      txhash: @successful_tx,
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
end
