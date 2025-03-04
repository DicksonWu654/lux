defmodule Lux.Lenses.Etherscan.TokenHolderCountLensTest do
  use UnitAPICase, async: false

  alias Lux.Lenses.Etherscan.TokenHolderCountLens

  setup do
    # Set up test API key in the configuration
    Application.put_env(:lux, :api_keys, [
      etherscan: "TEST_API_KEY",
      etherscan_pro: false
    ])

    on_exit(fn ->
      # Clean up after tests
      Application.delete_env(:lux, :api_keys)
    end)

    :ok
  end

  describe "focus/1" do
    test "makes correct API call and processes the response" do
      # Set up the test parameters
      params = %{
        contractaddress: "0xaaaebe6fe48e54f431b0c390cfaf0b017d09d42d",
        chainid: 1
      }

      # Mock the API response
      Req.Test.expect(Lux.Lens, fn conn ->
        # Verify the request
        assert conn.method == "GET"
        assert conn.request_path == "/v2/api"

        # Verify query parameters
        query = URI.decode_query(conn.query_string)
        assert query["module"] == "token"
        assert query["action"] == "tokenholdercount"
        assert query["contractaddress"] == "0xaaaebe6fe48e54f431b0c390cfaf0b017d09d42d"
        assert query["apikey"] == "TEST_API_KEY"

        # Return a mock response
        Req.Test.json(conn, %{
          "status" => "1",
          "message" => "OK",
          "result" => "12345"
        })
      end)

      # Call the lens
      result = TokenHolderCountLens.focus(params)

      # Verify the result
      assert {:ok, %{result: "12345", holder_count: "12345"}} = result
    end

    test "handles error responses" do
      # Set up the test parameters with invalid contract address
      params = %{
        contractaddress: "0xinvalid",
        chainid: 1
      }

      # Mock the API response
      Req.Test.expect(Lux.Lens, fn conn ->
        # Return an error response
        Req.Test.json(conn, %{
          "status" => "0",
          "message" => "Error",
          "result" => "Invalid contract address format"
        })
      end)

      # Call the lens
      result = TokenHolderCountLens.focus(params)

      # Verify the result
      assert {:error, %{message: "Error", result: "Invalid contract address format"}} = result
    end
  end

  describe "before_focus/1" do
    test "prepares parameters correctly" do
      # Set up the test parameters
      params = %{
        contractaddress: "0xaaaebe6fe48e54f431b0c390cfaf0b017d09d42d",
        chainid: 1
      }

      # Call the function
      result = TokenHolderCountLens.before_focus(params)

      # Verify the result
      assert result.module == "token"
      assert result.action == "tokenholdercount"
      assert result.contractaddress == "0xaaaebe6fe48e54f431b0c390cfaf0b017d09d42d"
      assert result.chainid == 1
    end
  end

  describe "after_focus/1" do
    test "processes successful response" do
      # Create a mock response
      response = %{
        "status" => "1",
        "message" => "OK",
        "result" => "12345"
      }

      # Call the function
      result = TokenHolderCountLens.after_focus(response)

      # Verify the result
      assert {:ok, %{result: "12345", holder_count: "12345"}} = result
    end

    test "processes error response" do
      # Create a mock error response
      response = %{
        "status" => "0",
        "message" => "Error",
        "result" => "Invalid contract address format"
      }

      # Call the function
      result = TokenHolderCountLens.after_focus(response)

      # Verify the result
      assert {:error, %{message: "Error", result: "Invalid contract address format"}} = result
    end
  end
end
