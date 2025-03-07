defmodule Lux.Lenses.Etherscan.TokenErc1155AddressContractTx do
  @moduledoc """
  Lens for fetching ERC-1155 (Multi Token Standard) token transfer events for a specific address filtered by a token contract from the Etherscan API.

  ## Examples

  ```elixir
  # Get ERC-1155 transfers for an address filtered by a token contract
  Lux.Lenses.Etherscan.TokenErc1155AddressContractTx.focus(%{
    address: "0x83f564d180b58ad9a02a449105568189ee7de8cb",
    contractaddress: "0x76be3b62873462d2142405439777e971754e8e77"
  })

  # With additional parameters
  Lux.Lenses.Etherscan.TokenErc1155AddressContractTx.focus(%{
    address: "0x83f564d180b58ad9a02a449105568189ee7de8cb",
    contractaddress: "0x76be3b62873462d2142405439777e971754e8e77",
    chainid: 1,
    startblock: 0,
    endblock: 27025780,
    page: 1,
    offset: 100,
    sort: "asc"
  })
  ```
  """

  alias Lux.Lenses.Etherscan.Base

  use Lux.Lens,
    name: "Etherscan.TokenErc1155AddressContractTx",
    description: "Retrieves ERC-1155 token transfers for a specific wallet address from a specific token contract",
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
          description: "Network identifier (1=Ethereum, 137=Polygon, 56=BSC, etc.)",
          default: 1
        },
        address: %{
          type: :string,
          description: "Wallet address to query for ERC-1155 token transfers (must be valid hex format)",
          pattern: "^0x[a-fA-F0-9]{40}$"
        },
        contractaddress: %{
          type: :string,
          description: "ERC-1155 token contract address to filter transfers by (must be valid hex format)",
          pattern: "^0x[a-fA-F0-9]{40}$"
        },
        startblock: %{
          type: :integer,
          description: "Starting block number to filter transfer events from",
          default: 0
        },
        endblock: %{
          type: :integer,
          description: "Ending block number to filter transfer events to",
          default: 99999999
        },
        page: %{
          type: :integer,
          description: "Page number for paginated results when many transfers exist",
          default: 1
        },
        offset: %{
          type: :integer,
          description: "Number of transfer records to return per page (max 10000)",
          default: 100
        },
        sort: %{
          type: :string,
          description: "Chronological ordering of results (asc=oldest first, desc=newest first)",
          enum: ["asc", "desc"],
          default: "asc"
        }
      },
      required: ["address", "contractaddress"]
    }

  @doc """
  Prepares parameters before making the API request.
  """
  def before_focus(params) do
    # Set module and action for this endpoint
    params
    |> Map.put(:module, "account")
    |> Map.put(:action, "token1155tx")
  end

  @doc """
  Transforms the API response into a more usable format.
  """
  @impl true
  def after_focus(response) do
    Base.process_response(response)
  end
end 