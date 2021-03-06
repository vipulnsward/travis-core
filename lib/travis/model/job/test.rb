require 'active_support/core_ext/hash/slice'
require 'simple_states'

class Job

  # Executes a test job (i.e. runs a test suite) remotely and keeps tabs about
  # state changes throughout its lifecycle in the database.
  #
  # Job::Test belongs to a Build as part of the build matrix and will be
  # created with the Build.
  class Test < Job
    include Sponsors, Tagging

    FINISHED_STATES = [:passed, :failed, :errored, :canceled]

    include SimpleStates, Travis::Event

    states :created, :queued, :started, :passed, :failed, :errored, :canceled

    event :start,   to: :started
    event :finish,  to: :finished, after: :add_tags
    event :reset,   to: :created, unless: :created?
    event :all, after: [:propagate, :notify]

    def enqueue # TODO rename to queue and make it an event, simple_states should support that now
      update_attributes!(state: :queued, queued_at: Time.now.utc)
      notify(:queue)
    end

    def start(data = {})
      log.update_attributes!(content: '') # TODO this should be in a restart method, right?
      data = data.symbolize_keys.slice(:started_at, :worker)
      data.each { |key, value| send(:"#{key}=", value) }
    end

    def finish(data = {})
      data = data.symbolize_keys.slice(:state, :finished_at)
      data.each { |key, value| send(:"#{key}=", value) }
    end

    def reset(*)
      self.state = :created
      attrs = %w(started_at queued_at finished_at worker)
      attrs.each { |attr| write_attribute(attr, nil) }
      if log
        log.clear!
      else
        build_log
      end
    end

    def cancelable?
      created?
    end

    def resetable?
      finished? && !invalid_config?
    end

    def invalid_config?
      config[:".result"] == "parse_error"
    end

    def finished?
      FINISHED_STATES.include?(state.to_sym)
    end

    def passed?
      state.to_s == "passed"
    end

    def failed?
      state.to_s == "failed"
    end

    def unknown?
      state == nil
    end

    def notify(event, *args)
      event = :create if event == :reset
      super
    end

    delegate :id, :content, :to => :log, :prefix => true, :allow_nil => true
  end
end
