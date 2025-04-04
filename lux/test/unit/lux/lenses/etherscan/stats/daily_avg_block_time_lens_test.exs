defmodule Lux.Lenses.Etherscan.DailyAvgBlockTimeLensTest do
  use UnitAPICase, async: false

  alias Lux.Lenses.Etherscan.DailyAvgBlockTime

  setup do
    # Set up test API key in the configuration
    Application.put_env(:lux, :api_keys, [
      etherscan: "TEST_API_KEY",
      etherscan_pro: true
    ])



    :ok
  end

  describe "focus/1" do
    test "makes correct API call and processes the response with default sort parameter" do
      # Set up the test parameters
      params = %{
        startdate: "2019-02-01",
        enddate: "2019-02-28",
        chainid: 1
      }

      # Mock the API response
      Req.Test.expect(Lux.Lens, fn conn ->
        # Verify the request
        assert conn.method == "GET"
        assert conn.request_path == "/v2/api"

        # Verify query parameters
        query = URI.decode_query(conn.query_string)
        assert query["module"] == "stats"
        assert query["action"] == "dailyavgblocktime"
        assert query["startdate"] == "2019-02-01"
        assert query["enddate"] == "2019-02-28"
        assert query["sort"] == "asc"
        assert query["apikey"] == "TEST_API_KEY"

        # Return a mock response
        Req.Test.json(conn, %{
          "status" => "1",
          "message" => "OK",
          "result" => [
            %{
              "UTCDate" => "2019-02-01",
              "avgBlockTime" => "13.25"
            },
            %{
              "UTCDate" => "2019-02-02",
              "avgBlockTime" => "13.42"
            }
          ]
        })
      end)

      # Call the lens
      result = DailyAvgBlockTime.focus(params)

      # Verify the result
      assert {:ok, %{result: block_times}} = result
      assert length(block_times) == 2

      # Verify first day's data
      first_day = Enum.at(block_times, 0)
      assert first_day.date == "2019-02-01"
      assert first_day.avg_block_time_seconds == "13.25"

      # Verify second day's data
      second_day = Enum.at(block_times, 1)
      assert second_day.date == "2019-02-02"
      assert second_day.avg_block_time_seconds == "13.42"
    end

    test "makes correct API call and processes the response with 'desc' sort parameter" do
      # Set up the test parameters
      params = %{
        startdate: "2019-02-01",
        enddate: "2019-02-28",
        sort: "desc",
        chainid: 1
      }

      # Mock the API response
      Req.Test.expect(Lux.Lens, fn conn ->
        # Verify query parameters
        query = URI.decode_query(conn.query_string)
        assert query["sort"] == "desc"

        # Return a mock response
        Req.Test.json(conn, %{
          "status" => "1",
          "message" => "OK",
          "result" => [
            %{
              "UTCDate" => "2019-02-28",
              "avgBlockTime" => "13.15"
            },
            %{
              "UTCDate" => "2019-02-27",
              "avgBlockTime" => "13.22"
            }
          ]
        })
      end)

      # Call the lens
      result = DailyAvgBlockTime.focus(params)

      # Verify the result
      assert {:ok, %{result: block_times}} = result
      assert length(block_times) == 2

      # Verify first day's data (should be the latest date due to desc sorting)
      first_day = Enum.at(block_times, 0)
      assert first_day.date == "2019-02-28"
      assert first_day.avg_block_time_seconds == "13.15"
    end

    test "handles error responses" do
      # Set up the test parameters with invalid data
      params = %{
        startdate: "invalid-date",
        enddate: "2019-02-28",
        chainid: 1
      }

      # Mock the API response
      Req.Test.expect(Lux.Lens, fn conn ->
        # Return an error response
        Req.Test.json(conn, %{
          "status" => "0",
          "message" => "Error",
          "result" => "Invalid date format"
        })
      end)

      # Call the lens
      result = DailyAvgBlockTime.focus(params)

      # Verify the result
      assert {:error, %{message: "Error", result: "Invalid date format"}} = result
    end

    test "handles Pro API key errors" do
      # Set up test API key without Pro access
      Application.put_env(:lux, :api_keys, [
        etherscan: "TEST_API_KEY",
        etherscan_pro: false
      ])

      # Set up the test parameters
      params = %{
        startdate: "2019-02-01",
        enddate: "2019-02-28",
        chainid: 1
      }

      # Expect an ArgumentError to be raised
      assert_raise ArgumentError, "This endpoint requires an Etherscan Pro API key.", fn ->
        DailyAvgBlockTime.focus(params)
      end
    end
  end

  describe "before_focus/1" do
    test "prepares parameters correctly with default sort" do
      # Temporarily set Pro API key to true for this test
      Application.put_env(:lux, :api_keys, [
        etherscan: "TEST_API_KEY",
        etherscan_pro: true
      ])

      # Set up the test parameters without sort
      params = %{
        startdate: "2019-02-01",
        enddate: "2019-02-28",
        chainid: 1
      }

      # Call the function
      result = DailyAvgBlockTime.before_focus(params)

      # Verify the result
      assert result.module == "stats"
      assert result.action == "dailyavgblocktime"
      assert result.startdate == "2019-02-01"
      assert result.enddate == "2019-02-28"
      assert result.sort == "asc"
      assert result.chainid == 1
    end

    test "prepares parameters correctly with specified sort" do
      # Temporarily set Pro API key to true for this test
      Application.put_env(:lux, :api_keys, [
        etherscan: "TEST_API_KEY",
        etherscan_pro: true
      ])

      # Set up the test parameters with sort
      params = %{
        startdate: "2019-02-01",
        enddate: "2019-02-28",
        sort: "desc",
        chainid: 1
      }

      # Call the function
      result = DailyAvgBlockTime.before_focus(params)

      # Verify the result
      assert result.module == "stats"
      assert result.action == "dailyavgblocktime"
      assert result.startdate == "2019-02-01"
      assert result.enddate == "2019-02-28"
      assert result.sort == "desc"
      assert result.chainid == 1
    end

    test "raises error when Pro API key is not available" do
      # Temporarily set Pro API key to false
      Application.put_env(:lux, :api_keys, [
        etherscan: "TEST_API_KEY",
        etherscan_pro: false
      ])

      # Set up the test parameters
      params = %{
        startdate: "2019-02-01",
        enddate: "2019-02-28",
        chainid: 1
      }

      # Expect an error to be raised
      assert_raise ArgumentError, "This endpoint requires an Etherscan Pro API key.", fn ->
        DailyAvgBlockTime.before_focus(params)
      end
    end
  end

  describe "after_focus/1" do
    test "processes successful response" do
      # Create a mock response
      response = %{
        "status" => "1",
        "message" => "OK",
        "result" => [
          %{
            "UTCDate" => "2019-02-01",
            "avgBlockTime" => "13.25"
          },
          %{
            "UTCDate" => "2019-02-02",
            "avgBlockTime" => "13.42"
          }
        ]
      }

      # Call the function
      result = DailyAvgBlockTime.after_focus(response)

      # Verify the result
      assert {:ok, %{result: block_times}} = result
      assert length(block_times) == 2

      # Verify first day's data
      first_day = Enum.at(block_times, 0)
      assert first_day.date == "2019-02-01"
      assert first_day.avg_block_time_seconds == "13.25"

      # Verify second day's data
      second_day = Enum.at(block_times, 1)
      assert second_day.date == "2019-02-02"
      assert second_day.avg_block_time_seconds == "13.42"
    end

    test "processes error response" do
      # Create a mock error response
      response = %{
        "status" => "0",
        "message" => "Error",
        "result" => "Invalid date format"
      }

      # Call the function
      result = DailyAvgBlockTime.after_focus(response)

      # Verify the result
      assert {:error, %{message: "Error", result: "Invalid date format"}} = result
    end

    test "processes Pro API key error response" do
      # Create a mock Pro API key error response
      response = %{
        "status" => "0",
        "message" => "Error",
        "result" => "Invalid API Key"
      }

      # Call the function
      result = DailyAvgBlockTime.after_focus(response)

      # Verify the result
      assert {:error, %{message: "Error", result: "This endpoint requires an Etherscan Pro API key."}} = result
    end
  end
end
