# Raft

## Configuration

In the [Makefile](./Makefile) there are a number of parameters that can be changed in order to simulate different system configurations.

### PARAMS

See [configuration.ex](./lib/configuration.ex) for implementations of the following preset system configurations:
- **default**
- **slower**: Client requests happen once per second
- **leader_crash**: Simulate the current leader (optionally repeatedly) crashing
- **server_crash**: Simulate certain servers crashing for a determined amount of time before coming back online
- **client_stop**: Stop the clients from sending more than 1000 requests each
- **split_vote**: Sets the election timeout range size to 0 to induce split votes during elections
- **long**: Runs the entire system for 60 seconds, displaying the number of database updates every 30s. Useful for profiling the system under different configurations/conditions.

### DEBUG OPTIONS

Choose multiple from the following:
- `!inf`: Show information about the system, e.g. when a new leader is elected.
- `?rec`: Display all messages received by servers
- `+/-log`: (+) for Log additions. (-) for Log deletions
- `showlog`: Show the current log for each server when a database error occurs
- `+/-hb`: (+) for Heartbeat requests. (-) for Heartbeat replies
- `elec`: Show when servers start elections

Other debug options inherited from the inital code are (Plus (+) for send/send_after. Minus (-) for receiver): 

```
+areq -areq +arep -arep +vreq +vall -vreq +vrep -vrep +atim -atim +etim -etim +dreq -dreq +drep -drep -creq -crep
```

- AppendEntries(areq, arep, atim)
- Vote(vreq, vrep, vall), Election(etim)
- DB(dreq, drep), Client(creq, crep)

## Running

To run the cluster implementing the Raft algorithm, run `make`

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `raft` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:raft, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/raft>.

