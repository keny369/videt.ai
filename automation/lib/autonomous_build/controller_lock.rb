# frozen_string_literal: true

module AutonomousBuild
  # The controller run lock (mandate §12). A single-instance advisory file lock ensures two
  # autonomous runs cannot operate on the same build state simultaneously. It is non-blocking: a
  # second run does not queue behind the first — it fails fast with LockError so duplicate execution
  # is locked out rather than silently serialised. The lock releases if the holding process dies.
  class ControllerLock
    attr_reader :path

    def initialize(path)
      @path = path
      @handle = nil
    end

    # Acquire the lock or raise LockError. Records the holder pid + timestamp for diagnostics.
    def acquire
      FileUtils.mkdir_p(File.dirname(@path))
      handle = File.open(@path, File::RDWR | File::CREAT, 0o644)
      unless handle.flock(File::LOCK_EX | File::LOCK_NB)
        handle.close
        raise LockError, "another controller run holds the lock (#{@path}); duplicate execution is locked out"
      end
      handle.truncate(0)
      handle.write("#{Process.pid} #{Time.now.utc.iso8601}\n")
      handle.flush
      @handle = handle
      self
    end

    def held? = !@handle.nil?

    def release
      return unless @handle

      @handle.flock(File::LOCK_UN)
      @handle.close
      @handle = nil
    end

    # Run the block while holding the lock; always release afterwards.
    def with_lock
      acquire
      yield self
    ensure
      release
    end
  end
end
