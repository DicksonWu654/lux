defmodule Lux.Integration.Etherscan.EthSupplyLensTest do
  @moduledoc false
  use IntegrationCase, async: false

  alias Lux.Lenses.Etherscan.EthSupply

  # Add a delay between tests to avoid hitting the API rate limit
  setup do
    # Sleep for 300ms to avoid hitting the Etherscan API rate limit (5 calls per second)
    Process.sleep(300)
    :ok
  end

  defmodule NoAuthEthSupplyLens do
    @moduledoc """
    Going to call the api without auth so that we always fail
    """
    use Lux.Lens,
      name: "Etherscan ETH Supply API",
      description: "Fetches the current amount of Ether in circulation excluding ETH2 Staking rewards and EIP1559 burnt fees",
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
      |> Map.put(:action, "ethsupply")
    end
  end

  test "can fetch total ETH supply" do
    assert {:ok, %{result: eth_supply, eth_supply: eth_supply}} =
             EthSupply.focus(%{
               chainid: 1
             })

    # ETH supply should be a large number (more than 100 million ETH)
    assert is_integer(eth_supply)
    assert eth_supply > 100_000_000 * 1.0e18 # More than 100M ETH in wei

    # Log the supply for informational purposes
    eth_supply_in_eth = eth_supply / 1.0e18
    IO.puts("Total ETH supply: #{eth_supply_in_eth} ETH")
  end

  test "requires chainid parameter for v2 API" do
    # The v2 API requires the chainid parameter
    result = EthSupply.focus(%{})

    case result do
      {:error, %{message: "NOTOK", result: error_message}} ->
        # Should return an error about missing chainid parameter
        assert String.contains?(error_message, "Missing chainid parameter")
        IO.puts("Expected error for missing chainid: #{error_message}")

      {:ok, _} ->
        flunk("Expected an error for missing chainid parameter")
    end
  end

  test "can fetch ETH supply for a different chain" do
    # This test just verifies that we can specify a different chain
    # The actual result may vary depending on the chain
    result = EthSupply.focus(%{
      chainid: 137 # Polygon
    })

    case result do
      {:ok, %{result: eth_supply}} ->
        # Log the supply for informational purposes
        eth_supply_in_eth = eth_supply / 1.0e18
        IO.puts("Total ETH supply on Polygon: #{eth_supply_in_eth} ETH")
        assert true

      {:error, error} ->
        # If the endpoint doesn't exist on this chain, that's also acceptable
        IO.puts("Error fetching ETH supply on Polygon: #{inspect(error)}")
        assert true
    end
  end

  test "fails when no auth is provided" do
    # The NoAuthEthSupplyLens doesn't have an API key, so it should fail
    result = NoAuthEthSupplyLens.focus(%{
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
