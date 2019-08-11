defmodule Tmate.MasterEndpoint do
  defmodule Null do
    def emit_event(_, _, _ \\ %{}), do: :ok
    def ping_master, do: :ping
  end

  def emit_event(event_type, entity_id, params \\ %{}) do
    call_master({:event, current_timestamp(), event_type, entity_id, params})
  end

  def identify_client(token, username, ip_address, pubkey) do
    call_master({:identify_client, token, username, ip_address, pubkey})
  end

  def ping_master do
    {:ok, master_options} = Application.fetch_env(:tmate, :master)
    results = master_options[:nodes] |> Enum.map(fn(name) ->
      name = name |> to_string
      if String.contains?(name, "@") do
        Node.ping(name |> String.to_atom)
      else
        host = node() |> to_string |> String.split("@") |> Enum.at(1)
        Node.ping("#{name}@#{host}" |> String.to_atom)
      end
    end)

    case results |> Enum.any?(& &1 == :pong) do
      false -> :pang
      true -> :ping
    end
  end

  defp call_master_once(args) do
    case :pg2.get_closest_pid(pg2_namespace()) do
      {:error, err} -> {:error, err}
      pid ->
        ref = Process.monitor(pid)
        send(pid, {:call, ref, self(), args})
        receive do
          {:DOWN, ^ref, _type, _pid, _info} -> {:error, :noproc}
          {:reply, ^ref, ret} ->
            Process.demonitor(ref, [:flush])
            {:reply, ret}
        end
    end
  end

  defp call_master(args, tries \\ 10, retry_timeout \\ 500) do
    case call_master_once(args) do
      {:reply, ret} -> ret
      {:error, err} ->
        case tries do
          0 -> {:error, err}
          _ ->
            :timer.sleep(retry_timeout)
            ping_master()
            call_master(args, tries - 1, retry_timeout)
        end
    end
  end

  defp current_timestamp() do
    DateTime.truncate(DateTime.utc_now, :second)
  end

  defp pg2_namespace do
    {:tmate, :master}
  end
end
