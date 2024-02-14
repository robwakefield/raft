# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule Server do
  # _________________________________________________________ Server.start()
  def start(config, server_num) do
    config =
      config
      |> Configuration.node_info("Server", server_num)
      |> Debug.node_starting()

    receive do
      {:BIND, servers, databaseP} ->
        config
        |> State.initialise(server_num, servers, databaseP)
        |> Timer.restart_election_timer()
        |> Server.next()
    end

    # receive
  end

  # start

  # _________________________________________________________ next()
  def next(server) do
    # invokes functions in AppendEntries, Vote, ServerLib etc

    server =
      receive do
        {:APPEND_ENTRIES_REQUEST,
         %{
           term: term,
           leaderId: leaderId,
           prevLogIndex: prevLogIndex,
           prevLogTerm: prevLogTerm,
           entries: entries,
           leaderCommit: leaderCommit,
           sender: sender
         }} ->
          # { :APPEND_ENTRIES_REQUEST, body } ->
          server
          |> Debug.received(":APPEND_ENTRIES_REQUEST, #{inspect(sender)}")
          |> Vote.accept_leader(term, sender, leaderId, leaderCommit, prevLogTerm, prevLogIndex)

        {:APPEND_ENTRIES_REPLY, term, msg} ->
          IO.puts("APPEND_ENTRIES #{inspect(msg)}")
          server

        {:APPEND_ENTRIES_TIMEOUT, %{term: _term, followerP: sender}} ->
          server
          |> Debug.received(":APPEND_ENTRIES_TIMEOUT, #{inspect(sender)}")
          |> Vote.rpc_timeout(sender)

        {:VOTE_REQUEST, term, sender, lastLogIndex, lastLogTerm} ->
          server
          |> Debug.received(
            ":VOTE_REQUEST, #{term}, #{inspect(sender)}, #{"lastLogIndex"}, #{"lastLogTerm"}"
          )
          |> Vote.vote_req(term, sender, lastLogIndex, lastLogTerm)

        {:VOTE_REPLY, term, sender, vote} ->
          server
          |> Debug.received(":VOTE_REPLY #{term} #{inspect(sender)} #{inspect(vote)}")
          |> Vote.vote_rep(term, sender, vote)

        {:ELECTION_TIMEOUT, %{term: _, election: _}} ->
          server
          |> Debug.received(":ELECTION TIMEOUT")
          |> Vote.election_timeout()

        {:CLIENT_REQUEST, %{cmd: cmd, clientP: clientP, cid: cid} = body} ->
          server
          |> Debug.received(":CLIENT_REQUEST")

        unexpected ->
          Helper.node_halt("***** Server: unexpected message #{inspect(unexpected)}")
      end

    # receive

    # if map_size(server.log) < 10 do
    #   server |> Server.next()
    # end
    server |> Server.next()
  end

  # next
end

# Server
