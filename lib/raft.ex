# Rob Wakefield (rgw20)

###
# next(config, servers) function added to allow for sending of crash messages to servers
# Change marked with: CHANGES START ~ CHANGES END
###

# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule Raft do

# _________________________________________________________ Raft.start/0
def start do
  config = Configuration.node_init()
  Raft.start(config, config.start_function)
end # start/0

# _________________________________________________________ Raft.start/2
def start(_config, :cluster_wait) do :skip end

def start(config, :cluster_start) do
  # more initialisation
  config = config
  |> Configuration.node_info("Raft")
  |> Map.put(:monitorP, spawn(Monitor, :start, [config]))

  # create 1 database and 1 raft server in each server-node
  servers = for num <- 1 .. config.n_servers do
    Node.spawn(:'server#{num}_#{config.node_suffix}', Server, :start, [config, num])
  end # for

  send config.monitorP, {:SERVERS, servers}

  databases = for num <- 1 .. config.n_servers do
    Node.spawn(:'server#{num}_#{config.node_suffix}', Database, :start, [config, num])
  end # for

  # bind servers and databases
  for num <- 0 .. config.n_servers-1 do
    serverP   = Enum.at(servers, num)
    databaseP = Enum.at(databases, num)
    send serverP,   { :BIND, servers, databaseP }
    send databaseP, { :BIND, serverP }
  end # for

  # create 1 client in each client_node and bind to servers
  for num <- 1 .. config.n_clients do
    Node.spawn(:'client#{num}_#{config.node_suffix}', Client, :start, [config, num, servers])
  end # for

  # CHANGES START
  unless Map.get(config, :crash_leaders_after) == nil do
    Process.send_after(self(), { :LEADER_CRASH }, config.crash_leaders_after)
  end

  Enum.each(config.crash_servers,
  fn {n, delay} ->
    Process.send_after(self(), { :SERVER_CRASH, n }, delay)
  end)
  # CHANGES END

  next(config, servers)

end # start

# CHANGES START
defp next(config, servers) do
  receive do
    {:LEADER_CRASH} ->
      # Send a signal for the leader to crash
      Enum.each(servers,
      fn s ->
        send s, {:LEADER_CRASH}
      end)

      unless Map.get(config, :crash_leaders_repeat) == nil do
        Process.send_after(self(), { :LEADER_CRASH }, config.crash_leaders_repeat)
      end

    {:SERVER_CRASH, n} ->
      # Send a signal for the server to crash
      duration = Map.get(config.crash_durations, n)
      send Enum.at(servers, n - 1), {:SERVER_CRASH, duration}

    {:SHOW_LOG} ->
      # Send a signal to each server to print their log
      Enum.each(servers,
      fn s ->
        send s, {:SHOW_LOG}
      end)
      Process.send_after(self(), { :SHOW_LOG }, 300)
  end
  next(config, servers)
end
# CHANGES END

end # Raft
