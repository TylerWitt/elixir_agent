defmodule NewRelic.Util do
  @moduledoc false

  alias NewRelic.Util.Vendor

  def hostname do
    maybe_heroku_dyno_hostname() || get_hostname()
  end

  def pid, do: System.pid() |> String.to_integer()

  def time_to_ms({megasec, sec, microsec}),
    do: (megasec * 1_000_000 + sec) * 1_000 + round(microsec / 1_000)

  def process_name(pid) do
    case Process.info(pid, :registered_name) do
      nil -> nil
      {:registered_name, []} -> nil
      {:registered_name, name} -> name
    end
  rescue
    # `Process.info/2` will raise when given a pid from a remote node
    ArgumentError -> nil
  end

  def metric_join(segments) when is_list(segments) do
    for segment <- segments, segment do
      segment
      |> to_string()
      |> String.replace_leading("/", "")
      |> String.replace_trailing("/", "")
    end
    |> Enum.join("/")
  end

  def deep_flatten(attrs) when is_list(attrs) do
    Enum.flat_map(attrs, &deep_flatten/1)
  end

  def deep_flatten({key, list_value}) when is_list(list_value) do
    list_value
    |> Enum.slice(0..9)
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, index} -> deep_flatten({"#{key}.#{index}", v}) end)
    |> Enum.concat([{"#{key}.length", length(list_value)}])
  end

  def deep_flatten({key, %{__struct__: _} = value}) do
    [{key, value}]
  end

  def deep_flatten({key, map_value}) when is_map(map_value) do
    map_value
    |> Enum.slice(0..9)
    |> Enum.flat_map(fn {k, v} -> deep_flatten({"#{key}.#{k}", v}) end)
    |> Enum.concat([{"#{key}.size", map_size(map_value)}])
  end

  def deep_flatten({key, value}) do
    [{key, value}]
  end

  def coerce_attributes(attrs) when is_map(attrs) do
    do_coerce_attributes(attrs) |> Map.new()
  end

  def coerce_attributes(attrs) when is_list(attrs) do
    do_coerce_attributes(attrs)
  end

  defp do_coerce_attributes(attrs) do
    for {key, value} <- attrs, not is_nil(value), value != "" do
      {key, coerce_value(key, value)}
    end
  end

  defp coerce_value(_key, value) when is_number(value), do: value
  defp coerce_value(_key, value) when is_boolean(value), do: value

  defp coerce_value(_key, value) when is_bitstring(value) do
    if String.valid?(value) do
      value
    else
      "[BINARY_VALUE]"
    end
  end

  defp coerce_value(_key, value) when is_reference(value) or is_pid(value) or is_port(value) do
    inspect(value)
  end

  defp coerce_value(_key, value) when is_atom(value), do: to_string(value)

  defp coerce_value(_key, %struct{} = value) when struct in [Date, DateTime, Time, NaiveDateTime] do
    struct.to_iso8601(value)
  end

  defp coerce_value(key, value) do
    NewRelic.log(:debug, "Bad attribute value: #{inspect(key)} => #{inspect(value)}")
    "[BAD_VALUE]"
  end

  def elixir_environment() do
    build_info = System.build_info()

    [
      ["Language", "Elixir"],
      ["Elixir Version", build_info[:version]],
      ["Elixir build", build_info[:build]],
      ["OTP Version", :erlang.system_info(:otp_release) |> to_string],
      ["ERTS Version", :erlang.system_info(:version) |> to_string]
    ]
  end

  @nr_metadata_prefix "NEW_RELIC_METADATA_"
  def metadata() do
    System.get_env()
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, @nr_metadata_prefix) end)
    |> Map.new()
  end

  def utilization() do
    %{
      metadata_version: 5,
      logical_processors: :erlang.system_info(:logical_processors),
      total_ram_mib: NewRelic.OsMon.get_system_memory(),
      hostname: hostname()
    }
    |> maybe_add_ip_addresses
    |> maybe_add_fqdn
    |> maybe_add_linux_boot_id()
    |> Vendor.maybe_add_vendors()
  end

  defp maybe_heroku_dyno_hostname do
    System.get_env("DYNO")
    |> case do
      nil -> nil
      "scheduler." <> _ -> "scheduler.*"
      "run." <> _ -> "run.*"
      name -> name
    end
  end

  defp maybe_add_linux_boot_id(util) do
    case File.read("/proc/sys/kernel/random/boot_id") do
      {:ok, boot_id} -> Map.put(util, "boot_id", boot_id)
      _ -> util
    end
  end

  defp maybe_add_ip_addresses(util) do
    case :inet.getif() do
      {:ok, addrs} ->
        ip_address = Enum.map(addrs, fn {ip, _, _} -> to_string(:inet.ntoa(ip)) end)
        Map.put(util, :ip_address, ip_address)

      _ ->
        util
    end
  end

  defp maybe_add_fqdn(util) do
    case :net_adm.dns_hostname(:net_adm.localhost()) do
      {:ok, fqdn} -> Map.put(util, :full_hostname, to_string(fqdn))
      _ -> util
    end
  end

  defp get_hostname do
    with {:ok, name} <- :inet.gethostname(), do: to_string(name)
  end

  def path_match?(_path, []), do: false

  def path_match?(path, path_set) do
    Enum.any?(path_set, fn
      string when is_binary(string) -> path == string
      %Regex{} = regex -> path =~ regex
      _ -> false
    end)
  end

  def uuid4() do
    "#{u(4)}-#{u(2)}-4a#{u(1)}-#{u(2)}-#{u(6)}"
  end

  defp u(len) do
    :crypto.strong_rand_bytes(len)
    |> Base.encode16(case: :lower)
  end
end
