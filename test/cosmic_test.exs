defmodule CosmicTest do
  use ExUnit.Case
  doctest Cosmic

  test "greets the world" do
    assert Cosmic.hello() == :world
  end
end
