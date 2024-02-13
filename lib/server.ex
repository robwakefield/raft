
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule Server do

# _________________________________________________________ Server.start()
def start(config, server_num) do

  config = config
    |> Configuration.node_info("Server", server_num)
    |> Debug.node_starting()

  receive do
    { :BIND, servers, databaseP } ->
      IO.puts("Started #{config.node_name}")
      config
      |> State.initialise(server_num, servers, databaseP)
      |> Timer.restart_election_timer()
      |> Server.next()
  end # receive
end # start

# _________________________________________________________ next()
def next(server) do

  # invokes functions in AppendEntries, Vote, ServerLib etc

  server = receive do

    { :APPEND_ENTRIES_REQUEST, %{term: term, msg: msg, followerP: sender}} ->
      # (b) another server has become a leader, we need to follow
      IO.puts("S#{server.server_num} received: #{msg} from #{inspect(sender)}")
      server
      |> Log.append_msg(":APPEND_ENTRIES_REQUEST, #{inspect(sender)} #{msg}")
      |> Vote.accept_leader(term, sender)

  # { :APPEND_ENTRIES_REPLY, ...

    { :APPEND_ENTRIES_TIMEOUT, %{term: _term, followerP: sender} } ->
      server
      |> Log.append_msg(":APPEND_ENTRIES_TIMEOUT, #{inspect(sender)}")
      |> Vote.rpc_timeout(sender)

    { :VOTE_REQUEST, term, sender, lastLogIndex, lastLogTerm } ->
      server
      |> Log.append_msg(":VOTE_REQUEST, #{term}, #{inspect(sender)}, #{"lastLogIndex"}, #{"lastLogTerm"}")
      |> Vote.vote_req(term, sender, lastLogIndex, lastLogTerm)

    { :VOTE_REPLY, term, sender, vote } ->
      server
      |> Log.append_msg(":VOTE_REPLY #{term} #{inspect(sender)} #{inspect(vote)}")
      |> Vote.vote_rep(term, sender, vote)

    { :ELECTION_TIMEOUT, %{term: _, election: _} } ->
      server
       |> Log.append_msg(":ELECTION TIMEOUT")
       |> Vote.election_timeout()

    { :CLIENT_REQUEST, _} ->
      #IO.puts(":CLIENT_REQUEST")
      server

   unexpected ->
      Helper.node_halt("***** Server: unexpected message #{inspect unexpected}")

  end # receive

  IO.puts(if map_size(server.log) > 0 do Log.last_entry(server) end)
  # if map_size(server.log) < 10 do
  #   server |> Server.next()
  # end
  server |> Server.next()



end # next

end # Server
