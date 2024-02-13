
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule Vote do

def accept_leader(server, term, q) do
  server = if term > server.curr_term do
    # Accept that we are not a leader
    stepdown(server, term)
    |> State.leaderP(q)
    |> Log.append_election("Accepting leader #{inspect(q)}")
  else
    server
  end
  # Send a reply telling a server they are behind
  if term < server.curr_term do
    send q, { :APPEND_ENTRIES_REPLY, server.curr_term, false}
  end
  server
end

def election_timeout(server) do
  if server.role == :FOLLOWER or server.role == :CANDIDATE do
    # Start an election ((c) a period of times goes by without winner)
    server = server
    |> Timer.restart_election_timer()
    |> State.inc_term()
    |> State.role(:CANDIDATE)
    |> State.voted_for(server.selfP)
    |> State.new_voted_by()
    |> State.add_to_voted_by(server.selfP)
    |> Timer.cancel_all_append_entries_timers()

    # Timeout everyone else so they can vote for me
    Enum.each(server.servers, fn s ->
      send self(), { :APPEND_ENTRIES_TIMEOUT, %{term: server.curr_term, followerP: s }}
    end)
    server
  else
    # We are already leader, no need for another election
    server
    |> Timer.restart_election_timer() # TODO: Need to reset timer? or can I ignore election timers as I am leader?
  end
end

def rpc_timeout(server, q) do
  if server.role == :CANDIDATE do
    send q, { :VOTE_REQUEST, server.curr_term, server.selfP, 0, "" }
    server
    |> Timer.restart_append_entries_timer(q)
  else
    server
  end
end

def vote_req(server, term, q, _lastLogIndex, _lastLogTerm) do
  server = if term > server.curr_term do
    stepdown(server, term)
  else
    server
  end
  if term == server.curr_term and
    (server.voted_for == nil or server.voted_for == server.selfP) do
    send q, { :VOTE_REPLY, term, server.selfP, q } # ?
    server
    |> State.voted_for(q)
    |> Timer.restart_election_timer()
  else
    server
  end
end

def vote_rep(server, term, q, vote) do
  server = if term > server.curr_term do
    stepdown(server, term)
  else
    server
  end
  if term == server.curr_term and server.role == :CANDIDATE do
    server = if vote == server.selfP do
      State.add_to_voted_by(server, q)
    else
      server
    end
    server = server |> Timer.cancel_append_entries_timer(q)
    if State.vote_tally(server) > server.majority do
      # (a) We win the election and become leader
      IO.puts("***************************\n\n   NEW LEADER - #{server.config.node_name}\n\n***************************")
      server = server
      |> State.role(:LEADER)
      |> State.leaderP(server.selfP)
      # Notify all other servers we are the leader now
      Enum.each(server.servers -- [server.selfP],
      fn s ->
        send s, { :APPEND_ENTRIES_REQUEST, %{term: server.curr_term, msg: :I_AM_LEADER, followerP: server.selfP}}
      end)
      server
    else
      server
    end
  else
    server
  end
end

defp stepdown(server, term) do
  server
  |> State.curr_term(term)
  |> State.role(:FOLLOWER)
  |> State.voted_for(nil)
  |> Timer.restart_election_timer()
  |> Log.append_election("Stepping down (term #{term})")
end
end # Vote
