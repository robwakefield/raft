
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule ServerLib do

# Library of functions called by other server-side modules

def stepdown(server, term) do
  server
  |> State.curr_term(term)
  |> State.role(:FOLLOWER)
  |> State.voted_for(nil)
  |> Timer.restart_election_timer()
end

def send_heartbeat(server) do
  Enum.each(server.servers -- [server.selfP],
  fn s ->
    send s, { :APPEND_ENTRIES_REQUEST, %{
      term: server.curr_term,
      leaderId: server.selfP,
      prevLogIndex: Log.last_index(server),
      prevLogTerm: Log.last_term(server),
      entries: [],
      leaderCommit: server.commit_index,
      sender: server.selfP } }
  end)
  Process.send_after(self(), { :APPEND_ENTRIES_TIMEOUT, %{term: server.curr_term, followerP: server.selfP} }, 5)
  server
  |> Timer.restart_append_entries_timer(server.selfP)
end

end # ServerLib
