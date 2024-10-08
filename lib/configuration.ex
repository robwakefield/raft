# Rob Wakefield (rgw20)

###
# See below for extra configuration params implemented
###

# distributed algorithms, n.dulay, 14 jan 2024
# raft, configuration parameters v2

defmodule Configuration do

# _________________________________________________________ node_init()
def node_init() do
  # get node arguments and spawn a process to exit node after max_time
  config =
  %{
    node_suffix:     Enum.at(System.argv, 0),
    raft_timelimit:  String.to_integer(Enum.at(System.argv, 1)),
    debug_level:     String.to_integer(Enum.at(System.argv, 2)),
    debug_options:   "#{Enum.at(System.argv, 3)}",
    n_servers:       String.to_integer(Enum.at(System.argv, 4)),
    n_clients:       String.to_integer(Enum.at(System.argv, 5)),
    params_function: :'#{Enum.at(System.argv, 6)}',
    start_function:  :'#{Enum.at(System.argv, 7)}',
  }

  if config.n_servers < 3 do
    Helper.node_halt("Raft is unlikely to work with fewer than 3 servers")
  end # if

  spawn(Helper, :node_exit_after, [config.raft_timelimit])

  config |> Map.merge(Configuration.params(config.params_function))
end # node_init

# _________________________________________________________ node_info()
def node_info(config, node_type, node_num \\ "") do
  Map.merge config,
  %{
    node_type:     node_type,
    node_num:      node_num,
    node_name:     "#{node_type}#{node_num}",
    node_location: Helper.node_string(),
    line_num:      0,  # for ordering output lines
  }
end # node_info

# _________________________________________________________ params :default ()
def params :default do
  %{
    n_accounts:              100,      # account numbers 1 .. n_accounts
    max_amount:              1_000,    # max amount moved between accounts in a single transaction

    client_timelimit:        60_000,   # clients stops sending requests after this time(ms)
    max_client_requests:     5000,     # maximum no of requests each client will attempt
    client_request_interval: 1,        # interval(ms) between client requests
    client_reply_timeout:    50,       # timeout(ms) for the reply to a client request

    election_timeout_range:  100..200, # timeout(ms) for election, set randomly in range
    append_entries_timeout:  10,       # timeout(ms) for the reply to a append_entries request

    monitor_interval:        1000,     # interval(ms) between monitor summaries

    crash_servers: %{		       # server_num => crash_after_time (ms), ..
      # 3 => 5_000,
      # 4 => 8_000,
    },
    crash_durations: %{		     # server_num => time until servers comes back online
      # 3 => 5_000,
      # 4 => 8_000,
    },

    crash_leaders_after:      nil,    # nil or time after which leaders will crash
    crash_leaders_repeat:      nil,
    crash_leaders_duration:      nil,

  }
end # params :default


# add further params functions for your own tests and experiments

# _________________________________________________________ params :slower
def params :slower do
  Map.merge (params :default),
  %{
    client_request_interval: 1_000,
    client_reply_timeout:    5_000,
    append_entries_timeout:  100,
  }
end # params :slower

# _________________________________________________________ params :leader_crash
def params :leader_crash do
  Map.merge (params :default),
  %{
    raft_timelimit:  15_000,
    n_servers:       5,
    n_clients:       3,

    crash_leaders_after:     1500,
    crash_leaders_repeat:    nil,
    crash_leaders_duration:  5000,

    client_timelimit:        11_000, # limit client requests so we can show eventual convergence
  }
end # params :slow

# _________________________________________________________ params :client_stop
def params :client_stop do
  Map.merge (params :default),
  %{
    max_client_requests:     1000,
  }
end # params :client_stop

# _________________________________________________________ params :server_crash
def params :server_crash do
  Map.merge (params :default),
  %{
    raft_timelimit:  15_000,
    n_servers:       5,
    n_clients:       3,

    crash_servers: %{
      3 => 1500,
      4 => 2000,
    },
    crash_durations: %{
      3 => 2000,
      4 => 100_000,
    },
    client_timelimit:        11_000, # limit client requests so we can show eventual convergence
  }
end # params :server_crash

# _________________________________________________________ params :split_vote
def params :split_vote do
  min_e = 150
  max_e = 150

  hb = floor(min_e / 2) # hb interval half of the minimum election timeout (see paper)

  Map.merge (params :default),
  %{
    raft_timelimit:  120_000,
    n_servers:       5,
    n_clients:       1,

    debug_options:           "time",
    no_print:                true, # don't print monitor updates

    append_entries_timeout:  hb,
    election_timeout_range:  min_e..max_e,

    crash_leaders_after:     500,
    crash_leaders_repeat:    500,
    crash_leaders_duration:  400,

    client_timelimit:        10, # Immediately quit client to ignore prevLogIndex check
  }
end # params :split_vote

# _________________________________________________________ params :long
def params :long do
  Map.merge (params :default),
  %{
    raft_timelimit:          60_000,
    client_timelimit:        60_000,
    debug_options:           "",

    monitor_interval:        30_000,
    max_client_requests:     100_000,
  }
end # params :long

end # Configuration

"""
def read_host_map(file_name) do      # read map of hosts for fully distributed execution via ssh
  # Format of lines
  #    line = <nodenum> <hostname> pair
  # returns Map of nodenum to hostname

  stream = File.stream!(file_name) |> Stream.map(&String.split/1)

  for [first, second | _] <- stream, into: Map.new do
    { (first |> String.to_integer), second }
  end # for
end # read_host_map
"""
