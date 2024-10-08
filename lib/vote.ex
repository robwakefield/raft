# Rob Wakefield (rgw20)

# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule Vote do

def election_timeout(server, _term, _election) do
  if server.role == :FOLLOWER or server.role == :CANDIDATE do
    # Start a new election
    server = server
    |> Timer.restart_election_timer()
    |> State.inc_term()
    |> State.role(:CANDIDATE)
    |> State.voted_for(server.selfP)
    |> State.new_voted_by()
    |> State.add_to_voted_by(server.selfP)
    |> Timer.cancel_all_append_entries_timers()
    |> Debug.message("elec", "Starting an election!")

    # Timeout everyone else so I can send them a vote req
    Enum.each(server.servers -- [server.selfP], fn s ->
      send self(), { :APPEND_ENTRIES_TIMEOUT, %{term: server.curr_term, followerP: s }}
    end)

    server
  else
    # We are already leader, no need for another election
    server
  end
end

def send_request(server, q) do
  lastLogIndex = Log.last_index(server)
  lastLogTerm = Log.last_term(server)

  send q, { :VOTE_REQUEST, server.curr_term, server.selfP, lastLogIndex, lastLogTerm }

  server
  |> Timer.restart_append_entries_timer(q)
end

def handle_request(server, term, q, lastLogIndex, lastLogTerm) do
  server = server |> ServerLib.stepdown_if_behind(term)

  if term == server.curr_term
    and (server.voted_for == nil or server.voted_for == q)
    and (lastLogTerm > Log.last_term(server)
        or (lastLogTerm == Log.last_term(server)
            and lastLogIndex >= Log.last_index(server)))
  do
    send q, { :VOTE_REPLY, term, server.selfP, q }

    server
    |> State.voted_for(q)
    |> Timer.restart_election_timer()
  else
    server
  end
end

def handle_reply(server, term, q, vote) do
  server = server |> ServerLib.stepdown_if_behind(term)

  if term == server.curr_term and server.role == :CANDIDATE do
    server = if vote == server.selfP do
      State.add_to_voted_by(server, q)
    else
      server
    end

    server = server |> Timer.cancel_append_entries_timer(q)

    if State.vote_tally(server) >= server.majority do
      # (a) We win the election and become leader
      server
      |> State.role(:LEADER)
      |> State.leaderP(server.selfP)
      |> State.init_next_index()
      |> State.init_match_index()
      |> Debug.info("NEW LEADER - #{server.config.node_name}")
      |> Debug.message("time", "NEW LEADER - #{server.config.node_name}      @ #{:os.system_time(:millisecond)}")
      |> ServerLib.send_heartbeat()
    else
      server
    end

  else
    server
  end
end

end # Vote
