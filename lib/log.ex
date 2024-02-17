
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2

defmodule Log do

# implemented as a Map indexed from 1.

def new()                     do Map.new() end                      # used when process state is initialised
def new(server) do # not currently used
  server = server
  |> Map.put(:log, Map.new)
  Debug.message(server, "-log", "Reset Log: #{inspect(Log.get_entries_from(server, 1))}")
end
def new(server, log) do # only used below
  server
  |> Map.put(:log, log)
end

def last_index(server)        do map_size(server.log) end
def entry_at(server, index)   do server.log[index] end
def request_at(server, index) do server.log[index].request end
def term_at(_server, 0)       do 0 end
def term_at(server, index)    do server.log[index].term end
def last_term(server)         do Log.term_at(server, Log.last_index(server)) end

def get_entries(server, range) do                 # e.g return server.log[3..5]
  Map.take(server.log, Enum.to_list(range))
  # equivalent to
  #   for k <- range.first .. range.last // 1, into: Map.new do {k, Log.entry_at(server, k)} end
end

def get_entries_from(server, from) do               # e.g return server.log[3..]
  for k <- from .. Log.last_index(server) // 1, into: Map.new do
    {k, Log.entry_at(server, k)}
  end
end

def append_request(server, term, req) do
  append_entry(server, %{term: term, request: req})
end

def append_entry(server, entry) do
  server = server
  |> Log.new(Map.put(server.log, Log.last_index(server)+1, entry))
  Debug.message(server, "+log", "Adding #{inspect(entry)} Log: #{inspect(Log.get_entries_from(server, 1))}")
end

def merge_entries(server, entries) do
  server = server
  |> Log.new(Map.merge(server.log, entries))
  Debug.message(server, "+log", "Merged #{inspect(entries)} Log: #{inspect(Log.get_entries_from(server, 1))}")
end

def delete_entries(server, range) do                 # e.g. delete server.log[3..5] keep rest
  server = server
  |> Log.new(Map.drop(server.log, Enum.to_list(range)))
  Debug.message(server, "-log", "Delete range #{inspect(range)} Log: #{inspect(Log.get_entries_from(server, 1))}")
end

def delete_entries_from(server, from) do             # delete server.log[from..last] keep rest
  server = server
  |> Log.delete_entries(from .. Log.last_index(server) // 1 )
  Debug.message(server, "-log", "Delete from #{inspect(from)} Log: #{inspect(Log.get_entries_from(server, 1))}")
end

end # Log
