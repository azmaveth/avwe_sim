# The kernel runs in processes and keeps files; a test that simulates for a while is
# seconds of CPU on a fast machine and can be most of a minute on a busy CI runner.
ExUnit.start(timeout: 180_000)
