# Rob Wakefield (rgw20)

# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule ClientRequest do

# Handle receieving a client request
def handle_request(server, req) do
  unless server.role == :LEADER do
    #send req.clientP, { :CLIENT_REPLY, %{cid: req.cid, reply: :NOT_LEADER, leaderP: server.leaderP} }
    server |> forward(req)
  else
    case req do
      %{cmd: _, clientP: _, cid: cid} ->
        # Check that this client request has not already been seen
        if MapSet.member?(server.seen, cid) do
          server
        else
          server = server
          |> State.seen(cid)
          |> Log.append_request(server.curr_term, req)

          Enum.reduce(server.servers -- [server.selfP], server,
          fn q, server ->
            server |> AppendEntries.sendAppendEntries(q)
          end)
          |> Monitor.send_msg({ :CLIENT_REQUEST, server.server_num })
          |> Debug.received(":CLIENT_REQUEST #{inspect(req)}")
        end

      unexpected ->
        Helper.node_halt("***** Server: unexpected message #{inspect(unexpected)}")
    end
  end
end

# Forward the client request to the leader
def forward(server, req) do
  # send back to ourselves if we don't know who the leader is yet
  dest = unless server.leaderP == nil do server.leaderP else self() end
  send dest, { :CLIENT_REQUEST, req }

  if dest == self() do
    server
  else
    server |> Debug.message("client", "Forwarding to leader(#{inspect(dest)}) #{inspect(req)}")
  end
end

# Send a reply back to the client with the response from the DB
def send_reply(server, index, response) do
  req = Map.get(server.applied, index)
  send req.clientP, { :CLIENT_REPLY, %{cid: req.cid, reply: response, leaderP: server.selfP} }
  server
end

end # ClientRequest
