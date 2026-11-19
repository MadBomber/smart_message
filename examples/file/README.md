# File Transport Examples

`SmartMessage::Transport::FileTransport` appends each published message to a file, one line of JSON per message (JSON Lines). Subscribing starts a background poller that tails the same file, so several transports or several processes can share one file: writers append, readers tail.

```bash
bundle exec ruby -Ilib examples/file/01_basic_file_transport_demo.rb
bundle exec ruby examples/run_all.rb file     # all of them
```

Each script checks its own result and exits non-zero when it is wrong. The files are written to a temporary directory that is removed when the script ends. See [`../README.md`](../README.md) for the runner and the shared helper.

## Examples

| Script | Shows |
|--------|-------|
| [`01_basic_file_transport_demo.rb`](01_basic_file_transport_demo.rb) | Publishing to a file, several message classes in one file, append-only behaviour, decoding a stored line, publishing to an IO, `disconnect` / `connect` |
| [`03_file_watching_demo.rb`](03_file_watching_demo.rb) | The tailing poller: `read_from_end:`, `poll_interval:`, several readers on one file, truncation, an undecodable line going to the dead letter queue |
| [`04_multi_transport_file_demo.rb`](04_multi_transport_file_demo.rb) | A file beside other transports: archiving, fan-out to two files, partial failure, choosing the file per message |

`00_run_all_file_demos.rb` runs `../run_all.rb file`.

There is no `02`: it demonstrated named pipes (FIFOs), which the file transport no longer supports.

The message classes are in [`messages/`](messages/), one class per file.

## Options

```ruby
SmartMessage::Transport::FileTransport.new(
  file_path:          'messages.jsonl',  # required: a path, or an IO to write to
  create_directories: true,              # create the file's directory
  encoding:           nil,               # file encoding; default: Ruby's default
  poll_interval:      0.5,               # seconds between checks for new lines
  read_from_end:      true               # a new subscription sees only lines written after it started
)

SmartMessage::Transport.create(:file, file_path: 'messages.jsonl')   # the same, through the registry
```

- `read_from_end: false` reads the whole file first, then tails it.
- An IO (`$stdout`, a `StringIO`) can be published to but not subscribed from, and the transport never closes it.
- A reader that finds the file shorter than what it has already consumed (truncated or replaced) starts again from the beginning.
- A line that cannot be decoded is stored in the dead letter queue and the poller continues with the next line.
- After `disconnect`, publishing fails until `connect` is called.

## Removed in 0.1.0

The 0.0.x file transport also had FIFO (named pipe) support, an asynchronous publish queue, file rotation, partitioned files, and several file watching modes, with the options `file_type`, `async`, `rotate_size`, `directory` and `subscription_mode`. All of these are gone.
